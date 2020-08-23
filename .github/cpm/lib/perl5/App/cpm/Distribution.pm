package App::cpm::Distribution;
use strict;
use warnings;

use App::cpm::Logger;
use App::cpm::Requirement;
use App::cpm::version;
use CPAN::DistnameInfo;

use constant STATE_REGISTERED      => 0b000001;
use constant STATE_DEPS_REGISTERED => 0b000010;
use constant STATE_RESOLVED        => 0b000100; # default
use constant STATE_FETCHED         => 0b001000;
use constant STATE_CONFIGURED      => 0b010000;
use constant STATE_INSTALLED       => 0b100000;

sub new {
    my ($class, %option) = @_;
    my $uri = delete $option{uri};
    my $distfile = delete $option{distfile};
    my $source = delete $option{source} || "cpan";
    my $provides = delete $option{provides} || [];
    bless {
        %option,
        provides => $provides,
        uri => $uri,
        distfile => $distfile,
        source => $source,
        _state => STATE_RESOLVED,
        requirements => {},
    }, $class;
}

sub requirements {
    my ($self, $phase, $req) = @_;
    if (ref $phase) {
        my $req = App::cpm::Requirement->new;
        for my $p (@$phase) {
            if (my $r = $self->{requirements}{$p}) {
                $req->merge($r);
            }
        }
        return $req;
    }
    $self->{requirements}{$phase} = $req if $req;
    $self->{requirements}{$phase} || App::cpm::Requirement->new;
}

for my $attr (qw(
    source
    directory
    distdata
    meta
    uri
    provides
    ref
    static_builder
    prebuilt
)) {
    no strict 'refs';
    *$attr = sub {
        my $self = shift;
        $self->{$attr} = shift if @_;
        $self->{$attr};
    };
}
sub distfile {
    my $self = shift;
    $self->{distfile} = shift if @_;
    $self->{distfile} || $self->{uri};
}

sub distvname {
    my $self = shift;
    $self->{distvname} ||= do {
        CPAN::DistnameInfo->new($self->{distfile})->distvname || $self->distfile;
    };
}

sub overwrite_provide {
    my ($self, $provide) = @_;
    my $overwrote;
    for my $exist (@{$self->{provides}}) {
        if ($exist->{package} eq $provide->{package}) {
            $exist = $provide;
            $overwrote++;
        }
    }
    if (!$overwrote) {
        push @{$self->{provides}}, $provide;
    }
    return 1;
}

sub registered {
    my $self = shift;
    if (@_ && $_[0]) {
        $self->{_state} |= STATE_REGISTERED;
    }
    $self->{_state} & STATE_REGISTERED;
}

sub deps_registered {
    my $self = shift;
    if (@_ && $_[0]) {
        $self->{_state} |= STATE_DEPS_REGISTERED;
    }
    $self->{_state} & STATE_DEPS_REGISTERED;
}

sub resolved {
    my $self = shift;
    if (@_ && $_[0]) {
        $self->{_state} = STATE_RESOLVED;
    }
    $self->{_state} & STATE_RESOLVED;
}

sub fetched {
    my $self = shift;
    if (@_ && $_[0]) {
        $self->{_state} = STATE_FETCHED;
    }
    $self->{_state} & STATE_FETCHED;
}

sub configured {
    my $self = shift;
    if (@_ && $_[0]) {
        $self->{_state} = STATE_CONFIGURED
    }
    $self->{_state} & STATE_CONFIGURED;
}

sub installed {
    my $self = shift;
    if (@_ && $_[0]) {
        $self->{_state} = STATE_INSTALLED;
    }
    $self->{_state} & STATE_INSTALLED;
}

sub providing {
    my ($self, $package, $version_range) = @_;
    for my $provide (@{$self->provides}) {
        if ($provide->{package} eq $package) {
            if (!$version_range or App::cpm::version->parse($provide->{version})->satisfy($version_range)) {
                return 1;
            } else {
                my $message = sprintf "%s provides %s (%s), but needs %s\n",
                    $self->distfile, $package, $provide->{version} || 0, $version_range;
                App::cpm::Logger->log(result => "WARN", message => $message);
                last;
            }
        }
    }
    return;
}

sub equals {
    my ($self, $that) = @_;
    $self->distfile && $that->distfile and $self->distfile eq $that->distfile;
}

1;
