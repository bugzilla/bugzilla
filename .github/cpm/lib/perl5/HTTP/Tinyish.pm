package HTTP::Tinyish;
use strict;
use warnings;
use Carp ();

our $VERSION = '0.16';

our $PreferredBackend; # for tests
our @Backends = map "HTTP::Tinyish::$_", qw( LWP HTTPTiny Curl Wget );
my %configured;

sub new {
    my($class, %attr) = @_;
    bless \%attr, $class;
}

for my $method (qw/get head put post delete mirror patch/) {
    no strict 'refs';
    eval <<"HERE";
    sub $method {
        my \$self = shift;
        \$self->_backend_for(\$_[0])->$method(\@_);
    }
HERE
}

sub request {
    my $self = shift;
    $self->_backend_for($_[1])->request(@_);
}

sub _backend_for {
    my($self, $url) = @_;

    my($scheme) = $url =~ m!^(https?):!;
    Carp::croak "URL Scheme '$url' not supported." unless $scheme;

    for my $backend ($self->backends) {
        $self->configure_backend($backend) or next;
        if ($backend->supports($scheme)) {
            return $backend->new(%$self);
        }
    }

    Carp::croak "No backend configured for scheme $scheme";
}

sub backends {
    $PreferredBackend ? ($PreferredBackend) : @Backends;
}

sub configure_backend {
    my($self, $backend) = @_;
    unless (exists $configured{$backend}) {
        $configured{$backend} =
          eval { require_module($backend); $backend->configure };
    }
    $configured{$backend};
}

sub require_module {
    local $_ = shift;
    s!::!/!g;
    require "$_.pm";
}

1;

__END__

=head1 NAME

HTTP::Tinyish - HTTP::Tiny compatible HTTP client wrappers

=head1 SYNOPSIS

  my $http = HTTP::Tinyish->new(agent => "Mozilla/4.0");

  my $res = $http->get("http://www.cpan.org/");
  warn $res->{status};

  $http->post("http://example.com/post", {
      headers => { "Content-Type" => "application/x-www-form-urlencoded" },
      content => "foo=bar&baz=quux",
  });

  $http->mirror("http://www.cpan.org/modules/02packages.details.txt.gz", "./02packages.details.txt.gz");

=head1 DESCRIPTION

HTTP::Tinyish is a wrapper module for HTTP client modules
L<LWP>, L<HTTP::Tiny> and HTTP client software C<curl> and C<wget>.

It provides an API compatible to HTTP::Tiny, and the implementation
has been extracted out of L<App::cpanminus>. This module can be useful
in a restrictive environment where you need to be able to download
CPAN modules without an HTTPS support in built-in HTTP library.

=head1 BACKEND SELECTION

Backends are searched in the order of: C<LWP>, L<HTTP::Tiny>, L<Curl>
and L<Wget>. HTTP::Tinyish will auto-detect if the backend also
supports HTTPS, and use the appropriate backend based on the given
URL to the request methods.

For example, if you only have HTTP::Tiny but without SSL related
modules, it is possible that:

  my $http = HTTP::Tinyish->new;

  $http->get("http://example.com");  # uses HTTP::Tiny
  $http->get("https://example.com"); # uses curl

=head1 COMPATIBILITIES

All request related methods such as C<get>, C<post>, C<put>,
C<delete>, C<request>, C<patch> and C<mirror> are supported.

=head2 LWP

=over 4

=item *

L<LWP> backend requires L<LWP> 5.802 or over to be functional, and L<LWP::Protocol::https> to send HTTPS requests.

=item *

C<mirror> method doesn't consider third options hash into account (i.e. you can't override the HTTP headers).

=item *

proxy is automatically detected from environment variables.

=item *

C<timeout>, C<max_redirect>, C<agent>, C<default_headers> and C<verify_SSL> are translated.

=back

=head2 HTTP::Tiny

Because the actual HTTP::Tiny backend is used, all APIs are supported.

=head2 Curl

=over

=item *

This module has been tested with curl 7.22 and later.

=item *

HTTPS support is automatically detected by running C<curl --version> and see its protocol output.

=item *

C<timeout>, C<max_redirect>, C<agent>, C<default_headers> and C<verify_SSL> are supported.

=back

=head2 Wget

=over 4

=item *

This module requires Wget 1.12 and later.

=item *

Wget prior to 1.15 doesn't support sending custom HTTP methods, so if you use C<< $http->put >> for example, you'll get an internal error response (599).

=item *

HTTPS support is automatically detected.

=item *

C<mirror()> method doesn't send C<If-Modified-Since> header to the server, which will result in full-download every time because C<wget> doesn't support C<--timestamping> combined with C<-O> option.

=item *

C<timeout>, C<max_redirect>, C<agent>, C<default_headers> and C<verify_SSL> are supported.

=back

=head1 SIMILAR MODULES

=over 4

=item *

L<File::Fetch> - is core since 5.10. Has support for non-HTTP protocols such as ftp and git. Does not support HTTPS or basic authentication as of this writing.

=item *

L<Plient> - provides more complete runtime API, but seems only compatible on Unix environments. Does not support mirror() method.

=back

=head1 AUTHOR

Tatsuhiko Miyagawa

=head1 COPYRIGHT

Tatsuhiko Miyagawa, 2015-

=head1 LICENSE

This module is licensed under the same terms as Perl itself.

=cut

