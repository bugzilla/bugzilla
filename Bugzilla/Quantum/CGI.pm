# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Quantum::CGI;
use Mojo::Base 'Mojolicious::Controller';

use CGI::Compile;
use Try::Tiny;
use Taint::Util qw(untaint);
use Sys::Hostname;
use Sub::Quote 2.005000;
use Sub::Name;
use Socket qw(AF_INET inet_aton);
use File::Spec::Functions qw(catfile);
use File::Slurper qw(read_text);
use English qw(-no_match_vars);
use Bugzilla::Quantum::Stdout;
use Bugzilla::Constants qw(bz_locations);

our $C;
my %SEEN;

sub load_all {
    my ( $class, $r ) = @_;

    foreach my $file ( glob '*.cgi' ) {
        my $name = _file_to_method($file);
        $class->load_one( $name, $file );
        $r->any("/$file")->to("CGI#$name");
    }
}

sub load_one {
    my ( $class, $name, $file ) = @_;
    my $package = __PACKAGE__ . "::$name", my $inner_name = "_$name";
    my $content = read_text( catfile( bz_locations->{cgi_path}, $file ) );
    $content = "package $package; $content";
    untaint($content);
    my %options = (
        package  => $package,
        file     => $file,
        line     => 1,
        no_defer => 1,
    );
    die "Tried to load $file more than once" if $SEEN{$file}++;
    my $inner = quote_sub $inner_name, $content, {}, \%options;
    my $wrapper = sub {
        my ($c) = @_;
        my $stdin = $c->_STDIN;
        local $C                           = $c;
        local %ENV                         = $c->_ENV($file);
        local $CGI::Compile::USE_REAL_EXIT = 0;
        local $PROGRAM_NAME                = $file;
        local *STDIN;    ## no critic (local)
        open STDIN, '<', $stdin->path or die "STDIN @{[$stdin->path]}: $!" if -s $stdin->path;
        tie *STDOUT, 'Bugzilla::Quantum::Stdout', controller => $c;    ## no critic (tie)
        try {
            Bugzilla->init_page();
            $inner->();
        }
        catch {
            die $_ unless ref $_ eq 'ARRAY' && $_->[0] eq "EXIT\n";
        }
        finally {
            untie *STDOUT;
            $c->finish;
            Bugzilla->cleanup;
            CGI::initialize_globals();
        };
    };

    no strict 'refs';    ## no critic (strict)
    *{$name} = subname( $name, $wrapper );
    return 1;
}


sub _ENV {
    my ( $c, $script_name ) = @_;
    my $tx             = $c->tx;
    my $req            = $tx->req;
    my $headers        = $req->headers;
    my $content_length = $req->content->is_multipart ? $req->body_size : $headers->content_length;
    my %env_headers    = ( HTTP_COOKIE => '', HTTP_REFERER => '' );

    for my $name ( @{ $headers->names } ) {
        my $key = uc "http_$name";
        $key =~ s/\W/_/g;
        $env_headers{$key} = $headers->header($name);
    }

    my $remote_user;
    if ( my $userinfo = $req->url->to_abs->userinfo ) {
        $remote_user = $userinfo =~ /([^:]+)/ ? $1 : '';
    }
    elsif ( my $authenticate = $headers->authorization ) {
        $remote_user = $authenticate =~ /Basic\s+(.*)/ ? b64_decode $1 : '';
        $remote_user = $remote_user =~ /([^:]+)/       ? $1            : '';
    }
    my $path_info = $c->stash->{'mojo.captures'}{'PATH_INFO'};
    my %captures = %{ $c->stash->{'mojo.captures'} // {} };
    foreach my $key ( keys %captures ) {
        if ( $key eq 'controller' || $key eq 'action' || $key eq 'PATH_INFO' || $key =~ /^REWRITE_/ ) {
            delete $captures{$key};
        }
    }
    my $cgi_query = Mojo::Parameters->new(%captures);
    $cgi_query->append( $req->url->query );
    my $prefix = $c->stash->{bmo_prefix} ? '/bmo/' : '/';

    return (
        %ENV,
        CONTENT_LENGTH => $content_length        || 0,
        CONTENT_TYPE   => $headers->content_type || '',
        GATEWAY_INTERFACE => 'CGI/1.1',
        HTTPS             => $req->is_secure ? 'on' : 'off',
        %env_headers,
        QUERY_STRING    => $cgi_query->to_string,
        PATH_INFO       => $path_info ? "/$path_info" : '',
        REMOTE_ADDR     => $tx->original_remote_address,
        REMOTE_HOST     => $tx->original_remote_address,
        REMOTE_PORT     => $tx->remote_port,
        REMOTE_USER     => $remote_user || '',
        REQUEST_METHOD  => $req->method,
        SCRIPT_NAME     => "$prefix$script_name",
        SERVER_NAME     => hostname,
        SERVER_PORT     => $tx->local_port,
        SERVER_PROTOCOL => $req->is_secure ? 'HTTPS' : 'HTTP',    # TODO: Version is missing
        SERVER_SOFTWARE => __PACKAGE__,
    );
}

sub _STDIN {
    my $c = shift;
    my $stdin;

    if ( $c->req->content->is_multipart ) {
        $stdin = Mojo::Asset::File->new;
        $stdin->add_chunk( $c->req->build_body );
    }
    else {
        $stdin = $c->req->content->asset;
    }

    return $stdin if $stdin->isa('Mojo::Asset::File');
    return Mojo::Asset::File->new->add_chunk( $stdin->slurp );
}

sub _file_to_method {
    my ($name) = @_;
    $name =~ s/\./_/s;
    $name =~ s/\W+/_/gs;
    return $name;
}

1;
