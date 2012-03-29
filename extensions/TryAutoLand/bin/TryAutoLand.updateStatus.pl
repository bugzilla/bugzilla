#!/usr/bin/perl -w
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use XMLRPC::Lite;
use Data::Dumper;
use HTTP::Cookies;

###################################
# Need to login first             #
###################################

my $username = shift;
my $password = shift;

my $cookie_jar = new HTTP::Cookies( file => "/tmp/lwp_cookies.dat" );

my $rpc = new XMLRPC::Lite;

$rpc->proxy('http://fedora/726193/xmlrpc.cgi');

$rpc->encoding('UTF-8');

$rpc->transport->cookie_jar($cookie_jar);

my $call = $rpc->call( 'User.login',
    { login => $username, password => $password } );

if ( $call->faultstring ) {
    print $call->faultstring . "\n";
    exit;
}

# Save the cookies in the cookie file
$rpc->transport->cookie_jar->extract_cookies(
    $rpc->transport->http_response );
$rpc->transport->cookie_jar->save;

print "Successfully logged in.\n";

###################################
# Main call here                  #
###################################

my $attach_id = shift;
my $action    = shift;
my $status    = shift;

$call = $rpc->call('TryAutoLand.update', 
                   { attach_id => $attach_id, action => $action, status => $status });

my $result = "";
if ( $call->faultstring ) {
    print $call->faultstring . "\n";
    exit;
}
else {
   $result = $call->result;
}

print Dumper($result);
