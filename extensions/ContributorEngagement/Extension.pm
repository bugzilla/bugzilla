# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::ContributorEngagement;

use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::User;
use Bugzilla::Util qw(format_time);
use Bugzilla::Mailer;
use Bugzilla::Install::Util qw(indicate_progress);

use Bugzilla::Extension::ContributorEngagement::Constants;

our $VERSION = '2.0';

BEGIN {
    *Bugzilla::User::first_patch_reviewed_id = \&_first_patch_reviewed_id;
}

sub _first_patch_reviewed_id { return $_[0]->{'first_patch_reviewed_id'}; }

sub install_update_db {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;

    if ($dbh->bz_column_info('profiles', 'first_patch_approved_id')) {
        $dbh->bz_drop_column('profiles', 'first_patch_approved_id');
    }
    if (!$dbh->bz_column_info('profiles', 'first_patch_reviewed_id')) {
        $dbh->bz_add_column('profiles', 'first_patch_reviewed_id', { TYPE => 'INT3' });
        _populate_first_reviewed_ids();
     }
}

sub _populate_first_reviewed_ids {
    my $dbh = Bugzilla->dbh;

    my $sth = $dbh->prepare('UPDATE profiles SET first_patch_reviewed_id = ? WHERE userid = ?');
    my $ra = $dbh->selectall_arrayref("SELECT attachments.submitter_id,
                                              attachments.attach_id
                                         FROM attachments
                                              INNER JOIN flags ON attachments.attach_id = flags.attach_id
                                              INNER JOIN flagtypes ON flags.type_id = flagtypes.id
                                        WHERE flagtypes.name LIKE 'review%' AND flags.status = '+'
                                     ORDER BY flags.modification_date");
    my $count = 1;
    my $total = scalar @$ra;
    my %user_seen;
    foreach my $ra_row (@$ra) {
        my ($user_id, $attach_id) = @$ra_row;
        indicate_progress({ current => $count++, total => $total, every => 25 });
        next if $user_seen{$user_id};
        $sth->execute($attach_id, $user_id);
        $user_seen{$user_id} = 1;
    }

    print "done\n";
}

sub object_columns {
    my ($self, $args) = @_;
    my ($class, $columns) = @$args{qw(class columns)};
    if ($class->isa('Bugzilla::User')) {
        push(@$columns, 'first_patch_reviewed_id');
    }
}

sub flag_end_of_update {
    my ($self, $args) = @_;
    my ($object, $timestamp, $new_flags) = @$args{qw(object timestamp new_flags)};

    if ($object->isa('Bugzilla::Attachment')
        && @$new_flags
        && !$object->attacher->first_patch_reviewed_id
        && grep($_ eq $object->bug->product, ENABLED_PRODUCTS))
    {
        my $attachment = $object;

        foreach my $orig_change (@$new_flags) {
            my $change = $orig_change;
            $change =~ s/^[^:]+://; # get rid of setter
            $change =~ s/\([^\)]+\)$//; # get rid of requestee
            my ($name, $value) = $change =~ /^(.+)(.)$/;

            # Only interested in review flags set to +
            next unless $name =~ /^review/ && $value eq '+';

            _send_mail($attachment, $timestamp);

            Bugzilla->dbh->do("UPDATE profiles SET first_patch_reviewed_id = ? WHERE userid = ?",
                              undef, $attachment->id, $attachment->attacher->id);
            Bugzilla->memcached->clear({ table => 'profiles', id => $attachment->attacher->id });
            last;
        }
    }
}

sub _send_mail {
    my ($attachment, $timestamp) = @_;

    my $vars = {
        date       => format_time($timestamp, '%a, %d %b %Y %T %z', 'UTC'),
        attachment => $attachment,
        from_user  => EMAIL_FROM,
    };

    my $msg;
    my $template = Bugzilla->template_inner($attachment->attacher->setting('lang'));
    $template->process("contributor/email.txt.tmpl", $vars, \$msg)
        || ThrowTemplateError($template->error());

    MessageToMTA($msg);
}

__PACKAGE__->NAME;
