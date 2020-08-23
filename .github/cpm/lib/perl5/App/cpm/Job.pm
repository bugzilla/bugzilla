package App::cpm::Job;
use strict;
use warnings;
use CPAN::DistnameInfo;

sub new {
    my ($class, %option) = @_;
    my $self = bless {%option}, $class;
    $self->{uid} = $self->_uid;
    $self;
}

sub uid { shift->{uid} }

sub _uid {
    my $self = shift;
    my $type = $self->type;
    if (grep { $type eq $_ } qw(fetch configure install)) {
        "$type " . $self->distfile;
    } elsif ($type eq "resolve") {
        "$type " . $self->{package};
    } else {
        die "unknown type: " . ($type || "(undef)");
    }
}

sub distfile {
    my $self = shift;
    $self->{distfile} || $self->{uri};
}

sub distvname {
    my $self = shift;
    return $self->{_distvname} if $self->{_distvname};
    if ($self->{distfile}) {
        $self->{_distvname} ||= CPAN::DistnameInfo->new($self->{distfile})->distvname;
    } elsif ($self->{uri}) {
        $self->{uri};
    } elsif ($self->{package}) {
        $self->{package};
    } else {
        "UNKNOWN";
    }
}

sub distname {
    my $self = shift;
    $self->{_distname} ||= CPAN::DistnameInfo->new($self->distfile)->dist || 'UNKNOWN';
}

sub cpanid {
    my $self = shift;
    $self->{_cpanid} ||= CPAN::DistnameInfo->new($self->distfile)->cpanid || 'UNKNOWN';
}

sub type {
    my $self = shift;
    $self->{type};
}

sub in_charge {
    my $self = shift;
    @_ ? $self->{in_charge} = shift : $self->{in_charge};
}

sub is_success {
    my $self = shift;
    $self->{ok};
}

sub equals {
    my ($self, $that) = @_;
    $self->uid eq $that->uid;
}

sub merge {
    my ($self, $that) = @_;
    for my $key (keys %$that) {
        $self->{$key} = $that->{$key};
    }
    $self;
}

1;
