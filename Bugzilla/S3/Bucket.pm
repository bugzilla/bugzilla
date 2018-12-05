package Bugzilla::S3::Bucket;

# Forked from Amazon::S3, which appears to be abandoned.

use 5.10.1;
use strict;
use warnings;

use Carp;
use File::stat;
use IO::File;

use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(qw(bucket creation_date account));

sub new {
  my $class = shift;
  my $self  = $class->SUPER::new(@_);
  croak "no bucket"  unless $self->bucket;
  croak "no account" unless $self->account;
  return $self;
}

sub _uri {
  my ($self, $key) = @_;
  return ($key)
    ? $self->bucket . "/" . $self->account->_urlencode($key)
    : $self->bucket . "/";
}

# returns bool
sub add_key {
  my ($self, $key, $value, $conf) = @_;
  croak 'must specify key' unless $key && length $key;

  if ($conf->{acl_short}) {
    $self->account->_validate_acl_short($conf->{acl_short});
    $conf->{'x-amz-acl'} = $conf->{acl_short};
    delete $conf->{acl_short};
  }

  if (ref($value) eq 'SCALAR') {
    $conf->{'Content-Length'} ||= -s $$value;
    $value = _content_sub($$value);
  }
  else {
    $conf->{'Content-Length'} ||= length $value;
  }

  # If we're pushing to a bucket that's under DNS flux, we might get a 307
  # Since LWP doesn't support actually waiting for a 100 Continue response,
  # we'll just send a HEAD first to see what's going on

  if (ref($value)) {
    return $self->account->_send_request_expect_nothing_probed('PUT',
      $self->_uri($key), $conf, $value);
  }
  else {
    return $self->account->_send_request_expect_nothing('PUT', $self->_uri($key),
      $conf, $value);
  }
}

sub add_key_filename {
  my ($self, $key, $value, $conf) = @_;
  return $self->add_key($key, \$value, $conf);
}

sub head_key {
  my ($self, $key) = @_;
  return $self->get_key($key, "HEAD");
}

sub get_key {
  my ($self, $key, $method, $filename) = @_;
  $method ||= "GET";
  $filename = $$filename if ref $filename;
  my $acct = $self->account;

  my $request = $acct->_make_request($method, $self->_uri($key), {});
  my $response = $acct->_do_http($request, $filename);

  if ($response->code == 404) {
    $acct->err(404);
    $acct->errstr('The requested key was not found');
    return undef;
  }

  return undef unless $acct->_check_response($response);

  my $etag = $response->header('ETag');
  if ($etag) {
    $etag =~ s/^"//;
    $etag =~ s/"$//;
  }

  my $return = {
    content_length => $response->content_length || 0,
    content_type   => $response->content_type,
    etag           => $etag,
    value          => $response->content,
  };

  foreach my $header ($response->headers->header_field_names) {
    next unless $header =~ /x-amz-meta-/i;
    $return->{lc $header} = $response->header($header);
  }

  return $return;

}

sub get_key_filename {
  my ($self, $key, $method, $filename) = @_;
  $filename = $key unless defined $filename;
  return $self->get_key($key, $method, \$filename);
}

# returns bool
sub delete_key {
  my ($self, $key) = @_;
  croak 'must specify key' unless $key && length $key;
  return $self->account->_send_request_expect_nothing('DELETE',
    $self->_uri($key), {});
}

sub get_acl {
  my ($self, $key) = @_;
  my $acct = $self->account;

  my $request = $acct->_make_request('GET', $self->_uri($key) . '?acl', {});
  my $response = $acct->_do_http($request);

  if ($response->code == 404) {
    return undef;
  }

  return undef unless $acct->_check_response($response);

  return $response->content;
}

sub set_acl {
  my ($self, $conf) = @_;
  $conf ||= {};

  unless ($conf->{acl_xml} || $conf->{acl_short}) {
    croak "need either acl_xml or acl_short";
  }

  if ($conf->{acl_xml} && $conf->{acl_short}) {
    croak "cannot provide both acl_xml and acl_short";
  }

  my $path = $self->_uri($conf->{key}) . '?acl';

  my $hash_ref = ($conf->{acl_short}) ? {'x-amz-acl' => $conf->{acl_short}} : {};

  my $xml = $conf->{acl_xml} || '';

  return $self->account->_send_request_expect_nothing('PUT', $path, $hash_ref,
    $xml);

}

sub get_location_constraint {
  my ($self) = @_;

  my $xpc = $self->account->_send_request('GET', $self->bucket . '/?location');
  return undef unless $xpc && !$self->account->_remember_errors($xpc);

  my $lc = $xpc->{content};
  if (defined $lc && $lc eq '') {
    $lc = undef;
  }
  return $lc;
}

# proxy up the err requests

sub err { $_[0]->account->err }

sub errstr { $_[0]->account->errstr }

sub _content_sub {
  my $filename  = shift;
  my $stat      = stat($filename);
  my $remaining = $stat->size;
  my $blksize   = $stat->blksize || 4096;

  croak "$filename not a readable file with fixed size"
    unless -r $filename and $remaining;

  my $fh = IO::File->new($filename, 'r') or croak "Could not open $filename: $!";
  $fh->binmode;

  return sub {
    my $buffer;

    # upon retries the file is closed and we must reopen it
    unless ($fh->opened) {
      $fh = IO::File->new($filename, 'r') or croak "Could not open $filename: $!";
      $fh->binmode;
      $remaining = $stat->size;
    }

    unless (my $read = $fh->read($buffer, $blksize)) {
      croak "Error while reading upload content $filename ($remaining remaining) $!"
        if $! and $remaining;
      $fh->close    # otherwise, we found EOF
        or croak "close of upload content $filename failed: $!";
      $buffer ||= '';    # LWP expects an empty string on finish, read returns 0
    }
    $remaining -= length($buffer);
    return $buffer;
  };
}

1;

__END__

=head1 NAME

Bugzilla::S3::Bucket - A container class for a S3 bucket and its contents.

=head1 METHODS

=head2 new

Instaniates a new bucket object.

Requires a hash containing two arguments:

=over

=item bucket

The name (identifier) of the bucket.

=item account

The L<S3::Amazon> object (representing the S3 account) this
bucket is associated with.

=back

NOTE: This method does not check if a bucket actually
exists. It simply instaniates the bucket.

Typically a developer will not call this method directly,
but work through the interface in L<S3::Amazon> that will
handle their creation.

=head2 add_key

Takes three positional parameters:

=over

=item key

A string identifier for the resource in this bucket

=item value

A SCALAR string representing the contents of the resource.

=item configuration

A HASHREF of configuration data for this key. The configuration
is generally the HTTP headers you want to pass the S3
service. The client library will add all necessary headers.
Adding them to the configuration hash will override what the
library would send and add headers that are not typically
required for S3 interactions.

In addition to additional and overriden HTTP headers, this
HASHREF can have a C<acl_short> key to set the permissions
(access) of the resource without a seperate call via
C<add_acl> or in the form of an XML document.  See the
documentation in C<add_acl> for the values and usage.

=back

Returns a boolean indicating its success. Check C<err> and
C<errstr> for error message if this operation fails.

=head2 add_key_filename

The method works like C<add_key> except the value is assumed
to be a filename on the local file system. The file will
be streamed rather then loaded into memory in one big chunk.

=head2 head_key $key_name

Returns a configuration HASH of the given key. If a key does
not exist in the bucket C<undef> will be returned.

=head2 get_key $key_name, [$method]

Takes a key and an optional HTTP method and fetches it from
S3. The default HTTP method is GET.

The method returns C<undef> if the key does not exist in the
bucket. If a server error occurs C<undef> is returned and
C<err> and C<errstr> are set.

On success, the method returns a HASHREF containing:

=over

=item content_type

=item etag

=item value

=item @meta

=back

=head2 get_key_filename $key_name, $method, $filename

This method works like C<get_key>, but takes an added
filename that the S3 resource will be written to.

=head2 delete_key $key_name

Permanently removes C<$key_name> from the bucket. Returns a
boolean value indicating the operations success.

=head2 get_acl

Retrieves the Access Control List (ACL) for the bucket or
resource as an XML document.

=over

=item key

The key of the stored resource to fetch. This parameter is
optional. By default the method returns the ACL for the
bucket itself.

=back

=head2 set_acl $conf

Retrieves the Access Control List (ACL) for the bucket or
resource. Requires a HASHREF argument with one of the following keys:

=over

=item acl_xml

An XML string which contains access control information
which matches Amazon's published schema.

=item acl_short

Alternative shorthand notation for common types of ACLs that
can be used in place of a ACL XML document.

According to the Amazon S3 API documentation the following recognized acl_short
types are defined as follows:

=over

=item private

Owner gets FULL_CONTROL. No one else has any access rights.
This is the default.

=item public-read

Owner gets FULL_CONTROL and the anonymous principal is
granted READ access. If this policy is used on an object, it
can be read from a browser with no authentication.

=item public-read-write

Owner gets FULL_CONTROL, the anonymous principal is granted
READ and WRITE access. This is a useful policy to apply to a
bucket, if you intend for any anonymous user to PUT objects
into the bucket.

=item authenticated-read

Owner gets FULL_CONTROL, and any principal authenticated as
a registered Amazon S3 user is granted READ access.

=back

=item key

The key name to apply the permissions. If the key is not
provided the bucket ACL will be set.

=back

Returns a boolean indicating the operations success.

=head2 get_location_constraint

Returns the location constraint data on a bucket.

For more information on location constraints, refer to the
Amazon S3 Developer Guide.

=head2 err

The S3 error code for the last error the account encountered.

=head2 errstr

A human readable error string for the last error the account encountered.

=head1 SEE ALSO

L<Bugzilla::S3>

=head1 AUTHOR & COPYRIGHT

Please see the L<Bugzilla::S3> manpage for author, copyright, and
license information.
