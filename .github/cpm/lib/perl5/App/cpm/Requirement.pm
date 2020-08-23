package App::cpm::Requirement;
use strict;
use warnings;

use App::cpm::version;

sub new {
    my $class = shift;
    my $self = bless { requirement => [] }, $class;
    $self->add(@_) if @_;
    $self;
}

sub empty {
    my $self = shift;
    @{$self->{requirement}} == 0;
}

sub has {
    my ($self, $package) = @_;
    my ($found) = grep { $_->{package} eq $package } @{$self->{requirement}};
    $found;
}

sub add {
    my $self = shift;
    my %package = (@_, @_ % 2 ? (0) : ());
    for my $package (sort keys %package) {
        my $version_range = $package{$package};
        if (my ($found) = grep { $_->{package} eq $package } @{$self->{requirement}}) {
            my $merged = eval {
                App::cpm::version::range_merge($found->{version_range}, $version_range);
            };
            if (my $err = $@) {
                if ($err =~ /illegal requirements/) {
                    $@ = "Couldn't merge version range '$version_range' with '$found->{version_range}' for package '$package'";
                    warn $@; # XXX
                    return; # should check $@ in caller side
                } else {
                    die $err;
                }
            }
            $found->{version_range} = $merged;
        } else {
            push @{$self->{requirement}}, { package => $package, version_range => $version_range };
        }
    }
    return 1;
}

sub merge {
    my ($self, $other) = @_;
    $self->add(map { ($_->{package}, $_->{version_range}) } @{ $other->as_array });
}

sub delete :method {
    my ($self, @package) = @_;
    for my $i (reverse 0 .. $#{ $self->{requirement} }) {
        my $current = $self->{requirement}[$i]{package};
        if (grep { $current eq $_ } @package) {
            splice @{$self->{requirement}}, $i, 1;
        }
    }
}

sub as_array {
    my $self = shift;
    $self->{requirement};
}

1;
