package HTTP::Tinyish::LWP;
use strict;
use parent qw(HTTP::Tinyish::Base);

use LWP 5.802;
use LWP::UserAgent;

my %supports = (http => 1);

sub configure {
    my %meta = (
        LWP => $LWP::VERSION,
    );

    if (eval { require LWP::Protocol::https; require Mozilla::CA; 1 }) {
        $supports{https} = 1;
        $meta{"LWP::Protocol::https"} = $LWP::Protocol::https::VERSION;
    }

    \%meta;
}

sub supports {
    $supports{$_[1]};
}

sub new {
    my($class, %attr) = @_;

    my $ua = LWP::UserAgent->new;
    
    bless {
        ua => $class->translate_lwp($ua, %attr),
    }, $class;
}

sub _headers_to_hashref {
    my($self, $hdrs) = @_;

    my %headers;
    for my $field ($hdrs->header_field_names) {
        $headers{lc $field} = $hdrs->header($field); # could be an array ref
    }

    \%headers;
}

sub request {
    my($self, $method, $url, $opts) = @_;
    $opts ||= {};

    my $req = HTTP::Request->new($method => $url);

    if ($opts->{headers}) {
        $req->header(%{$opts->{headers}});
    }

    if ($opts->{content}) {
        $req->content($opts->{content});
    }

    my $res = $self->{ua}->request($req);

    if ($self->is_internal_response($res)) {
        return $self->internal_error($url, $res->content);
    }

    return {
        url      => $url,
        content  => $res->decoded_content(charset => 'none'),
        success  => $res->is_success,
        status   => $res->code,
        reason   => $res->message,
        headers  => $self->_headers_to_hashref($res->headers),
        protocol => $res->protocol,
    };
}

sub mirror {
    my($self, $url, $file) = @_;

    # TODO support optional headers
    my $res = $self->{ua}->mirror($url, $file);

    if ($self->is_internal_response($res)) {
        return $self->internal_error($url, $res->content);
    }

    return {
        url      => $url,
        content  => $res->decoded_content,
        success  => $res->is_success || $res->code == 304,
        status   => $res->code,
        reason   => $res->message,
        headers  => $self->_headers_to_hashref($res->headers),
        protocol => $res->protocol,
    };
}

sub translate_lwp {
    my($class, $agent, %attr) = @_;

    $agent->parse_head(0);
    $agent->env_proxy;
    $agent->timeout(delete $attr{timeout} || 60);
    $agent->max_redirect(delete $attr{max_redirect} || 5);
    $agent->agent(delete $attr{agent} || "HTTP-Tinyish/$HTTP::Tinyish::VERSION");

    # LWP default is to verify, HTTP::Tiny isn't
    unless ($attr{verify_SSL}) {
        if ($agent->can("ssl_opts")) {
            $agent->ssl_opts(verify_hostname => 0);
        }
    }

    if ($attr{default_headers}) {
        $agent->default_headers( HTTP::Headers->new(%{$attr{default_headers}}) );
    }

    $agent;
}

sub is_internal_response {
    my($self, $res) = @_;

    $res->code == 500 &&
      ( $res->header('Client-Warning') || '' ) eq 'Internal response';
}

1;
