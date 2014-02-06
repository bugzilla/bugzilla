# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::TagNewUsers;
use strict;
use base qw(Bugzilla::Extension);
use Bugzilla::Field;
use Bugzilla::User;
use Bugzilla::Install::Util qw(indicate_progress);
use Bugzilla::WebService::Util qw(filter_wants);
use Date::Parse;
use Scalar::Util qw(blessed);

# users younger than PROFILE_AGE days will be tagged as new
use constant PROFILE_AGE => 60;

# users with fewer comments than COMMENT_COUNT will be tagged as new
use constant COMMENT_COUNT => 25;

our $VERSION = '1';

#
# install
#

sub install_update_db {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;

    if (!$dbh->bz_column_info('profiles', 'comment_count')) {
        $dbh->bz_add_column('profiles', 'comment_count',
            {TYPE => 'INT3', NOTNULL => 1, DEFAULT => 0});
        my $sth = $dbh->prepare('UPDATE profiles SET comment_count=? WHERE userid=?');
        my $ra = $dbh->selectall_arrayref('SELECT who,COUNT(*) FROM longdescs GROUP BY who');
        my $count = 1;
        my $total = scalar @$ra;
        foreach my $ra_row (@$ra) {
            indicate_progress({ current => $count++, total => $total, every => 25 });
            my ($user_id, $count) = @$ra_row;
            $sth->execute($count, $user_id);
        }
    }

    if (!$dbh->bz_column_info('profiles', 'creation_ts')) {
        $dbh->bz_add_column('profiles', 'creation_ts',
            {TYPE => 'DATETIME'});
        my $creation_date_fieldid = get_field_id('creation_ts');
        my $sth = $dbh->prepare('UPDATE profiles SET creation_ts=? WHERE userid=?');
        my $ra = $dbh->selectall_arrayref("
            SELECT p.userid, a.profiles_when
              FROM profiles p
                   LEFT JOIN profiles_activity a ON a.userid=p.userid
                        AND a.fieldid=$creation_date_fieldid
        ");
        my ($now) = Bugzilla->dbh->selectrow_array("SELECT NOW()");
        my $count = 1;
        my $total = scalar @$ra;
        foreach my $ra_row (@$ra) {
            indicate_progress({ current => $count++, total => $total, every => 25 });
            my ($user_id, $when) = @$ra_row;
            if (!$when) {
                ($when) = $dbh->selectrow_array(
                    "SELECT bug_when FROM bugs_activity WHERE who=? ORDER BY bug_when " .
                        $dbh->sql_limit(1),
                    undef, $user_id
                );
            }
            if (!$when) {
                ($when) = $dbh->selectrow_array(
                    "SELECT bug_when FROM longdescs WHERE who=? ORDER BY bug_when " .
                        $dbh->sql_limit(1),
                    undef, $user_id
                );
            }
            if (!$when) {
                ($when) = $dbh->selectrow_array(
                    "SELECT creation_ts FROM bugs WHERE reporter=? ORDER BY creation_ts " .
                        $dbh->sql_limit(1),
                    undef, $user_id
                );
            }
            if (!$when) {
                $when = $now;
            }

            $sth->execute($when, $user_id);
        }
    }

    if (!$dbh->bz_column_info('profiles', 'first_patch_bug_id')) {
        $dbh->bz_add_column('profiles', 'first_patch_bug_id', {TYPE => 'INT3'});
        my $sth_update = $dbh->prepare('UPDATE profiles SET first_patch_bug_id=? WHERE userid=?');
        my $sth_select = $dbh->prepare(
            'SELECT bug_id FROM attachments WHERE submitter_id=? AND ispatch=1 ORDER BY creation_ts ' . $dbh->sql_limit(1)
        );
        my $ra = $dbh->selectcol_arrayref('SELECT DISTINCT submitter_id FROM attachments WHERE ispatch=1');
        my $count = 1;
        my $total = scalar @$ra;
        foreach my $user_id (@$ra) {
            indicate_progress({ current => $count++, total => $total, every => 25 });
            $sth_select->execute($user_id);
            my ($bug_id) = $sth_select->fetchrow_array;
            $sth_update->execute($bug_id, $user_id);
        }
    }
}

#
# objects
#

sub object_columns {
    my ($self, $args) = @_;
    my ($class, $columns) = @$args{qw(class columns)};
    if ($class->isa('Bugzilla::User')) {
        push(@$columns, qw(comment_count creation_ts first_patch_bug_id));
    }
}

sub object_before_create {
    my ($self, $args) = @_;
    my ($class, $params) = @$args{qw(class params)};
    if ($class->isa('Bugzilla::User')) {
        my ($timestamp) = Bugzilla->dbh->selectrow_array("SELECT NOW()");
        $params->{comment_count} = 0;
        $params->{creation_ts} = $timestamp;
    } elsif ($class->isa('Bugzilla::Attachment')) {
        if ($params->{ispatch} && !Bugzilla->user->first_patch_bug_id) {
            Bugzilla->user->first_patch_bug_id($params->{bug}->id);
        }
    }
}

#
# Bugzilla::User methods
#

BEGIN {
    *Bugzilla::User::comment_count = \&_comment_count;
    *Bugzilla::User::creation_ts = \&_creation_ts;
    *Bugzilla::User::update_comment_count = \&_update_comment_count;
    *Bugzilla::User::first_patch_bug_id = \&_first_patch_bug_id;
    *Bugzilla::User::is_new = \&_is_new;
    *Bugzilla::User::creation_age = \&_creation_age;
}

sub _comment_count { return $_[0]->{comment_count} }
sub _creation_ts { return $_[0]->{creation_ts} }

sub _update_comment_count {
    my $self = shift;
    my $dbh = Bugzilla->dbh;

    # no need to update this counter for users which are no longer new
    return unless $self->is_new;

    my $id = $self->id;
    my ($count) = $dbh->selectrow_array(
        "SELECT COUNT(*) FROM longdescs WHERE who=?",
        undef, $id
    );
    return if $self->{comment_count} == $count;
    $dbh->do(
        'UPDATE profiles SET comment_count=? WHERE userid=?',
        undef, $count, $id
    );
    $self->{comment_count} = $count;
}

sub _first_patch_bug_id {
    my ($self, $bug_id) = @_;
    return $self->{first_patch_bug_id} unless defined $bug_id;

    Bugzilla->dbh->do(
        'UPDATE profiles SET first_patch_bug_id=? WHERE userid=?',
        undef, $bug_id, $self->id
    );
    $self->{first_patch_bug_id} = $bug_id;
}

sub _is_new {
    my ($self) = @_;

    if (!exists $self->{is_new}) {
        if ($self->in_group('canconfirm')) {
            $self->{is_new} = 0;
        } else {
            $self->{is_new} = ($self->comment_count <= COMMENT_COUNT)
                              || ($self->creation_age <= PROFILE_AGE);
        }
    }

    return $self->{is_new};
}

sub _creation_age {
    my ($self) = @_;

    if (!exists $self->{creation_age}) {
        my $age = sprintf("%.0f", (time() - str2time($self->creation_ts)) / 86400);
        $self->{creation_age} = $age;
    }

    return $self->{creation_age};
}

#
# hooks
#

sub bug_end_of_create {
    Bugzilla->user->update_comment_count();
}

sub bug_end_of_update {
    Bugzilla->user->update_comment_count();
}

sub mailer_before_send {
    my ($self, $args) = @_;
    my $email = $args->{email};

    my ($bug_id) = ($email->header('Subject') =~ /^[^\d]+(\d+)/);
    my $changer_login = $email->header('X-Bugzilla-Who');
    my $changed_fields = $email->header('X-Bugzilla-Changed-Fields');

    if ($bug_id
        && $changer_login
        && $changed_fields =~ /attachments.created/)
    {
        my $changer = Bugzilla::User->new({ name => $changer_login });
        if ($changer
            && $changer->first_patch_bug_id
            && $changer->first_patch_bug_id == $bug_id)
        {
            $email->header_set('X-Bugzilla-FirstPatch' => $bug_id);
        }
    }
}

sub webservice_user_get {
    my ($self, $args) = @_;
    my ($webservice, $params, $users) = @$args{qw(webservice params users)};

    return unless filter_wants($params, 'is_new');

    foreach my $user (@$users) {
        # Most of the time the hash values are XMLRPC::Data objects
        my $email = blessed $user->{'email'} ? $user->{'email'}->value : $user->{'email'};
        if ($email) {
            my $user_obj = Bugzilla::User->new({ name => $email });
            $user->{'is_new'} = $webservice->type('boolean', $user_obj->is_new ? 1 : 0);
        }
    }
}

__PACKAGE__->NAME;
