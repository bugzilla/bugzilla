package Carton::Index;
use strict;
use Class::Tiny {
    _packages => sub { +{} },
    generator => sub { require Carton; "Carton $Carton::VERSION" },
};

sub add_package {
    my($self, $package) = @_;
    $self->_packages->{$package->name} = $package; # XXX ||=
}

sub count {
    my $self = shift;
    scalar keys %{$self->_packages};
}

sub packages {
    my $self = shift;
    sort { lc $a->name cmp lc $b->name } values %{$self->_packages};
}

sub write {
    my($self, $fh) = @_;

    print $fh <<EOF;
File:         02packages.details.txt
URL:          http://www.perl.com/CPAN/modules/02packages.details.txt
Description:  Package names found in cpanfile.snapshot
Columns:      package name, version, path
Intended-For: Automated fetch routines, namespace documentation.
Written-By:   @{[ $self->generator ]}
Line-Count:   @{[ $self->count ]}
Last-Updated: @{[ scalar localtime ]}

EOF
    for my $p ($self->packages) {
        print $fh $self->_format_line($p->name, $p->version_format, $p->pathname);
    }
}

sub _format_line {
    my($self, @row) = @_;

    # from PAUSE::mldistwatch::rewrite02
    my $one = 30;
    my $two = 8;

    if (length $row[0] > $one) {
        $one += 8 - length $row[1];
        $two = length $row[1];
    }

    sprintf "%-${one}s %${two}s  %s\n", @row;
}

sub pad {
    my($str, $len, $left) = @_;

    my $howmany = $len - length($str);
    return $str if $howmany <= 0;

    my $pad = " " x $howmany;
    return $left ? "$pad$str" : "$str$pad";
}


1;
