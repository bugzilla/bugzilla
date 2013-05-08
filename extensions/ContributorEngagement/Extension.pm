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

our $VERSION = '1.0';

BEGIN {
    *Bugzilla::User::first_patch_approved_id = \&_first_patch_approved_id;
}

sub _first_patch_approved_id { return $_[0]->{'first_patch_approved_id'}; }

sub install_update_db {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;

    if (!$dbh->bz_column_info('profiles', 'first_patch_approved_id')) {
        $dbh->bz_add_column('profiles', 'first_patch_approved_id', 
                            { TYPE => 'INT3' });
        _migrate_first_approved_ids();
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

sub _migrate_first_approved_ids {
    my $dbh = Bugzilla->dbh;

    my $sth = $dbh->prepare('UPDATE profiles SET first_patch_approved_id = ? WHERE userid = ?');
    my $ra = $dbh->selectall_arrayref("SELECT attachments.submitter_id, 
                                              attachments.attach_id, 
                                              flagtypes.name 
                                         FROM attachments 
                                              INNER JOIN flags ON attachments.attach_id = flags.attach_id
                                              INNER JOIN flagtypes ON flags.type_id = flagtypes.id
                                        WHERE flags.status = '+'
                                     ORDER BY flags.modification_date");
    my $count = 1;
    my $total = scalar @$ra;
    my %user_seen;
    foreach my $ra_row (@$ra) {
        my ($user_id, $attach_id, $flag_name) = @$ra_row;
        next if $user_seen{$user_id};
        my $found_flag = 0;
        foreach my $flag_re (FLAG_REGEXES) {
            $found_flag = 1 if ($flag_name =~ $flag_re);
        }
        next if !$found_flag;
        indicate_progress({ current => $count++, total => $total, every => 25 });
        $sth->execute($attach_id, $user_id);
        $user_seen{$user_id} = 1;
    } 

    print "done\n";   
}

sub object_columns {
    my ($self, $args) = @_;
    my ($class, $columns) = @$args{qw(class columns)};
    if ($class->isa('Bugzilla::User')) {
        push(@$columns, 'first_patch_approved_id');
    }
}

sub flag_end_of_update {
    my ($self, $args) = @_;
    my ($object, $timestamp, $new_flags) = @$args{qw(object timestamp new_flags)};

    if ($object->isa('Bugzilla::Attachment') 
        && @$new_flags 
        && grep($_ eq $object->bug->product, ENABLED_PRODUCTS)
        && !$object->attacher->first_patch_approved_id) 
    {
        my $attachment = $object;

        # Glob: Borrowed this code from your push extension :)
        foreach my $change (@$new_flags) {
            $change =~ s/^[^:]+://; # get rid of setter
            $change =~ s/\([^\)]+\)$//; # get rid of requestee
            my ($name, $value) = $change =~ /^(.+)(.)$/;

            # Only interested in flags set to +
            next if $value ne '+';

            my $found_flag = 0; 
            foreach my $flag_re (FLAG_REGEXES) {
                $found_flag = 1 if ($name =~ $flag_re);
            }
            next if !$found_flag;
        
            _send_approval_mail($attachment, $timestamp);
            
            last;
        }
    }
}

sub _send_approval_mail {
    my ($attachment, $timestamp) = @_;
    
    my $vars = { 
        date      => format_time($timestamp, '%a, %d %b %Y %T %z', 'UTC'), 
        to_user   => $attachment->attacher->email, 
        from_user => EMAIL_FROM,  
    };

    my $msg;
    my $template = Bugzilla->template_inner($attachment->attacher->setting('lang'));
    $template->process("contributor/email.txt.tmpl", $vars, \$msg)
        || ThrowTemplateError($template->error());

    MessageToMTA($msg);

    # Make sure we don't do this again
    Bugzilla->dbh->do("UPDATE profiles SET first_patch_approved_id = ? WHERE userid = ?", 
                      undef, $attachment->id, $attachment->attacher->id);
}

__PACKAGE__->NAME;
