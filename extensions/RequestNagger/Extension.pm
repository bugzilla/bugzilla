# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::RequestNagger;

use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Extension::RequestNagger::TimeAgo qw(time_ago);
use Bugzilla::Flag;
use Bugzilla::Install::Filesystem;
use Bugzilla::User::Setting;
use Bugzilla::Util qw(datetime_from detaint_natural);
use DateTime;

our $VERSION = '1';

BEGIN {
    *Bugzilla::Flag::age = \&_flag_age;
    *Bugzilla::Flag::deferred = \&_flag_deferred;
    *Bugzilla::Product::nag_interval = \&_product_nag_interval;
}

sub _flag_age {
    return time_ago(datetime_from($_[0]->modification_date));
}

sub _flag_deferred {
    my ($self) = @_;
    if (!exists $self->{deferred}) {
        my $dbh = Bugzilla->dbh;
        my ($defer_until) = $dbh->selectrow_array(
            "SELECT defer_until FROM nag_defer WHERE flag_id=?",
            undef,
            $self->id
        );
        $self->{deferred} = $defer_until ? datetime_from($defer_until) : undef;
    }
    return $self->{deferred};
}

sub _product_nag_interval { $_[0]->{nag_interval} }

sub object_columns {
    my ($self, $args) = @_;
    my ($class, $columns) = @$args{qw(class columns)};
    if ($class->isa('Bugzilla::Product')) {
        push @$columns, 'nag_interval';
    }
}

sub object_update_columns {
    my ($self, $args) = @_;
    my ($object, $columns) = @$args{qw(object columns)};
    if ($object->isa('Bugzilla::Product')) {
        push @$columns, 'nag_interval';
    }
}

sub object_before_create {
    my ($self, $args) = @_;
    my ($class, $params) = @$args{qw(class params)};
    return unless $class->isa('Bugzilla::Product');
    my $interval = _check_nag_interval(Bugzilla->cgi->param('nag_interval'));
    $params->{nag_interval} = $interval;
}

sub object_end_of_set_all {
    my ($self, $args) = @_;
    my ($object, $params) = @$args{qw(object params)};
    return unless $object->isa('Bugzilla::Product');
    my $interval = _check_nag_interval(Bugzilla->cgi->param('nag_interval'));
    $object->set('nag_interval', $interval);
}

sub _check_nag_interval {
    my ($value) = @_;
    detaint_natural($value)
        || ThrowUserError('invalid_parameter', { name => 'request reminding interval', err => 'must be numeric' });
    return $value < 0 ? 0 : $value * 24;
}

sub page_before_template {
    my ($self, $args) = @_;
    my ($vars, $page) = @$args{qw(vars page_id)};
    return unless $page eq 'request_defer.html';

    my $user = Bugzilla->login(LOGIN_REQUIRED);
    my $input = Bugzilla->input_params;

    # load flag
    my $flag_id = scalar($input->{flag})
        || ThrowUserError('request_nagging_flag_invalid');
    detaint_natural($flag_id)
        || ThrowUserError('request_nagging_flag_invalid');
    my $flag = Bugzilla::Flag->new({ id => $flag_id, cache => 1 })
        || ThrowUserError('request_nagging_flag_invalid');

    # you can only defer flags directed at you
    $user->can_see_bug($flag->bug->id)
        || ThrowUserError("bug_access_denied", { bug_id => $flag->bug->id });
    $flag->status eq '?'
        || ThrowUserError('request_nagging_flag_set');
    $flag->requestee
        || ThrowUserError('request_nagging_flag_wind');
    $flag->requestee->id == $user->id
        || ThrowUserError('request_nagging_flag_not_owned');

    my $date = DateTime->now()->truncate(to => 'day');
    my $defer_until;
    if ($input->{'defer-until'}
        && $input->{'defer-until'} =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/)
    {
        $defer_until = DateTime->new(year => $1, month => $2, day => $3);
        if ($defer_until > $date->clone->add(days => 7)) {
            $defer_until = undef;
        }
    }

    if ($input->{save} && $defer_until) {
        $self->_defer_until($flag_id, $defer_until);
        $vars->{saved} = "1";
        $vars->{defer_until} = $defer_until;
    }
    else {
        my @dates;
        foreach my $i (1..7) {
            $date->add(days => 1);
            unshift @dates, { days => $i, date => $date->clone };
        }
        $vars->{defer_until} = \@dates;
    }

    $vars->{flag} = $flag;
}

sub _defer_until {
    my ($self, $flag_id, $defer_until) = @_;
    my $dbh = Bugzilla->dbh;

    $dbh->bz_start_transaction();

    my ($defer_id) = $dbh->selectrow_array("SELECT id FROM nag_defer WHERE flag_id=?", undef, $flag_id);
    if ($defer_id) {
        $dbh->do("UPDATE nag_defer SET defer_until=? WHERE id=?", undef, $defer_until->ymd, $flag_id);
    } else {
        $dbh->do("INSERT INTO nag_defer(flag_id, defer_until) VALUES (?, ?)", undef, $flag_id, $defer_until->ymd);
    }

    $dbh->bz_commit_transaction();
}

#
# hooks
#

sub object_end_of_update {
    my ($self, $args) = @_;
    if ($args->{object}->isa("Bugzilla::Flag") && exists $args->{changes}) {
        # any change to the flag (setting, clearing, or retargetting) will clear the deferals
        my $flag = $args->{object};
        Bugzilla->dbh->do("DELETE FROM nag_defer WHERE flag_id=?", undef, $flag->id);
    }
}

sub user_preferences {
    my ($self, $args) = @_;
    my $tab     = $args->{'current_tab'};
    return unless $tab eq 'request_nagging';

    my $save = $args->{'save_changes'};
    my $vars = $args->{'vars'};
    my $user = Bugzilla->user;
    my $dbh  = Bugzilla->dbh;

    my %watching =
        map { $_ => 1 }
        @{ $dbh->selectcol_arrayref(
            "SELECT profiles.login_name
                FROM nag_watch
                    INNER JOIN profiles ON nag_watch.nagged_id = profiles.userid
                WHERE nag_watch.watcher_id = ?
                ORDER BY profiles.login_name",
            undef,
            $user->id
        ) };

    if ($save) {
        my $input = Bugzilla->input_params;
        Bugzilla::User::match_field({ 'add_watching' => {'type' => 'multi'} });

        $dbh->bz_start_transaction();

        # user preference
        if (my $value = $input->{request_nagging}) {
            my $settings = $user->settings;
            my $setting = new Bugzilla::User::Setting('request_nagging');
            if ($value eq 'default') {
                $settings->{request_nagging}->reset_to_default;
            }
            else {
                $setting->validate_value($value);
                $settings->{request_nagging}->set($value);
            }
        }

        # watching
        if ($input->{remove_watched_users}) {
            my $del_watching = ref($input->{del_watching}) ? $input->{del_watching} : [ $input->{del_watching} ];
            foreach my $login (@$del_watching) {
                my $u = Bugzilla::User->new({ name => $login, cache => 1 })
                    || next;
                next unless exists $watching{$u->login};
                $dbh->do(
                    "DELETE FROM nag_watch WHERE watcher_id=? AND nagged_id=?",
                    undef,
                    $user->id, $u->id
                );
                delete $watching{$u->login};
            }
        }
        if ($input->{add_watching}) {
            my $add_watching = ref($input->{add_watching}) ? $input->{add_watching} : [ $input->{add_watching} ];
            foreach my $login (@$add_watching) {
                my $u = Bugzilla::User->new({ name => $login, cache => 1 })
                    || next;
                next if exists $watching{$u->login};
                $dbh->do(
                    "INSERT INTO nag_watch(watcher_id, nagged_id) VALUES(?, ?)",
                    undef,
                    $user->id, $u->id
                );
                $watching{$u->login} = 1;
            }
        }

        $dbh->bz_commit_transaction();
    }

    $vars->{watching} = [ sort keys %watching ];

    my $handled = $args->{'handled'};
    $$handled = 1;
}

#
# installation
#

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    $args->{'schema'}->{'nag_watch'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            nagged_id => {
                TYPE    => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'profiles',
                    COLUMN => 'userid',
                    DELETE => 'CASCADE',
                }
            },
            watcher_id => {
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
            nag_watch_idx => {
                FIELDS => [ 'nagged_id', 'watcher_id' ],
                TYPE => 'UNIQUE',
            },
        ],
    };
    $args->{'schema'}->{'nag_defer'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            flag_id => {
                TYPE    => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'flags',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                }
            },
            defer_until => {
                TYPE    => 'DATETIME',
                NOTNULL => 1,
            },
        ],
        INDEXES => [
            nag_defer_idx => {
                FIELDS => [ 'flag_id' ],
                TYPE => 'UNIQUE',
            },
        ],
    };
}

sub install_update_db {
    my $dbh = Bugzilla->dbh;
    $dbh->bz_add_column('products', 'nag_interval', { TYPE => 'INT2',  NOTNULL => 1, DEFAULT => 7 * 24  });
}

sub install_filesystem {
    my ($self, $args) = @_;
    my $files = $args->{'files'};
    my $extensions_dir = bz_locations()->{'extensionsdir'};
    my $script_name = $extensions_dir . "/" . __PACKAGE__->NAME . "/bin/send-request-nags.pl";
    $files->{$script_name} = {
        perms => Bugzilla::Install::Filesystem::WS_EXECUTE
    };
}

sub install_before_final_checks {
    my ($self, $args) = @_;
    add_setting('request_nagging', ['on', 'off'], 'on');
}

__PACKAGE__->NAME;
