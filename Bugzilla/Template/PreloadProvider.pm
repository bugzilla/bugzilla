# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# This exists to implement the template-before_process hook.
package Bugzilla::Template::PreloadProvider;

use 5.10.1;
use strict;
use warnings;

use base qw(Template::Provider);

use File::Find ();
use Cwd ();
use File::Spec;
use Template::Constants qw( STATUS_ERROR );
use Template::Document;
use Template::Config;

use Bugzilla::Util qw(trick_taint);

sub _init {
    my $self = shift;
    $self->SUPER::_init(@_);

    my $path   = $self->{INCLUDE_PATH};
    my $cache  = $self->{_BZ_CACHE} = {};
    my $search = $self->{_BZ_SEARCH} = {};

    foreach my $template_dir (@$path) {
        $template_dir = Cwd::realpath($template_dir);
        my $wanted = sub {
            my ( $name, $dir ) = ($File::Find::name, $File::Find::dir);
            if ( $name =~ /\.tmpl$/ ) {
                my $key = $name;
                $key =~ s/^\Q$template_dir\///;
                unless ($search->{$key}) {
                    $search->{$key} = $name;
                }
                trick_taint($name);
                my $data = {
                    name => $key,
                    text => do {
                        open my $fh, '<:utf8', $name or die "cannot open $name";
                        local $/ = undef;
                        scalar <$fh>; # $fh is closed it goes out of scope
                    },
                    time => (stat($name))[9],
                };
                trick_taint($data->{text}) if $data->{text};
                $cache->{$name} = $self->_bz_compile($data) or die "compile error: $name";
            }
        };
        File::Find::find( { wanted => $wanted, no_chdir => 1 }, $template_dir );
    }

    return $self;
}

sub fetch {
    my ($self, $name, $prefix) = @_;
    my $file;
    if (File::Spec->file_name_is_absolute($name)) {
        $file = $name;
    }
    elsif ($name =~ m#^\./#) {
        $file = File::Spec->rel2abs($name);
    }
    else {
        $file = $self->{_BZ_SEARCH}{$name};
    }

    if (not $file) {
        return ("cannot find file - $name ($file)", STATUS_ERROR);
    }

    if ($self->{_BZ_CACHE}{$file}) {
        return ($self->{_BZ_CACHE}{$file}, undef);
    }
    else {
        return ("unknown file - $file", STATUS_ERROR);
    }
}

sub _bz_compile {
    my ($self, $data) = @_;

    my $parser = $self->{PARSER} ||= Template::Config->parser( $self->{PARAMS} )
        || return ( Template::Config->error(), STATUS_ERROR );

    # discard the template text - we don't need it any more
    my $text = delete $data->{text};

    # call parser to compile template into Perl code
    if (my $parsedoc = $parser->parse($text, $data)) {
        $parsedoc->{METADATA} = {
            'name' => $data->{name},
            'modtime' => $data->{time},
            %{ $parsedoc->{METADATA} },
        };

        return Template::Document->new($parsedoc);
    }
}

1;
