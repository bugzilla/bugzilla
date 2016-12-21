# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

##################################################
# Test for xmlrpc call functions in Bugzilla.pm  #
##################################################

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);
use Test::More tests => 11 * 3;
use QA::Util;
my ($config, @clients) = get_rpc_clients();

foreach my $rpc (@clients) {
    my $vers_call = $rpc->bz_call_success('Bugzilla.version');
    my $version = $vers_call->result->{version};
    ok($version, "Bugzilla.version returns $version");

    my $tz_call = $rpc->bz_call_success('Bugzilla.timezone');
    my $tz = $tz_call->result->{timezone};
    ok($tz, "Bugzilla.timezone retuns $tz");

    my $ext_call = $rpc->bz_call_success('Bugzilla.extensions');
    my $extensions = $ext_call->result->{extensions};
    isa_ok($extensions, 'HASH', 'extensions');

    # There is always at least the QA extension enabled.
    my $cmp = $config->{test_extensions} ? '>' : '==';
    my @ext_names = keys %$extensions;
    my $desc = scalar(@ext_names) . ' extension(s) returned: ' . join(', ', @ext_names);
    cmp_ok(scalar(@ext_names), $cmp, 1, $desc);
    ok(grep($_ eq 'QA', @ext_names), 'The QA extension is enabled');

    my $time_call = $rpc->bz_call_success('Bugzilla.time');
    my $time_result = $time_call->result;
    foreach my $type (qw(db_time web_time)) {
        cmp_ok($time_result->{$type}, '=~', $rpc->DATETIME_REGEX,
               "Bugzilla.time returns a datetime for $type");
    }
}
