#!/usr/bin/perl -w

use JSON::RPC::Client;
use Data::Dumper;
use HTTP::Cookies;

###################################
# Need to login first             #
###################################

my $username = shift;
my $password = shift;

my $cookie_jar = HTTP::Cookies->new( file => "/tmp/lwp_cookies.dat" );

my $rpc = new JSON::RPC::Client;

$rpc->ua->ssl_opts(verify_hostname => 0);

my $uri = "https://bugzilla-stage-tip.mozilla.org/jsonrpc.cgi";
#my $uri = "http://fedora/autoland/jsonrpc.cgi";

#$rpc->ua->cookie_jar($cookie_jar);

#my $result = $rpc->call($uri, { method => 'User.login', params => 
#    { login => $username, password => $password } });

#if ($result) {
#    if ($result->is_error) {                                                         
#        print "Error : ", $result->error_message;
#        exit;
#    }                                                                                                       
#    else {
#        print "Successfully logged in.\n";
#    }
#}
#else {
#    print $rpc->status_line;                                                                                                                                             
#}  

###################################
# Main call here                  #
###################################

my $attach_id = shift;
my $status    = shift;

$result = $rpc->call($uri, { method => 'TryAutoLand.updateStatus', 
                             params => { attach_id         => $attach_id, 
                                         status            => $status, 
                                         Bugzilla_login    => $username, 
                                         Bugzilla_password => $password  } });

if ($result) {
    if ($result->is_error) {                                                         
        print "Error : ", $result->error_message;
        exit;
    }                                                                                                       
}
else {
    print $rpc->status_line;                                                                                                                                             
}  

print Dumper($result->result);
