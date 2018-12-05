# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package QA::REST;

use 5.14.0;
use strict;
use warnings;

use FindBin qw($RealBin);
use lib "$RealBin/../../lib", "$RealBin/../../../local/lib/perl5";

use autodie;

use LWP::UserAgent;
use JSON;
use QA::Util;

use parent qw(LWP::UserAgent Exporter);

@QA::REST::EXPORT = qw(
  MUST_FAIL
  get_rest_client
);

use constant MUST_FAIL => 1;

sub get_rest_client {
  my $rest_client = LWP::UserAgent->new(ssl_opts => {verify_hostname => 0});
  bless($rest_client, 'QA::REST');
  my $config = $rest_client->{bz_config} = get_config();
  $rest_client->{bz_url}
    = $config->{browser_url} . '/' . $config->{bugzilla_installation} . '/rest/';
  $rest_client->{bz_default_headers}
    = {'Accept' => 'application/json', 'Content-Type' => 'application/json'};
  return $rest_client;
}

sub bz_config { return $_[0]->{bz_config}; }

sub call {
  my ($self, $method, $data, $http_verb, $expect_to_fail) = @_;
  $http_verb = lc($http_verb || 'GET');
  $data //= {};

  my %args = %{$self->{bz_default_headers}};

# We do not pass the API key in the URL, so that it's not logged by the web server.
  if ($http_verb eq 'get' && $data->{api_key}) {
    $args{'X-BUGZILLA-API-KEY'} = $data->{api_key};
  }
  elsif ($http_verb ne 'get') {
    $args{Content} = encode_json($data);
  }

  my $response = $self->$http_verb($self->{bz_url} . $method, %args);
  my $res = decode_json($response->decoded_content);
  if ($response->is_success xor $expect_to_fail) {
    return $res;
  }
  else {
    die 'error ' . $res->{code} . ': ' . $res->{message} . "\n";
  }
}

1;
