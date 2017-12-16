# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Config::Advanced;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Config::Common;

our $sortkey = 1700;

use constant get_param_list => (
    {
        name    => 'inbound_proxies',
        type    => 't',
        default => '',
        checker => \&check_inbound_proxies
    },

    {
        name    => 'proxy_url',
        type    => 't',
        default => ''
    },

    {
        name    => 'strict_transport_security',
        type    => 's',
        choices => [ 'off', 'this_domain_only', 'include_subdomains' ],
        default => 'off',
        checker => \&check_multi
    },

    {
        name    => 'disable_bug_updates',
        type    => 'b',
        default => 0
    },

    {
        name    => 'sentry_uri',
        type    => 't',
        default => '',
    },

    {
        name    => 'metrics_enabled',
        type    => 'b',
        default => 0
    },
    {
        name    => 'metrics_user_ids',
        type    => 't',
        default => '3881,5038,5898,13647,20209,251051,373476,409787'
    },
    {
        name    => 'metrics_elasticsearch_server',
        type    => 't',
        default => '127.0.0.1:9200'
    },
    {
        name    => 'metrics_elasticsearch_index',
        type    => 't',
        default => 'bmo-metrics'
    },
    {
        name    => 'metrics_elasticsearch_type',
        type    => 't',
        default => 'timings'
    },
    {
        name    => 'metrics_elasticsearch_ttl',
        type    => 't',
        default => '1210000000'                   # 14 days
    },
);

sub check_inbound_proxies {
    my $inbound_proxies = shift;

    return "" if $inbound_proxies eq "*";
    my @proxies = split( /[\s,]+/, $inbound_proxies );
    foreach my $proxy (@proxies) {
        validate_ip($proxy) || return "$proxy is not a valid IPv4 or IPv6 address";
    }
    return "";
}

1;
