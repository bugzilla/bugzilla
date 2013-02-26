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
use Date::Parse;
use Scalar::Util qw(blessed);

# users younger than PROFILE_AGE days will be tagged as new
use constant PROFILE_AGE => 60;

# users with fewer comments than COMMENT_COUNT will be tagged as new
use constant COMMENT_COUNT => 25;

# users to always treat as not-new
# note: users in this list won't have their comment_count field updated
use constant NEVER_NEW => (
    'tbplbot@gmail.com',    # the TinderBoxPushLog robot is very frequent commenter
);

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

BEGIN {
    *Bugzilla::User::update_comment_count = \&_update_comment_count;
    *Bugzilla::User::first_patch_bug_id = \&_first_patch_bug_id;
}

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

sub bug_end_of_create {
    Bugzilla->user->update_comment_count();
}

sub bug_end_of_update {
    Bugzilla->user->update_comment_count();
}

sub _update_comment_count {
    my $self = shift;
    my $dbh = Bugzilla->dbh;

    my $login = $self->login;
    return if grep { $_ eq $login } NEVER_NEW;

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

#
#
#

sub template_before_process {
    my ($self, $args) = @_;
    my ($vars, $file) = @$args{qw(vars file)};
    if ($file eq 'bug/comments.html.tmpl') {

        # only users in canconfirm will see the new-to-bugzilla tag
        return unless Bugzilla->user->in_group('canconfirm');

        # calculate if each user that has commented on the bug is new
        foreach my $comment (@{$vars->{bug}{comments}}) {
            my $user = $comment->author;
            $user->{is_new} = $self->_user_is_new($user);
        }
    }
}

sub _user_is_new {
    my ($self, $user) = (shift, shift);

    my $login = $user->login;
    return 0 if grep { $_ eq $login} NEVER_NEW;

    # if the user can confirm bugs, they are no longer new
    return 0 if $user->in_group('canconfirm');

    # store the age in days, for the 'new to bugzilla' tooltip
    my $age = sprintf("%.0f", (time() - str2time($user->{creation_ts})) / 86400);
    $user->{creation_age} = $age;

    return
        ($user->{comment_count} <= COMMENT_COUNT)
        || ($user->{creation_age} <= PROFILE_AGE);
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

    foreach my $user (@$users) {
        # Most of the time the hash values are XMLRPC::Data objects
        my $email = blessed $user->{'email'} ? $user->{'email'}->value : $user->{'email'};
        if ($email) {
            my $user_obj = Bugzilla::User->new({ name => $email });
            $user->{'is_new'}
                = $webservice->type('boolean', $self->_user_is_new($user_obj) ? 1 : 0);
        }
    }
}

__PACKAGE__->NAME;
