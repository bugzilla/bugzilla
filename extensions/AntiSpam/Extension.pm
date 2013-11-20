# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::AntiSpam;

use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Error;
use Bugzilla::Group;
use Bugzilla::Util qw(remote_ip trick_taint);
use Email::Address;
use Encode;
use Socket;
use Sys::Syslog qw(:DEFAULT setlogsock);

our $VERSION = '1';

#
# project honeypot integration
#

sub _project_honeypot_blocking {
    my ($self, $api_key, $login) = @_;
    my $ip = remote_ip();
    return unless $ip =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/;
    my $lookup = "$api_key.$4.$3.$2.$1.dnsbl.httpbl.org";
    return unless my $packed = gethostbyname($lookup);
    my $honeypot = inet_ntoa($packed);
    return unless $honeypot =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/;
    my ($status, $days, $threat, $type) = ($1, $2, $3, $4);

    return if $status != 127
              || $threat < Bugzilla->params->{honeypot_threat_threshold};

    _syslog(sprintf("[audit] blocked <%s> from creating %s, honeypot %s", $ip, $login, $honeypot));
    ThrowUserError('account_creation_restricted');
}

sub config_modify_panels {
    my ($self, $args) = @_;
    push @{ $args->{panels}->{auth}->{params} }, {
        name    => 'honeypot_api_key',
        type    => 't',
        default => '',
    };
    push @{ $args->{panels}->{auth}->{params} }, {
        name    => 'honeypot_threat_threshold',
        type    => 't',
        default => '32',
    };
}

#
# comment blocking
#

sub _comment_blocking {
    my ($self, $params) = @_;

    # as we want to use this sparingly, we only block comments on bugs which
    # the user didn't report, and skip it completely if the user is in the
    # editbugs group.
    my $user = Bugzilla->user;
    return if $user->in_group('editbugs');
    # new bug
    return unless $params->{bug_id};
    # existing bug
    my $bug = ref($params->{bug_id})
              ? $params->{bug_id}
              : Bugzilla::Bug->new($params->{bug_id});
    return if $bug->reporter->id == $user->id;

    my $blocklist = Bugzilla->dbh->selectcol_arrayref(
        'SELECT word FROM antispam_comment_blocklist'
    );
    return unless @$blocklist;

    my $regex = '\b(?:' . join('|', map { quotemeta } @$blocklist) . ')\b';
    if ($params->{thetext} =~ /$regex/i) {
        ThrowUserError('antispam_comment_blocked');
    }
}

#
# domain blocking
#

sub _domain_blocking {
    my ($self, $login) = @_;
    my $address = Email::Address->new(undef, $login);
    my $blocked = Bugzilla->dbh->selectrow_array(
        "SELECT 1 FROM antispam_domain_blocklist WHERE domain=?",
        undef,
        $address->host
    );
    if ($blocked) {
        _syslog(sprintf("[audit] blocked <%s> from creating %s, blacklisted domain", remote_ip(), $login));
        ThrowUserError('account_creation_restricted');
    }
}

#
# ip blocking
#

sub _ip_blocking {
    my ($self, $login) = @_;
    my $ip = remote_ip();
    trick_taint($ip);
    my $blocked = Bugzilla->dbh->selectrow_array(
        "SELECT 1 FROM antispam_ip_blocklist WHERE ip_address=?",
        undef,
        $ip
    );
    if ($blocked) {
        _syslog(sprintf("[audit] blocked <%s> from creating %s, blacklisted IP", $ip, $login));
        ThrowUserError('account_creation_restricted');
    }
}

#
# hooks
#

sub object_end_of_create_validators {
    my ($self, $args) = @_;
    if ($args->{class} eq 'Bugzilla::Comment') {
        $self->_comment_blocking($args->{params});
    }
}

sub user_verify_login {
    my ($self, $args) = @_;
    if (my $api_key = Bugzilla->params->{honeypot_api_key}) {
        $self->_project_honeypot_blocking($api_key, $args->{login});
    }
    $self->_ip_blocking($args->{login});
    $self->_domain_blocking($args->{login});
}

sub editable_tables {
    my ($self, $args) = @_;
    my $tables = $args->{tables};
    # allow these tables to be edited with the EditTables extension
    $tables->{antispam_domain_blocklist} = {
        id_field => 'id',
        order_by => 'domain',
        blurb    => 'List of fully qualified domain names to block at account creation time.',
        group    => 'can_configure_antispam',
    };
    $tables->{antispam_comment_blocklist} = {
        id_field => 'id',
        order_by => 'word',
        blurb    => "List of whole words that will cause comments containing \\b\$word\\b to be blocked.\n" .
                    "This only applies to comments on bugs which the user didn't report.\n" .
                    "Users in the editbugs group are exempt from comment blocking.",
        group    => 'can_configure_antispam',
    };
    $tables->{antispam_ip_blocklist} = {
        id_field => 'id',
        order_by => 'ip_address',
        blurb    => 'List of IPv4 addresses which are prevented from creating accounts.',
        group    => 'can_configure_antispam',
    };
}

#
# installation
#

sub install_before_final_checks {
    if (!Bugzilla::Group->new({ name => 'can_configure_antispam' })) {
        Bugzilla::Group->create({
            name        => 'can_configure_antispam',
            description => 'Can configure Anti-Spam measures',
            isbuggroup  => 0,
        });
    }
}

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    $args->{'schema'}->{'antispam_domain_blocklist'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            domain => {
                TYPE    => 'VARCHAR(255)',
                NOTNULL => 1,
            },
            comment => {
                TYPE    => 'VARCHAR(255)',
                NOTNULL => 1,
            },
        ],
        INDEXES => [
            antispam_domain_blocklist_idx => {
                FIELDS => [ 'domain' ],
                TYPE => 'UNIQUE',
            },
        ],
    };
    $args->{'schema'}->{'antispam_comment_blocklist'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            word => {
                TYPE    => 'VARCHAR(255)',
                NOTNULL => 1,
            },
        ],
        INDEXES => [
            antispam_comment_blocklist_idx => {
                FIELDS => [ 'word' ],
                TYPE => 'UNIQUE',
            },
        ],
    };
    $args->{'schema'}->{'antispam_ip_blocklist'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            ip_address => {
                TYPE    => 'VARCHAR(15)',
                NOTNULL => 1,
            },
            comment => {
                TYPE    => 'VARCHAR(255)',
                NOTNULL => 1,
            },
        ],
        INDEXES => [
            antispam_ip_blocklist_idx => {
                FIELDS => [ 'ip_address' ],
                TYPE => 'UNIQUE',
            },
        ],
    };
}

#
# utilities
#

sub _syslog {
    my $message = shift;
    openlog('apache', 'cons,pid', 'local4');
    syslog('notice', encode_utf8($message));
    closelog();
}

__PACKAGE__->NAME;
