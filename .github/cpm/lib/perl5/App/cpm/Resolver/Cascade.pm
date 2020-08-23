package App::cpm::Resolver::Cascade;
use strict;
use warnings;

sub new {
    my $class = shift;
    bless { backends => [] }, $class;
}

sub add {
    my ($self, $resolver) = @_;
    push @{ $self->{backends} }, $resolver;
    $self;
}

sub resolve {
    my ($self, $job) = @_;
    # here job = { package => "Plack", version_range => ">= 1.000, < 1.0030" }

    my @error;
    for my $backend (@{ $self->{backends} }) {
        my $result = $backend->resolve($job);
        next unless $result;

        my $klass = ref $backend;
        $klass = $1 if $klass =~ /^App::cpm::Resolver::(.*)$/;
        if (my $error = $result->{error}) {
            push @error, "$klass, $error";
        } else {
            $result->{from} = $klass;
            return $result;
        }
    }
    return { error => join("\n", @error) };
}

1;
