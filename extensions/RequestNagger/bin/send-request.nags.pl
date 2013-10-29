#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;

use FindBin qw($RealBin);
use lib "$RealBin/../../..";

use Bugzilla;
BEGIN { Bugzilla->extensions() }

use Bugzilla::Attachment;
use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Extension::RequestNagger::Constants;
use Bugzilla::Mailer;
use Bugzilla::User;
use Bugzilla::Util qw(format_time);
use Email::MIME;
use Sys::Hostname;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $DO_NOT_NAG = grep { $_ eq '-d' } @ARGV;

my $dbh = Bugzilla->dbh;
my $date = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
$date = format_time($date, '%a, %d %b %Y %T %z', 'UTC');

# delete expired defers
$dbh->do("DELETE FROM nag_defer WHERE defer_until <= CURRENT_DATE()");
Bugzilla->switch_to_shadow_db();

# send nags to requestees
send_nags(
    sql             => REQUESTEE_NAG_SQL,
    template        => 'requestee',
    recipient_field => 'requestee_id',
    date            => $date,
);

# send nags to watchers
send_nags(
    sql             => WATCHING_NAG_SQL,
    template        => 'watching',
    recipient_field => 'watcher_id',
    date            => $date,
);

sub send_nags {
    my (%args) = @_;
    my $rows = $dbh->selectall_arrayref($args{sql}, { Slice => {} });

    # iterate over rows, sending email when the current recipient changes
    my $requests = [];
    my $current_recipient;
    foreach my $request (@$rows) {
        # send previous user's requests
        if (!$current_recipient || $request->{$args{recipient_field}} != $current_recipient->id) {
            send_email(%args, recipient => $current_recipient, requests => $requests);
            $current_recipient = Bugzilla::User->new({ id => $request->{$args{recipient_field}}, cache => 1 });
            $requests = [];
        }

        # check group membership
        $request->{requestee} = Bugzilla::User->new({ id => $request->{requestee_id}, cache => 1 });
        my $group;
        foreach my $type (FLAG_TYPES) {
            next unless $type->{type} eq $request->{flag_type};
            $group = $type->{group};
            last;
        }
        next unless $request->{requestee}->in_group($group);

        # check bug visibility
        next unless $current_recipient->can_see_bug($request->{bug_id});

        # create objects
        $request->{bug} = Bugzilla::Bug->new({ id => $request->{bug_id}, cache => 1 });
        $request->{requester} = Bugzilla::User->new({ id => $request->{requester_id}, cache => 1 });
        $request->{flag} = Bugzilla::Flag->new({ id => $request->{flag_id}, cache => 1 });
        if ($request->{attach_id}) {
            $request->{attachment} = Bugzilla::Attachment->new({ id => $request->{attach_id}, cache => 1 });
            # check attachment visibility
            next if $request->{attachment}->isprivate && !$current_recipient->is_insider;
        }
        if (exists $request->{watcher_id}) {
            $request->{watcher} = Bugzilla::User->new({ id => $request->{watcher_id}, cache => 1 });
        }

        # add this request to the current user's list
        push(@$requests, $request);
    }
    send_email(%args, recipient => $current_recipient, requests => $requests);
}

sub send_email {
    my (%vars) = @_;
    my $vars = \%vars;
    return unless $vars->{recipient} && @{ $vars->{requests} };

    # restructure the list to group by requestee then flag type
    my $request_list = delete $vars->{requests};
    my $requests = {};
    my %seen_types;
    foreach my $request (@{ $request_list }) {
        # by requestee
        my $requestee_login = $request->{requestee}->login;
        $requests->{$requestee_login} ||= {
            requestee => $request->{requestee},
            types     => {},
            typelist  => [],
        };

        # by flag type
        my $types = $requests->{$requestee_login}->{types};
        my $flag_type = $request->{flag_type};
        $types->{$flag_type} ||= [];

        push @{ $types->{$flag_type} }, $request;
        $seen_types{$requestee_login}{$flag_type} = 1;
    }
    foreach my $requestee_login (keys %seen_types) {
        my @flag_types;
        foreach my $flag_type (map { $_->{type} } FLAG_TYPES) {
            push @flag_types, $flag_type if $seen_types{$requestee_login}{$flag_type};
        }
        $requests->{$requestee_login}->{typelist} = \@flag_types;
    }
    $vars->{requests} = $requests;

    # generate email
    my $template = Bugzilla->template_inner($vars->{recipient}->setting('lang'));
    my $template_file = $vars->{template};

    my ($header, $text);
    $template->process("email/request_nagging-$template_file-header.txt.tmpl", $vars, \$header)
        || ThrowTemplateError($template->error());
    $header .= "\n";
    $template->process("email/request_nagging-$template_file.txt.tmpl", $vars, \$text)
        || ThrowTemplateError($template->error());

    my @parts = (
        Email::MIME->create(
            attributes => { content_type => "text/plain" },
            body => $text,
        )
    );
    if ($vars->{recipient}->setting('email_format') eq 'html') {
        my $html;
        $template->process("email/request_nagging-$template_file.html.tmpl", $vars, \$html)
            || ThrowTemplateError($template->error());
        push @parts, Email::MIME->create(
            attributes => { content_type => "text/html" },
            body => $html,
        );
    }

    my $email = Email::MIME->new($header);
    $email->header_set('X-Generated-By' => hostname());
    if (scalar(@parts) == 1) {
        $email->content_type_set($parts[0]->content_type);
    } else {
        $email->content_type_set('multipart/alternative');
    }
    $email->parts_set(\@parts);

    # send
    if ($DO_NOT_NAG) {
        print $email->as_string, "\n";
    } else {
        MessageToMTA($email);
    }
}

