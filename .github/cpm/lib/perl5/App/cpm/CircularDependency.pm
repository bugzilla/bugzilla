package App::cpm::CircularDependency;
use strict;
use warnings;

{
    package
        App::cpm::CircularDependency::OrderedSet;
    sub new {
        my $class = shift;
        bless { index => 0, hash => +{} }, $class;
    }
    sub add {
        my ($self, $name) = @_;
        $self->{hash}{$name} = $self->{index}++;
    }
    sub exists {
        my ($self, $name) = @_;
        exists $self->{hash}{$name};
    }
    sub values {
        my $self = shift;
        sort { $self->{hash}{$a} <=> $self->{hash}{$b} } keys %{$self->{hash}};
    }
    sub clone {
        my $self = shift;
        my $new = (ref $self)->new;
        $new->add($_) for $self->values;
        $new;
    }
}

sub _uniq {
    my %u;
    grep !$u{$_}++, @_;
}

sub new {
    my $class = shift;
    bless { _tmp => {} }, $class;
}

sub add {
    my ($self, $distfile, $provides, $requirements) = @_;
    $self->{_tmp}{$distfile} = +{
        provides => [ map $_->{package}, @$provides ],
        requirements => [ map $_->{package}, @$requirements ],
    };
}

sub finalize {
    my $self = shift;
    for my $distfile (sort keys %{$self->{_tmp}}) {
        $self->{$distfile} = [
            _uniq map $self->_find($_), @{$self->{_tmp}{$distfile}{requirements}}
        ];
    }
    delete $self->{_tmp};
    return;
}

sub _find {
    my ($self, $package) = @_;
    for my $distfile (sort keys %{$self->{_tmp}}) {
        if (grep { $_ eq $package } @{$self->{_tmp}{$distfile}{provides}}) {
            return $distfile;
        }
    }
    return;
}

sub detect {
    my $self = shift;

    my %result;
    for my $distfile (sort keys %$self) {
        my $seen = App::cpm::CircularDependency::OrderedSet->new;
        $seen->add($distfile);
        if (my $detected = $self->_detect($distfile, $seen)) {
            $result{$distfile} = $detected;
        }
    }
    return \%result;
}

sub _detect {
    my ($self, $distfile, $seen) = @_;

    for my $req (@{$self->{$distfile}}) {
        if ($seen->exists($req)) {
            return [$seen->values, $req];
        }

        my $clone = $seen->clone;
        $clone->add($req);
        if (my $detected = $self->_detect($req, $clone)) {
            return $detected;
        }
    }
    return;
}

1;
