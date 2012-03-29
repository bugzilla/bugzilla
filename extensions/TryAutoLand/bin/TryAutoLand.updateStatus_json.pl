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

my $uri = "http://fedora/726193/jsonrpc.cgi";

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
my $action    = shift;
my $status    = shift;

$result = $rpc->call($uri, { method => 'TryAutoLand.update', 
                             params => { attach_id         => $attach_id,
                                         action            => $action, 
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
