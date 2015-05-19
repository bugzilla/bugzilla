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
use Bugzilla::Hook;
use Bugzilla::Error;
use Bugzilla::Extension::RequestNagger::Constants;
use Bugzilla::Extension::RequestNagger::Bug;
use Bugzilla::Mailer;
use Bugzilla::User;
use Bugzilla::Util qw(format_time);
use Email::MIME;
use Sys::Hostname qw(hostname);

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
    requestee_sql => REQUESTEE_NAG_SQL,
    setter_sql    => SETTER_NAG_SQL,
    template      => 'user',
    date          => $date,
);

# send nags to watchers
send_nags(
    requestee_sql => WATCHING_REQUESTEE_NAG_SQL,
    setter_sql    => WATCHING_SETTER_NAG_SQL,
    template      => 'watching',
    date          => $date,
);

sub send_nags {
    my (%args) = @_;

    my @reports    = qw( requestee setter );
    my $securemail = Bugzilla::User->can('public_key');
    my $requests   = {};

    # get requests

    foreach my $report (@reports) {

        # collate requests
        my $rows = $dbh->selectall_arrayref($args{$report . '_sql'}, { Slice => {} });
        foreach my $request (@$rows) {
            next unless _include_request($request, $report);

            my $target = Bugzilla::User->new({ id => $request->{target_id}, cache => 1 });
            push @{
                    $requests
                    ->{$request->{recipient_id}}
                    ->{$target->login}
                    ->{$report}
                    ->{$request->{flag_type}}
                }, $request;
            push @{
                    $requests
                    ->{$request->{recipient_id}}
                    ->{$target->login}
                    ->{bug_ids}
                    ->{$report}
                }, $request->{bug_id};
        }

        # process requests here to avoid doing it in the templates
        foreach my $recipient_id (keys %$requests) {
            foreach my $target_login (keys %{ $requests->{$recipient_id} }) {
                my $rh = $requests->{$recipient_id}->{$target_login};

                # build a list of valid types in the correct order
                $rh->{types}->{$report} = [];
                foreach my $type (map { $_->{type} } FLAG_TYPES) {
                    next unless exists $rh->{$report}->{$type};
                    push @{ $rh->{types}->{$report} }, $type;
                }

                # build a summary
                $rh->{summary}->{$report} = join(', ',
                    map { scalar(@{ $rh->{$report}->{$_} }) . ' ' . $_ }
                    @{ $rh->{types}->{$report} }
                );
            }
        }
    }

    # send emails

    foreach my $recipient_id (sort keys %$requests) {
        my $recipient = Bugzilla::User->new({ id => $recipient_id, cache => 1 });
        my $has_key = $securemail && $recipient->public_key;
        my $has_private_bug = 0;

        foreach my $target_login (keys %{ $requests->{$recipient_id} }) {
            my $rh = $requests->{$recipient_id}->{$target_login};
            $rh->{target} = Bugzilla::User->new({ name => $target_login, cache => 1 });
            foreach my $report (@reports) {
                foreach my $type (keys %{ $rh->{$report} }) {
                    foreach my $request (@{ $rh->{$report}->{$type} }) {

                        _create_objects($request);

                        # we need to encrypt or censor emails which contain
                        # non-public bugs
                        if ($request->{bug}->is_private) {
                            $has_private_bug = 1;
                            $request->{bug}->{sanitise_bug} = !$securemail || !$has_key;
                        }
                        else {
                            $request->{bug}->{sanitise_bug} = 0;
                        }
                    }
                }
            }
        }
        my $encrypt = $securemail && $has_private_bug && $has_key;

        # generate email
        my $template = Bugzilla->template_inner($recipient->setting('lang'));
        my $template_file = $args{template};
        my $vars = {
            recipient => $recipient,
            requests  => $requests->{$recipient_id},
            date      => $args{date},
        };

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
        if ($recipient->setting('email_format') eq 'html') {
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
        }
        else {
            $email->content_type_set('multipart/alternative');
        }
        $email->parts_set(\@parts);
        if ($encrypt) {
            $email->header_set('X-Bugzilla-Encrypt' => '1');
        }

        # send
        if ($DO_NOT_NAG) {
            # uncomment the following line to enable other extensions to
            # process this email, including encryption
            # Bugzilla::Hook::process('mailer_before_send', { email => $email });
            print $email->as_string, "\n";
        }
        else {
            MessageToMTA($email);
        }

        # nuke objects to avoid excessive memory usage
        $requests->{$recipient_id} = undef;
        Bugzilla->clear_request_cache();
    }
}

sub _include_request {
    my ($request, $report) = @_;

    my $recipient = Bugzilla::User->new({ id => $request->{recipient_id}, cache => 1 });

    if ($report eq 'requestee') {
        # check recipient group membership
        my $group;
        foreach my $type (FLAG_TYPES) {
            next unless $type->{type} eq $request->{flag_type};
            $group = $type->{group};
            last;
        }
        return 0 unless $recipient->in_group($group);
    }

    # check bug visibility
    return 0 unless $recipient->can_see_bug($request->{bug_id});

    # check attachment visibility
    if ($request->{attach_id}) {
        my $attachment = Bugzilla::Attachment->new({ id => $request->{attach_id}, cache => 1 });
        return 0 if $attachment->isprivate && !$recipient->is_insider;
    }

    return 1;
}

sub _create_objects {
    my ($request) = @_;

    $request->{recipient} = Bugzilla::User->new({ id => $request->{recipient_id}, cache => 1 });
    $request->{setter}    = Bugzilla::User->new({ id => $request->{setter_id}, cache => 1 });

    if (defined $request->{requestee_id}) {
        $request->{requestee} = Bugzilla::User->new({ id => $request->{requestee_id}, cache => 1 });
    }
    if (exists $request->{watcher_id}) {
        $request->{watcher} = Bugzilla::User->new({ id => $request->{watcher_id}, cache => 1 });
    }

    $request->{bug} = Bugzilla::Extension::RequestNagger::Bug->new({ id => $request->{bug_id}, cache => 1 });
    $request->{flag} = Bugzilla::Flag->new({ id => $request->{flag_id}, cache => 1 });
    if (defined $request->{attach_id}) {
        $request->{attachment} = Bugzilla::Attachment->new({ id => $request->{attach_id}, cache => 1 });
    }
}
