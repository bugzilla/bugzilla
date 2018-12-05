package Bugzilla::DuoAPI;
use strict;
use warnings;

our $VERSION = '1.0';

=head1 NAME

Duo::API - Reference client to call Duo Security's API methods.

=head1 SYNOPSIS

 use Duo::API;
 my $client = Duo::API->new('INTEGRATION KEY', 'SECRET KEY', 'HOSTNAME');
 my $res = $client->json_api_call('GET', '/auth/v2/check', {});

=head1 SEE ALSO

Duo for Developers: L<https://www.duosecurity.com/api>

=head1 COPYRIGHT

Copyright (c) 2013 Duo Security

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 DESCRIPTION

Duo::API objects have the following methods:

=over 4

=item new($integration_key, $integration_secret_key, $api_hostname)

Returns a handle to sign and send requests. These parameters are
obtained when creating an API integration.

=item json_api_call($method, $path, \%params)

Make a request to an API endpoint with the given HTTPS method and
parameters. Returns the parsed result if successful or dies with the
error message from the Duo Security service.

=item api_call($method, $path, \%params)

Make a request without parsing the response.

=item canonicalize_params(\%params)

Serialize a parameter hash reference to a string to sign or send.

=item sign($method, $path, $canon_params, $date)

Return the Authorization header for a request. C<$canon_params> is the
string returned by L<canonicalize_params>.

=back

=cut

use CGI qw();
use Carp qw(croak);
use Digest::HMAC_SHA1 qw(hmac_sha1_hex);
use JSON qw(decode_json);
use LWP::UserAgent;
use MIME::Base64 qw(encode_base64);
use POSIX qw(strftime);

sub new {
  my ($proto, $ikey, $skey, $host) = @_;
  my $class = ref($proto) || $proto;
  my $self = {'ikey' => $ikey, 'skey' => $skey, 'host' => $host,};
  bless($self, $class);
  return $self;
}

sub canonicalize_params {
  my ($self, $params) = @_;

  my @ret;
  while (my ($k, $v) = each(%{$params})) {
    push(@ret, join('=', CGI::escape($k), CGI::escape($v)));
  }
  return join('&', sort(@ret));
}

sub sign {
  my ($self, $method, $path, $canon_params, $date) = @_;
  my $canon
    = join("\n", $date, uc($method), lc($self->{'host'}), $path, $canon_params);
  my $sig = hmac_sha1_hex($canon, $self->{'skey'});
  my $auth = join(':', $self->{'ikey'}, $sig);
  $auth = 'Basic ' . encode_base64($auth, '');
  return $auth;
}

sub api_call {
  my ($self, $method, $path, $params) = @_;
  $params ||= {};

  my $canon_params = $self->canonicalize_params($params);
  my $date         = strftime('%a, %d %b %Y %H:%M:%S -0000', gmtime(time()));
  my $auth         = $self->sign($method, $path, $canon_params, $date);

  my $ua  = LWP::UserAgent->new();
  my $req = HTTP::Request->new();
  $req->method($method);
  $req->protocol('HTTP/1.1');
  $req->header('If-SSL-Cert-Subject' => qr{CN=[^=]+\.duosecurity.com$});
  $req->header('Authorization'       => $auth);
  $req->header('Date'                => $date);
  $req->header('Host'                => $self->{'host'});

  if (grep(/^$method$/, qw(POST PUT))) {
    $req->header('Content-type' => 'application/x-www-form-urlencoded');
    $req->content($canon_params);
  }
  else {
    $path .= '?' . $canon_params;
  }

  $req->uri('https://' . $self->{'host'} . $path);
  if ($ENV{'DEBUG'}) {
    print STDERR $req->as_string();
  }
  my $res = $ua->request($req);
  return $res;
}

sub json_api_call {
  my $self = shift;
  my $res  = $self->api_call(@_);
  my $json = $res->content();
  if ($json !~ /^{/) {
    croak($json);
  }
  my $ret = decode_json($json);
  if (($ret->{'stat'} || '') ne 'OK') {
    my $msg = join('', 'Error ', $ret->{'code'}, ': ', $ret->{'message'});
    if (defined($ret->{'message_detail'})) {
      $msg .= ' (' . $ret->{'message_detail'} . ')';
    }
    croak($msg);
  }
  return $ret->{'response'};
}

1;
