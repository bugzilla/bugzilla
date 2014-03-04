# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::UserProfile;

use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Constants;
use Bugzilla::Extension::UserProfile::TimeAgo qw(time_ago);
use Bugzilla::Extension::UserProfile::Util;
use Bugzilla::Install::Filesystem;
use Bugzilla::User;
use Bugzilla::Util qw(datetime_from);
use Scalar::Util qw(blessed);

our $VERSION = '1';

#
# user methods
#

BEGIN {
    *Bugzilla::User::last_activity_ts         = \&_user_last_activity_ts;
    *Bugzilla::User::set_last_activity_ts     = \&_user_set_last_activity_ts;
    *Bugzilla::User::last_statistics_ts       = \&_user_last_statistics_ts;
    *Bugzilla::User::clear_last_statistics_ts = \&_user_clear_last_statistics_ts;
}

sub _user_last_activity_ts         { $_[0]->{last_activity_ts}               }
sub _user_last_statistics_ts       { $_[0]->{last_statistics_ts}             }

sub _user_set_last_activity_ts     {
    my ($self, $value) = @_;
    $self->set('last_activity_ts', $_[1]);

    # we update the database directly to avoid audit_log entries
    Bugzilla->dbh->do(
        "UPDATE profiles SET last_activity_ts = ? WHERE userid = ?",
        undef,
        $value, $self->id);
    Bugzilla->memcached->clear({ table => 'profiles', id => $self->id });
}

sub _user_clear_last_statistics_ts {
    my ($self) = @_;
    $self->set('last_statistics_ts', undef);

    # we update the database directly to avoid audit_log entries
    Bugzilla->dbh->do(
        "UPDATE profiles SET last_statistics_ts = NULL WHERE userid = ?",
        undef,
        $self->id);
    Bugzilla->memcached->clear({ table => 'profiles', id => $self->id });
}

#
# hooks
#

sub bug_after_create {
    my ($self, $args) = @_;
    $self->_bug_touched($args);
}

sub bug_after_update {
    my ($self, $args) = @_;
    $self->_bug_touched($args);
}

sub _bug_touched {
    my ($self, $args) = @_;
    my $bug = $args->{bug};

    my $user = Bugzilla->user;
    my ($assigned_to, $qa_contact);

    # bug update
    if (exists $args->{changes}) {
        return unless
            scalar(keys %{ $args->{changes} })
            || exists $args->{bug}->{added_comments};

        # if the assignee or qa-contact is changed to someone other than the
        # current user, update them
        if (exists $args->{changes}->{assigned_to}
            && $args->{changes}->{assigned_to}->[1] ne $user->login)
        {
            $assigned_to = $bug->assigned_to;
        }
        if (exists $args->{changes}->{qa_contact}
            && ($args->{changes}->{qa_contact}->[1] || '') ne $user->login)
        {
            $qa_contact = $bug->qa_contact;
        }

        # if the product is changed, we need to recount everyone involved with
        # this bug
        if (exists $args->{changes}->{product}) {
            tag_for_recount_from_bug($bug->id);
        }

    }
    # new bug
    else {
        # if the assignee or qa-contact is created set to someone other than
        # the current user, update them
        if ($bug->assigned_to->id != $user->id) {
            $assigned_to = $bug->assigned_to;
        }
        if ($bug->qa_contact && $bug->qa_contact->id != $user->id) {
            $qa_contact = $bug->qa_contact;
        }
    }

    my $dbh = Bugzilla->dbh;
    $dbh->bz_start_transaction();

    # update user's last_activity_ts
    eval {
        $user->set_last_activity_ts($args->{timestamp});
        $self->_recalc_remove($user);
    };
    if ($@) {
        warn $@;
        $self->_recalc_insert($user);
    }

    # clear the last_statistics_ts for assignee/qa-contact to force a recount
    # at the next poll
    if ($assigned_to) {
        eval {
            $assigned_to->clear_last_statistics_ts();
            $self->_recalc_remove($assigned_to);
        };
        if ($@) {
            warn $@;
            $self->_recalc_insert($assigned_to);
        }
    }
    if ($qa_contact) {
        eval {
            $qa_contact->clear_last_statistics_ts();
            $self->_recalc_remove($qa_contact);
        };
        if ($@) {
            warn $@;
            $self->_recalc_insert($qa_contact);
        }
    }

    $dbh->bz_commit_transaction();
}

sub _recalc_insert {
    my ($self, $user) = @_;
    Bugzilla->dbh->do(
        "INSERT IGNORE INTO profiles_statistics_recalc SET user_id=?",
        undef, $user->id
    );
}

sub _recalc_remove {
    my ($self, $user) = @_;
    Bugzilla->dbh->do(
        "DELETE FROM profiles_statistics_recalc WHERE user_id=?",
        undef, $user->id
    );
}

sub object_end_of_create {
    my ($self, $args) = @_;
    $self->_object_touched($args);
}

sub object_end_of_update {
    my ($self, $args) = @_;
    $self->_object_touched($args);
}

sub _object_touched {
    my ($self, $args) = @_;
    my $object = $args->{object}
        or return;
    return if exists $args->{changes} && !scalar(keys %{ $args->{changes} });

    if ($object->isa('Bugzilla::Attachment')) {
        # if an attachment is created or updated, that counts as user activity
        my $user = Bugzilla->user;
        my $timestamp = Bugzilla->dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
        eval {
            $user->set_last_activity_ts($timestamp);
            $self->_recalc_remove($user);
        };
        if ($@) {
            warn $@;
            $self->_recalc_insert($user);
        }
    }
    elsif ($object->isa('Bugzilla::Product') && exists $args->{changes}->{name}) {
        # if a product is renamed by an admin, rename in the
        # profiles_statistics_products table
        Bugzilla->dbh->do(
            "UPDATE profiles_statistics_products SET product=? where product=?",
            undef,
            $args->{changes}->{name}->[1], $args->{changes}->{name}->[0],
        );
    }
}

sub reorg_move_bugs {
    my ($self, $args) = @_;
    my $bug_ids = $args->{bug_ids};
    printf "Touching user profile data for %s bugs.\n", scalar(@$bug_ids);
    my $count = 0;
    foreach my $bug_id (@$bug_ids) {
        $count += tag_for_recount_from_bug($bug_id);
    }
    print "Updated $count users.\n";
}

sub merge_users_before {
    my ($self, $args) = @_;
    my ($old_id, $new_id) = @$args{qw(old_id new_id)};
    # when users are merged, we have to delete all the statistics for both users
    # we'll recalcuate the stats after the merge
    print "deleting user profile statistics for $old_id and $new_id\n";
    my $dbh = Bugzilla->dbh;
    foreach my $table (qw( profiles_statistics profiles_statistics_status profiles_statistics_products )) {
        $dbh->do("DELETE FROM $table WHERE " . $dbh->sql_in('user_id', [ $old_id, $new_id ]));
    }
}

sub merge_users_after {
    my ($self, $args) = @_;
    my $new_id = $args->{new_id};
    print "generating user profile statistics $new_id\n";
    update_statistics_by_user($new_id);
}

sub webservice_user_get {
    my ($self, $args) = @_;
    my ($service, $users) = @$args{qw(webservice users)};

    my $dbh = Bugzilla->dbh;
    my $ids = [
        map { blessed($_->{id}) ? $_->{id}->value : $_->{id} }
        grep { exists $_->{id} }
        @$users
    ];
    return unless @$ids;
    my $timestamps = $dbh->selectall_hashref(
        "SELECT userid,last_activity_ts FROM profiles WHERE " . $dbh->sql_in('userid', $ids),
        'userid',
    );
    foreach my $user (@$users) {
        my $id = blessed($user->{id}) ? $user->{id}->value : $user->{id};
        $user->{last_activity} = $service->type('dateTime', $timestamps->{$id}->{last_activity_ts});
    }
}

sub template_before_create {
    my ($self, $args) = @_;
    $args->{config}->{FILTERS}->{timeago} = sub {
        my ($time_str) = @_;
        return time_ago(datetime_from($time_str, 'UTC'));
    };
}

sub page_before_template {
    my ($self, $args) = @_;
    my ($vars, $page) = @$args{qw(vars page_id)};
    return unless $page eq 'user_profile.html';
    my $user = Bugzilla->user;

    # determine user to display
    my ($target, $login);
    my $input = Bugzilla->input_params;
    if (my $user_id = $input->{user_id}) {
        # load from user_id
        $user_id = 0 if $user_id =~ /\D/;
        $target = Bugzilla::User->check({ id => $user_id });
    } else {
        # loading from login name requires authentication
        Bugzilla->login(LOGIN_REQUIRED);
        $login = $input->{login};
        if (!$login) {
            # show current user's profile by default
            $target = $user;
        } else {
            my $limit = Bugzilla->params->{'maxusermatches'} + 1;
            my $users = Bugzilla::User::match($login, $limit, 1);
            if (scalar(@$users) == 1) {
                # always allow singular matches without confirmation
                $target = $users->[0];
            } else {
                Bugzilla::User::match_field({ 'login' => {'type' => 'single'} });
                $target = Bugzilla::User->check($login);
            }
        }
    }
    $login ||= $target->login;

    # load statistics into $vars
    my $dbh = Bugzilla->switch_to_shadow_db;

    my $stats = $dbh->selectall_hashref(
        "SELECT name, count
           FROM profiles_statistics
          WHERE user_id = ?",
        "name",
        undef,
        $target->id,
    );
    map { $stats->{$_} = $stats->{$_}->{count} } keys %$stats;

    my $statuses = $dbh->selectall_hashref(
        "SELECT status, count
           FROM profiles_statistics_status
          WHERE user_id = ?",
        "status",
        undef,
        $target->id,
    );
    map { $statuses->{$_} = $statuses->{$_}->{count} } keys %$statuses;

    my $products = $dbh->selectall_arrayref(
        "SELECT product, count
           FROM profiles_statistics_products
          WHERE user_id = ?
          ORDER BY product = '', count DESC",
        { Slice => {} },
        $target->id,
    );

    # ensure there's always an "other" product entry
    my ($other_product) = grep { $_->{product} eq '' } @$products;
    if (!$other_product) {
        $other_product = { product => '', count => 0 };
        push @$products, $other_product;
    }

    # load product objects and validate product visibility
    foreach my $product (@$products) {
        next if $product->{product} eq '';
        my $product_obj = Bugzilla::Product->new({ name => $product->{product} });
        if (!$product_obj || !$user->can_see_product($product_obj->name)) {
            # products not accessible to current user are moved into "other"
            $other_product->{count} += $product->{count};
            $product->{count} = 0;
        } else {
            $product->{product} = $product_obj;
        }
    }

    # set other's name, and remove empty products
    $other_product->{product} = { name => 'Other' };
    $products = [ grep { $_->{count} } @$products ];

    $vars->{stats}    = $stats;
    $vars->{statuses} = $statuses;
    $vars->{products} = $products;
    $vars->{login}    = $login;
    $vars->{target}   = $target;
}

sub object_columns {
    my ($self, $args) = @_;
    my ($class, $columns) = @$args{qw(class columns)};
    if ($class->isa('Bugzilla::User')) {
        push(@$columns, qw(last_activity_ts last_statistics_ts));
    }
}

sub object_update_columns {
    my ($self, $args) = @_;
    my ($object, $columns) = @$args{qw(object columns)};
    if ($object->isa('Bugzilla::User')) {
        push(@$columns, qw(last_activity_ts last_statistics_ts));
    }
}

#
# installation
#

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    $args->{'schema'}->{'profiles_statistics'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            user_id => {
                TYPE    => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'profiles',
                    COLUMN => 'userid',
                    DELETE => 'CASCADE',
                }
            },
            name => {
                TYPE    => 'VARCHAR(30)',
                NOTNULL => 1,
            },
            count => {
                TYPE    => 'INT',
                NOTNULL => 1,
            },
        ],
        INDEXES => [
            profiles_statistics_name_idx => {
                FIELDS => [ 'user_id', 'name' ],
                TYPE => 'UNIQUE',
            },
        ],
    };
    $args->{'schema'}->{'profiles_statistics_status'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            user_id => {
                TYPE    => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'profiles',
                    COLUMN => 'userid',
                    DELETE => 'CASCADE',
                }
            },
            status => {
                TYPE    => 'VARCHAR(64)',
                NOTNULL => 1,
            },
            count => {
                TYPE    => 'INT',
                NOTNULL => 1,
            },
        ],
        INDEXES => [
            profiles_statistics_status_idx => {
                FIELDS => [ 'user_id', 'status' ],
                TYPE => 'UNIQUE',
            },
        ],
    };
    $args->{'schema'}->{'profiles_statistics_products'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            user_id => {
                TYPE    => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'profiles',
                    COLUMN => 'userid',
                    DELETE => 'CASCADE',
                }
            },
            product => {
                TYPE    => 'VARCHAR(64)',
                NOTNULL => 1,
            },
            count => {
                TYPE    => 'INT',
                NOTNULL => 1,
            },
        ],
        INDEXES => [
            profiles_statistics_products_idx => {
                FIELDS => [ 'user_id', 'product' ],
                TYPE => 'UNIQUE',
            },
        ],
    };
    $args->{'schema'}->{'profiles_statistics_recalc'} = {
        FIELDS => [
            user_id => {
                TYPE    => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'profiles',
                    COLUMN => 'userid',
                    DELETE => 'CASCADE',
                }
            },
        ],
        INDEXES => [
            profiles_statistics_recalc_idx => {
                FIELDS => [ 'user_id' ],
                TYPE => 'UNIQUE',
            },
        ],
    };
    $args->{'schema'}->{'profiles_statistics_recalc'} = {
        FIELDS => [
            user_id => {
                TYPE    => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'profiles',
                    COLUMN => 'userid',
                    DELETE => 'CASCADE',
                }
            },
        ],
        INDEXES => [
            profiles_statistics_recalc_idx => {
                FIELDS => [ 'user_id' ],
                TYPE => 'UNIQUE',
            },
        ],
    };
}

sub install_update_db {
    my $dbh = Bugzilla->dbh;
    $dbh->bz_add_column('profiles', 'last_activity_ts', { TYPE => 'DATETIME' });
    $dbh->bz_add_column('profiles', 'last_statistics_ts', { TYPE => 'DATETIME' });
}

sub install_filesystem {
    my ($self, $args) = @_;
    my $files = $args->{'files'};
    my $extensions_dir = bz_locations()->{'extensionsdir'};
    my $script_name = $extensions_dir . "/" . __PACKAGE__->NAME . "/bin/update.pl";
    $files->{$script_name} = {
        perms => Bugzilla::Install::Filesystem::WS_EXECUTE
    };
    $script_name = $extensions_dir . "/" . __PACKAGE__->NAME . "/bin/migrate.pl";
    $files->{$script_name} = {
        perms => Bugzilla::Install::Filesystem::OWNER_EXECUTE
    };
}

__PACKAGE__->NAME;
