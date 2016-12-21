#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(. lib local/lib/perl5);


use Bugzilla;
BEGIN { Bugzilla->extensions() }

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Field;
use Bugzilla::Group;
use Bugzilla::Mailer;
use Bugzilla::User;

use Sys::Hostname qw(hostname);

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $dbh = Bugzilla->dbh;

# Record any changes as made by the automation user
my $auto_user = Bugzilla::User->check({ name => 'automation@bmo.tld' });

my $expired = $dbh->selectall_arrayref(
    "SELECT DISTINCT profiles.userid AS user_id,
            groups.id AS group_id
       FROM profiles JOIN user_group_map ON profiles.userid = user_group_map.user_id
            JOIN groups ON user_group_map.group_id = groups.id
      WHERE user_group_map.grant_type = ?
            AND groups.idle_member_removal > 0
            AND (profiles.last_seen_date IS NULL
                 OR TO_DAYS(LOCALTIMESTAMP(0)) - TO_DAYS(profiles.last_seen_date) > groups.idle_member_removal)
      ORDER BY profiles.login_name",
    { Slice => {} }, GRANT_DIRECT
);

exit(0) if !@$expired;

my %remove_data = ();
foreach my $data (@$expired) {
    $remove_data{$data->{group_id}} ||= [];
    push(@{ $remove_data{$data->{group_id}} }, $data->{user_id});
}

# 1. Remove users from the group
# 2. $user->update will add audit log and profile_activity entries
# 3. Send email to group owner showing users removed
foreach my $group_id (keys %remove_data) {
    my $group = Bugzilla::Group->new({ id => $group_id, cache => 1 });

    $dbh->bz_start_transaction();

    my @users_removed = ();
    foreach my $user_id (@{ $remove_data{$group->id} }) {
        my $user = Bugzilla::User->new({ id => $user_id, cache => 1 });
        Bugzilla->set_user(Bugzilla::User->super_user);
        $user->set_groups({ remove => [ $group->name ] });
        $user->set_bless_groups({ remove => [ $group->name ] });
        Bugzilla->set_user($auto_user);
        $user->update();
        push(@users_removed, $user);
    }

    $dbh->bz_commit_transaction();

    # nobody@mozilla.org cannot recieve email
    next if $group->owner->login eq 'nobody@mozilla.org';

    _send_email($group, \@users_removed);
}

sub _send_email {
    my ($group, $users) = @_;

    my $template = Bugzilla->template_inner($group->owner->setting('lang'));
    my $vars = { group => $group, users => $users };

    my ($header, $text);
    $template->process("admin/groups/email/idle-member-removal-header.txt.tmpl", $vars, \$header)
        || ThrowTemplateError($template->error());
    $header .= "\n";
    $template->process("admin/groups/email/idle-member-removal.txt.tmpl", $vars, \$text)
        || ThrowTemplateError($template->error());

    my @parts = (
        Email::MIME->create(
            attributes => {
                content_type => 'text/plain',
                charset      => 'UTF-8',
                encoding     => 'quoted-printable',
            },
            body_str => $text,
        )
    );

    if ($group->owner->setting('email_format') eq 'html') {
        my $html;
        $template->process("admin/groups/email/idle-member-removal.html.tmpl", $vars, \$html)
            || ThrowTemplateError($template->error());
        push @parts, Email::MIME->create(
            attributes => {
                content_type => 'text/html',
                charset      => 'UTF-8',
                encoding     => 'quoted-printable',
            },
            body_str => $html,
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

    MessageToMTA($email);
}
