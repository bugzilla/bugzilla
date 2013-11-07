# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::ProjectHoneyPot;

use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Encode;
use Bugzilla::Error;
use Bugzilla::Util qw(remote_ip);
use Socket;
use Sys::Syslog qw(:DEFAULT setlogsock);

our $VERSION = '1';

sub user_verify_login {
    my ($self, $args) = @_;
    return unless my $api_key = Bugzilla->params->{honeypot_api_key};
    my $ip = remote_ip();
    return unless $ip =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/;
    my $lookup = "$api_key.$4.$3.$2.$1.dnsbl.httpbl.org";
    return unless my $packed = gethostbyname($lookup);
    my $honeypot = inet_ntoa($packed);
    return unless $honeypot =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/;
    my ($status, $days, $threat, $type) = ($1, $2, $3, $4);

    return if $status != 127
              || $threat < Bugzilla->params->{honeypot_threat_threshold};

    _syslog(sprintf("[audit] blocked <%s> from creating %s, honeypot %s",
        $ip, $args->{login}, $honeypot));
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

sub _syslog {
    my $message = shift;
    openlog('apache', 'cons,pid', 'local4');
    syslog('notice', encode_utf8($message));
    closelog();
}

__PACKAGE__->NAME;
