package Command::Runner::LineBuffer;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $buffer = exists $args{buffer} ? $args{buffer} : "";
    bless {
        buffer => $buffer,
        $args{keep} ? (keep => $buffer) : (),
    }, $class;
}

sub raw {
    my $self = shift;
    exists $self->{keep} ? $self->{keep} : undef;
}

sub add {
    my ($self, $buffer) = @_;
    $self->{buffer} .= $buffer;
    $self->{keep} .= $buffer if exists $self->{keep};
    $self;
}

sub get {
    my ($self, $drain) = @_;
    if ($drain) {
        if (length $self->{buffer}) {
            my @line = $self->get;
            if (length $self->{buffer} and $self->{buffer} ne "\x0d") {
                $self->{buffer} =~ s/[\x0d\x0a]+\z//;
                push @line, $self->{buffer};
            }
            $self->{buffer} = "";
            return @line;
        } else {
            return;
        }
    }
    my @line;
    while ($self->{buffer} =~ s/\A(.*?(?:\x0d\x0a|\x0d|\x0a))//sm) {
        my $line = $1;
        next if $line eq "\x0d";
        $line =~ s/[\x0d\x0a]+\z//;
        push @line, $line;
    }
    return @line;
}

1;
