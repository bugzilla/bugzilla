# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::CGI::ContentSecurityPolicy;

use 5.10.1;
use strict;
use warnings;
use Moo;
use MooX::StrictConstructor;
use Types::Standard qw(Bool Str ArrayRef);
use Type::Utils;

use Bugzilla::Util qw(generate_random_password);

my $SRC_KEYWORD = enum['none', 'self', 'unsafe-inline', 'unsafe-eval', 'nonce'];
my $SRC_URI = declare as Str, where {
    $_ =~ m{
        ^(?: https?:// )?  # optional http:// or https://
        [*A-Za-z0-9.-]+    # hostname including wildcards. Possibly too permissive.
        (?: :[0-9]+ )?     # optional port
    }x;
};
my $SRC      = $SRC_KEYWORD | $SRC_URI;
my $SOURCE_LIST = ArrayRef[$SRC];
my $REFERRER_KEYWORD = enum [qw(
    no-referrer no-referrer-when-downgrade
    origin      origin-when-cross-origin unsafe-url
)];

my @ALL_BOOL = qw( sandbox upgrade_insecure_requests );
my @ALL_SRC = qw(
    default_src child_src  connect_src
    font_src    img_src    media_src
    object_src  script_src style_src
    frame_ancestors form_action
);

has \@ALL_SRC     => ( is => 'ro', isa => $SOURCE_LIST, predicate => 1 );
has \@ALL_BOOL    => ( is => 'ro', isa => Bool, default => 0 );
has 'report_uri'  => ( is => 'ro', isa => Str, predicate => 1 );
has 'base_uri'    => ( is => 'ro', isa => Str, predicate => 1 );
has 'report_only' => ( is => 'ro', isa => Bool );
has 'referrer'    => ( is => 'ro', isa => $REFERRER_KEYWORD, predicate => 1 );
has 'value'       => ( is => 'lazy' );
has 'nonce'       => ( is => 'lazy', init_arg => undef, predicate => 1 );
has 'disable'     => ( is => 'ro', isa => Bool, default => 0 );

sub _has_directive {
    my ($self, $directive) = @_;
    my $method = 'has_' . $directive;
    return $self->$method;
}

sub header_names {
    my ($self) = @_;
    my @names = ('Content-Security-Policy');
    if ($self->report_only) {
        return map { $_ . '-Report-Only' } @names;
    }
    else {
        return @names;
    }
}

sub add_cgi_headers {
    my ($self, $headers) = @_;
    return if $self->disable;
    foreach my $name ($self->header_names) {
        $headers->{"-$name"} = $self->value;
    }
}

sub _build_value {
    my $self = shift;
    my @result;

    my @list_directives = (@ALL_SRC);
    my @boolean_directives = (@ALL_BOOL);
    my @single_directives  = qw(report_uri base_uri);

    foreach my $directive (@list_directives) {
        next unless $self->_has_directive($directive);
        my @values = map { $self->_quote($_) } @{ $self->$directive };
        if (@values) {
            push @result, join(' ', _name($directive), @values);
        }
    }

    foreach my $directive (@single_directives) {
        next unless $self->_has_directive($directive);
        my $value = $self->$directive;
        if (defined $value) {
            push @result, _name($directive) . ' ' . $value;
        }
    }

    foreach my $directive (@boolean_directives) {
        if ($self->$directive) {
            push @result, _name($directive);
        }
    }

    return join('; ', @result);
}

sub _build_nonce {
    return generate_random_password(48);
}

sub _name {
    my $name = shift;
    $name =~ tr/_/-/;
    return $name;
}

sub _quote {
    my ($self, $val) = @_;

    if ($val eq 'nonce') {
        return q{'nonce-} . $self->nonce . q{'};
    }
    elsif ($SRC_KEYWORD->check($val)) {
        return qq{'$val'};
    }
    else {
        return $val;
    }
}



1;

__END__

=head1 NAME

Bugzilla::CGI::ContentSecurityPolicy - Object-oriented interface to generating CSP directives and adding them to headers.

=head1 SYNOPSIS

    use Bugzilla::CGI::ContentSecurityPolicy;

    my $csp = Bugzilla::CGI::ContentSecurityPolicy->new(
        default_src => [ 'self' ],
        style_src   => [ 'self', 'unsafe-inline' ],
        script_src  => [ 'self', 'nonce' ],
        child_src   => ['none'],
        report_uri  => '/csp-report.cgi',
        referrer    => 'origin-when-cross-origin',
    );
    $csp->headers_names               # returns a list of header names and depends on the value of $self->report_only
    $csp->value                       # returns the string representation of the policy.
    $csp->add_cgi_headers(\%hashref); # will insert entries compatible with CGI.pm's $cgi->headers() method into the provided hashref.

=head1 DESCRIPTION

This class provides an object interface to constructing Content Security Policies.

Rather than use this module, scripts should call $cgi->content_security_policy() which constructs the CSP headers
and registers them for the current request.

See L<Bugzilla::CGI> for details.

=head1 ATTRIBUTES

Generally all CSP directives are available as attributes to the constructor,
with dashes replaced by underscores. All directives that can be lists must be
passed as array references, and the quoting rules for urls and keywords like
'self' or 'none' is handled automatically.

=head2 report_only

If this is true, then the the -Report-Only version of the headers will be produced, so nothing will be blocked.

=head2 disable

If this is true, no CSP headers will be used at all.

=head2 base_uri

The base-uri directive defines the URIs that a user agent may use as the
document base URL. If this value is absent, then any URI is allowed. If this
directive is absent, the user agent will use the value in the base element.

=head2 child_src

The child-src directive defines the valid sources for web workers and nested
browsing contexts loaded using elements such as <frame> and <iframe>. This
directive is preferred over the frame-src directive, which is deprecated. For
workers, non-compliant requests are treated as fatal network errors by the user
agent.

=head2 connect_src

The connect-src directive defines valid sources for fetch, XMLHttpRequest, WebSocket, and EventSource connections.

=head2 default_src

The default-src directive defines the security policy for types of content which are not expressly called out by more specific directives. This directive covers the following directives:

=over 4

=item *

L</child_src>

=item *

L</connect_src>

=item *

L</font_src>

=item *

L</img_src>

=item *

L</media_src>

=item *

L</object_src>

=item *

L</script_src>

=item *

L</style_src>

=back

=head2 font_src

The font-src directive specifies valid sources for fonts loaded using @font-face.

=head2 img_src

The img-src directive specifies valid sources of images and favicons.

=head2 manifest_src

The manifest-src directive specifies which manifest can be applied to the resource.

=head2 media_src

The media-src directive specifies valid sources for loading media using the <audio> and <video> elements.

=head2 object_src

The object-src directive specifies valid sources for the <object>, <embed>, and <applet> elements.

=head2 referrer

The referrer directive specifies information in the B<referer> (sic) header for
links away from a page. Valid values are C<no-referrer>,
C<no-referrer-when-downgrade>, C<origin>, C<origin-when-cross-origin>, and
C<unsafe-url>.

=head2 report_uri

The report-uri directive instructs the user agent to report attempts to violate
the Content Security Policy. These violation reports consist of JSON documents
sent via an HTTP POST request to the specified URI.

=head2 sandbox

The sandbox directive applies restrictions to a page's actions including
preventing popups, preventing the execution of plugins and scripts, and
enforcing a same-origin policy.

=head2 script_src

The script-src directive specifies valid sources for JavaScript. When either the
script-src or the default-src directive is included, inline script and eval()
are disabled unless you specify 'unsafe-inline' and 'unsafe-eval', respectively.
In Chrome 49 and later, 'script-src http' will match both HTTP and HTTPS.

=head2 style_src

The style-src directive specifies valid sources for stylesheets. This includes
both externally-loaded stylesheets and inline use of the C<style> element and
HTML style attributes. Stylesheets from sources that aren't included in the
source list are not requested or loaded. When either the style-src or the
default-src directive is included, inline use of the C<style> element and HTML
style attributes are disabled unless you specify 'unsafe-inline'.

=head2 upgrade_insecure_requests

The upgrade-insecure-requests directive instructs user agents to treat all of a
site's unsecure URL's (those serverd over HTTP) as though they have been
replaced with secure URL's (those served over HTTPS). This directive is intended
for web sites with large numbers of unsecure legacy URL's that need to be
rewritten.

=head1 METHODS

=head2 header_names()

This returns a list of header names. This will typically be
C<Content-Security-Policy>, C<X-Content-Security-Policy>, and C<X-WebKit-CSP>.

=head2 value()

This returns the value or right-of-colon part of the header.

=head2 add_cgi_headers($headers)

This adds C<header_value()> to C<$headers> in a format that is compatible with
L<CGI>'s headers() method.

=head2 nonce() / has_nonce()

This is unique value that can used if the 'nonce' is used as a source for
style_src or script_src.

=head1 B<Methods in need of POD>

=over 4

=item has_report_uri

=item has_child_src

=item has_connect_src

=item has_script_src

=item has_media_src

=item has_base_uri

=item has_img_src

=item has_referrer

=item has_style_src

=item has_default_src

=item has_object_src

=item has_font_src

=back
