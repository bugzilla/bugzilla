# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Quantum::Plugin::Glue;
use 5.10.1;
use Mojo::Base 'Mojolicious::Plugin';

use Try::Tiny;
use Bugzilla::Constants;
use Bugzilla::Logging;
use Bugzilla::RNG ();
use JSON::MaybeXS qw(decode_json);
use Scope::Guard;

sub register {
    my ( $self, $app, $conf ) = @_;

    my %D;
    if ( $ENV{BUGZILLA_HTTPD_ARGS} ) {
        my $args = decode_json( $ENV{BUGZILLA_HTTPD_ARGS} );
        foreach my $arg (@$args) {
            if ( $arg =~ /^-D(\w+)$/ ) {
                $D{$1} = 1;
            }
            else {
                die "Unknown httpd arg: $arg";
            }
        }
    }

    $app->hook(
        before_dispatch => sub {
            my ($c) = @_;
            if ( $D{HTTPD_IN_SUBDIR} ) {
                my $path = $c->req->url->path;
                if ( $path =~ s{^/bmo}{}s ) {
                    $c->stash->{bmo_prefix} = 1;
                    $c->req->url->path($path);
                }
            }
            Log::Log4perl::MDC->put( request_id => $c->req->request_id );
            $c->stash->{cleanup_guard} = Scope::Guard->new( \&Bugzilla::cleanup );
        }
    );


    $app->secrets( [ Bugzilla->localconfig->{side_wide_secret} ] );

    $app->renderer->add_handler(
        'bugzilla' => sub {
            my ( $renderer, $c, $output, $options ) = @_;
            my $vars = delete $c->stash->{vars};

            # Helpers
            my %helper;
            foreach my $method ( grep {m/^\w+\z/} keys %{ $renderer->helpers } ) {
                my $sub = $renderer->helpers->{$method};
                $helper{$method} = sub { $c->$sub(@_) };
            }
            $vars->{helper} = \%helper;

            # The controller
            $vars->{c} = $c;
            my $name = $options->{template};
            unless ( $name =~ /\./ ) {
                $name = sprintf '%s.%s.tmpl', $options->{template}, $options->{format};
            }
            my $template = Bugzilla->template;
            $template->process( $name, $vars, $output )
              or die $template->error;
        }
    );

    $app->log( MojoX::Log::Log4perl::Tiny->new( logger => Log::Log4perl->get_logger( ref $app ) ) );
}

1;
