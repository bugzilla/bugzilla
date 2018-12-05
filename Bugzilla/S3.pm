package Bugzilla::S3;

# Forked from Amazon::S3, which appears to be abandoned.
#
# changes for Bugzilla:
# - fixed error handling
#   (https://rt.cpan.org/Ticket/Display.html?id=93033)
# - made LWP::UserAgent::Determined optional
#   (https://rt.cpan.org/Ticket/Display.html?id=76471)
# - replaced croaking with returning undef in Bucket->get_key and Bucket->get_acl
#   (https://rt.cpan.org/Public/Bug/Display.html?id=40281)
# - default to secure (https) connections to AWS
#

use 5.10.1;
use strict;
use warnings;

use Bugzilla::S3::Bucket;
use Bugzilla::Util qw(trim);
use Carp;
use Digest::HMAC_SHA1;
use HTTP::Date;
use LWP::UserAgent;
use MIME::Base64 qw(encode_base64);
use URI::Escape qw(uri_escape_utf8);
use XML::Simple;

use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(
  qw(aws_access_key_id aws_secret_access_key secure ua err errstr timeout retry host)
);
our $VERSION = '0.45bmo';

my $AMAZON_HEADER_PREFIX = 'x-amz-';
my $METADATA_PREFIX      = 'x-amz-meta-';
my $KEEP_ALIVE_CACHESIZE = 10;

sub new {
  my $class = shift;
  my $self  = $class->SUPER::new(@_);

  die "No aws_access_key_id"     unless $self->aws_access_key_id;
  die "No aws_secret_access_key" unless $self->aws_secret_access_key;

  $self->secure(1)                if not defined $self->secure;
  $self->timeout(30)              if not defined $self->timeout;
  $self->host('s3.amazonaws.com') if not defined $self->host;

  my $ua;
  if ($self->retry) {
    require LWP::UserAgent::Determined;
    $ua = LWP::UserAgent::Determined->new(
      keep_alive            => $KEEP_ALIVE_CACHESIZE,
      requests_redirectable => [qw(GET HEAD DELETE PUT)],
    );
    $ua->timing('1,2,4,8,16,32');
  }
  else {
    $ua = LWP::UserAgent->new(
      keep_alive            => $KEEP_ALIVE_CACHESIZE,
      requests_redirectable => [qw(GET HEAD DELETE PUT)],
    );
  }

  $ua->timeout($self->timeout);
  if (my $proxy = Bugzilla->params->{proxy_url}) {
    $ua->proxy(['https', 'http'], $proxy);
  }
  $self->ua($ua);
  return $self;
}

sub bucket {
  my ($self, $bucketname) = @_;
  return Bugzilla::S3::Bucket->new({bucket => $bucketname, account => $self});
}

sub _validate_acl_short {
  my ($self, $policy_name) = @_;

  if (
    !grep({ $policy_name eq $_ }
      qw(private public-read public-read-write authenticated-read)))
  {
    croak "$policy_name is not a supported canned access policy";
  }
}

# EU buckets must be accessed via their DNS name. This routine figures out if
# a given bucket name can be safely used as a DNS name.
sub _is_dns_bucket {
  my $bucketname = $_[0];

  if (length $bucketname > 63) {
    return 0;
  }
  if (length $bucketname < 3) {
    return;
  }
  return 0 unless $bucketname =~ m{^[a-z0-9][a-z0-9.-]+$};
  my @components = split /\./, $bucketname;
  for my $c (@components) {
    return 0 if $c =~ m{^-};
    return 0 if $c =~ m{-$};
    return 0 if $c eq '';
  }
  return 1;
}

# make the HTTP::Request object
sub _make_request {
  my ($self, $method, $path, $headers, $data, $metadata) = @_;
  croak 'must specify method' unless $method;
  croak 'must specify path'   unless defined $path;
  $headers ||= {};
  $data = '' if not defined $data;
  $metadata ||= {};
  my $http_headers = $self->_merge_meta($headers, $metadata);

  $self->_add_auth_header($http_headers, $method, $path)
    unless exists $headers->{Authorization};
  my $protocol = $self->secure ? 'https' : 'http';
  my $host     = $self->host;
  my $url      = "$protocol://$host/$path";
  if ($path =~ m{^([^/?]+)(.*)} && _is_dns_bucket($1)) {
    $url = "$protocol://$1.$host$2";
  }

  my $request = HTTP::Request->new($method, $url, $http_headers);
  $request->content($data);

  # my $req_as = $request->as_string;
  # $req_as =~ s/[^\n\r\x20-\x7f]/?/g;
  # $req_as = substr( $req_as, 0, 1024 ) . "\n\n";
  # warn $req_as;

  return $request;
}

# $self->_send_request($HTTP::Request)
# $self->_send_request(@params_to_make_request)
sub _send_request {
  my $self = shift;
  my $request;
  if (@_ == 1) {
    $request = shift;
  }
  else {
    $request = $self->_make_request(@_);
  }

  my $response = $self->_do_http($request);
  my $content  = $response->content;

  return $content unless $response->content_type eq 'application/xml';
  return unless $content;
  return $self->_xpc_of_content($content);
}

# centralize all HTTP work, for debugging
sub _do_http {
  my ($self, $request, $filename) = @_;

  # convenient time to reset any error conditions
  $self->err(undef);
  $self->errstr(undef);
  return $self->ua->request($request, $filename);
}

sub _send_request_expect_nothing {
  my $self    = shift;
  my $request = $self->_make_request(@_);

  my $response = $self->_do_http($request);
  my $content  = $response->content;

  return 1 if $response->code =~ /^2\d\d$/;

  # anything else is a failure, and we save the parsed result
  $self->_remember_errors($response->content);
  return 0;
}

# Send a HEAD request first, to find out if we'll be hit with a 307 redirect.
# Since currently LWP does not have true support for 100 Continue, it simply
# slams the PUT body into the socket without waiting for any possible redirect.
# Thus when we're reading from a filehandle, when LWP goes to reissue the request
# having followed the redirect, the filehandle's already been closed from the
# first time we used it. Thus, we need to probe first to find out what's going on,
# before we start sending any actual data.
sub _send_request_expect_nothing_probed {
  my $self = shift;
  my ($method, $path, $conf, $value) = @_;
  my $request = $self->_make_request('HEAD', $path);
  my $override_uri = undef;

  my $old_redirectable = $self->ua->requests_redirectable;
  $self->ua->requests_redirectable([]);

  my $response = $self->_do_http($request);

  if ($response->code =~ /^3/ && defined $response->header('Location')) {
    $override_uri = $response->header('Location');
  }
  $request = $self->_make_request(@_);
  $request->uri($override_uri) if defined $override_uri;

  $response = $self->_do_http($request);
  $self->ua->requests_redirectable($old_redirectable);

  my $content = $response->content;

  return 1 if $response->code =~ /^2\d\d$/;

  # anything else is a failure, and we save the parsed result
  $self->_remember_errors($response->content);
  return 0;
}

sub _check_response {
  my ($self, $response) = @_;
  return 1 if $response->code =~ /^2\d\d$/;
  $self->err("network_error");
  $self->errstr($response->status_line);
  $self->_remember_errors($response->content);
  return undef;
}

sub _croak_if_response_error {
  my ($self, $response) = @_;
  unless ($response->code =~ /^2\d\d$/) {
    $self->err("network_error");
    $self->errstr($response->status_line);
    croak "Bugzilla::S3: Amazon responded with " . $response->status_line . "\n";
  }
}

sub _xpc_of_content {
  return XMLin(
    $_[1],
    'KeepRoot'      => 1,
    'SuppressEmpty' => '',
    'ForceArray'    => ['Contents']
  );
}

# returns 1 if errors were found
sub _remember_errors {
  my ($self, $src) = @_;

  unless (ref $src || $src =~ m/^[[:space:]]*</) {    # if not xml
    (my $code = $src) =~ s/^[[:space:]]*\([0-9]*\).*$/$1/;
    $self->err($code);
    $self->errstr($src);
    return 1;
  }

  my $r = ref $src ? $src : $self->_xpc_of_content($src);

  if ($r->{Error}) {
    $self->err($r->{Error}{Code});
    $self->errstr($r->{Error}{Message});
    return 1;
  }
  return 0;
}

sub _add_auth_header {
  my ($self, $headers, $method, $path) = @_;
  my $aws_access_key_id     = $self->aws_access_key_id;
  my $aws_secret_access_key = $self->aws_secret_access_key;

  if (not $headers->header('Date')) {
    $headers->header(Date => time2str(time));
  }
  my $canonical_string = $self->_canonical_string($method, $path, $headers);
  my $encoded_canonical
    = $self->_encode($aws_secret_access_key, $canonical_string);
  $headers->header(Authorization => "AWS $aws_access_key_id:$encoded_canonical");
}

# generates an HTTP::Headers objects given one hash that represents http
# headers to set and another hash that represents an object's metadata.
sub _merge_meta {
  my ($self, $headers, $metadata) = @_;
  $headers  ||= {};
  $metadata ||= {};

  my $http_header = HTTP::Headers->new;
  while (my ($k, $v) = each %$headers) {
    $http_header->header($k => $v);
  }
  while (my ($k, $v) = each %$metadata) {
    $http_header->header("$METADATA_PREFIX$k" => $v);
  }

  return $http_header;
}

# generate a canonical string for the given parameters.  expires is optional and is
# only used by query string authentication.
sub _canonical_string {
  my ($self, $method, $path, $headers, $expires) = @_;
  my %interesting_headers = ();
  while (my ($key, $value) = each %$headers) {
    my $lk = lc $key;
    if ( $lk eq 'content-md5'
      or $lk eq 'content-type'
      or $lk eq 'date'
      or $lk =~ /^$AMAZON_HEADER_PREFIX/)
    {
      $interesting_headers{$lk} = trim($value);
    }
  }

  # these keys get empty strings if they don't exist
  $interesting_headers{'content-type'} ||= '';
  $interesting_headers{'content-md5'}  ||= '';

  # just in case someone used this.  it's not necessary in this lib.
  $interesting_headers{'date'} = '' if $interesting_headers{'x-amz-date'};

  # if you're using expires for query string auth, then it trumps date
  # (and x-amz-date)
  $interesting_headers{'date'} = $expires if $expires;

  my $buf = "$method\n";
  foreach my $key (sort keys %interesting_headers) {
    if ($key =~ /^$AMAZON_HEADER_PREFIX/) {
      $buf .= "$key:$interesting_headers{$key}\n";
    }
    else {
      $buf .= "$interesting_headers{$key}\n";
    }
  }

  # don't include anything after the first ? in the resource...
  $path =~ /^([^?]*)/;
  $buf .= "/$1";

  # ...unless there is an acl or torrent parameter
  if ($path =~ /[&?]acl($|=|&)/) {
    $buf .= '?acl';
  }
  elsif ($path =~ /[&?]torrent($|=|&)/) {
    $buf .= '?torrent';
  }
  elsif ($path =~ /[&?]location($|=|&)/) {
    $buf .= '?location';
  }

  return $buf;
}

# finds the hmac-sha1 hash of the canonical string and the aws secret access key and then
# base64 encodes the result (optionally urlencoding after that).
sub _encode {
  my ($self, $aws_secret_access_key, $str, $urlencode) = @_;
  my $hmac = Digest::HMAC_SHA1->new($aws_secret_access_key);
  $hmac->add($str);
  my $b64 = encode_base64($hmac->digest, '');
  if ($urlencode) {
    return $self->_urlencode($b64);
  }
  else {
    return $b64;
  }
}

sub _urlencode {
  my ($self, $unencoded) = @_;
  return uri_escape_utf8($unencoded, '^A-Za-z0-9_-');
}

1;

__END__

=head1 NAME

Bugzilla::S3 - A portable client library for working with and
managing Amazon S3 buckets and keys.

=head1 DESCRIPTION

Bugzilla::S3 provides a portable client interface to Amazon Simple
Storage System (S3).

This need for this module arose from some work that needed
to work with S3 and would be distributed, installed and used
on many various environments where compiled dependencies may
not be an option. L<Net::Amazon::S3> used L<XML::LibXML>
tying it to that specific and often difficult to install
option. In order to remove this potential barrier to entry,
this module is forked and then modified to use L<XML::SAX>
via L<XML::Simple>.

Bugzilla::S3 is intended to be a drop-in replacement for
L<Net:Amazon::S3> that trades some performance in return for
portability.

=head1 METHODS

=head2 new

Create a new S3 client object. Takes some arguments:

=over

=item aws_access_key_id

Use your Access Key ID as the value of the AWSAccessKeyId parameter
in requests you send to Amazon Web Services (when required). Your
Access Key ID identifies you as the party responsible for the
request.

=item aws_secret_access_key

Since your Access Key ID is not encrypted in requests to AWS, it
could be discovered and used by anyone. Services that are not free
require you to provide additional information, a request signature,
to verify that a request containing your unique Access Key ID could
only have come from you.

B<DO NOT INCLUDE THIS IN SCRIPTS OR APPLICATIONS YOU
DISTRIBUTE. YOU'LL BE SORRY.>

=item secure

Set this to C<0> if you not want to use SSL-encrypted
connections when talking to S3. Defaults to C<1>.

=item timeout

Defines the time, in seconds, your script should wait or a
response before bailing. Defaults is 30 seconds.

=item retry

Enables or disables the library to retry upon errors. This
uses exponential backoff with retries after 1, 2, 4, 8, 16,
32 seconds, as recommended by Amazon. Defaults to off, no
retries.

=item host

Defines the S3 host endpoint to use. Defaults to
's3.amazonaws.com'.

=back

=head1 ABOUT

This module contains code modified from Amazon that contains the
following notice:

  #  This software code is made available "AS IS" without warranties of any
  #  kind.  You may copy, display, modify and redistribute the software
  #  code either by itself or as incorporated into your code; provided that
  #  you do not remove any proprietary notices.  Your use of this software
  #  code is at your own risk and you waive any claim against Amazon
  #  Digital Services, Inc. or its affiliates with respect to your use of
  #  this software code. (c) 2006 Amazon Digital Services, Inc. or its
  #  affiliates.

=head1 TESTING

Testing S3 is a tricky thing. Amazon wants to charge you a bit of
money each time you use their service. And yes, testing counts as using.
Because of this, the application's test suite skips anything approaching
a real test unless you set these three environment variables:

=over

=item AMAZON_S3_EXPENSIVE_TESTS

Doesn't matter what you set it to. Just has to be set

=item AWS_ACCESS_KEY_ID

Your AWS access key

=item AWS_ACCESS_KEY_SECRET

Your AWS sekkr1t passkey. Be forewarned that setting this environment variable
on a shared system might leak that information to another user. Be careful.

=back

=head1 TO DO

=over

=item Continued to improve and refine of documentation.

=item Reduce dependencies wherever possible.

=item Implement debugging mode

=item Refactor and consolidate request code in Bugzilla::S3

=item Refactor URI creation code to make use of L<URI>.

=back

=head1 SUPPORT

Bugs should be reported via the CPAN bug tracker at

<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Amazon-S3>

For other issues, contact the author.

=head1 AUTHOR

Timothy Appnel <tima@cpan.org>

=head1 SEE ALSO

L<Bugzilla::S3::Bucket>, L<Net::Amazon::S3>

=head1 COPYRIGHT AND LICENCE

This module was initially based on L<Net::Amazon::S3> 0.41, by
Leon Brocard. Net::Amazon::S3 was based on example code from
Amazon with this notice:

#  This software code is made available "AS IS" without warranties of any
#  kind.  You may copy, display, modify and redistribute the software
#  code either by itself or as incorporated into your code; provided that
#  you do not remove any proprietary notices.  Your use of this software
#  code is at your own risk and you waive any claim against Amazon
#  Digital Services, Inc. or its affiliates with respect to your use of
#  this software code. (c) 2006 Amazon Digital Services, Inc. or its
#  affiliates.

The software is released under the Artistic License. The
terms of the Artistic License are described at
http://www.perl.com/language/misc/Artistic.html. Except
where otherwise noted, Amazon::S3 is Copyright 2008, Timothy
Appnel, tima@cpan.org. All rights reserved.
