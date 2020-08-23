package Carton::Util;
use strict;
use warnings;

sub load_json {
    my $file = shift;

    open my $fh, "<", $file or die "$file: $!";
    from_json(join '', <$fh>);
}

sub dump_json {
    my($data, $file) = @_;

    open my $fh, ">", $file or die "$file: $!";
    binmode $fh;
    print $fh to_json($data);
}

sub from_json {
    require JSON::PP;
    JSON::PP->new->utf8->decode($_[0])
}

sub to_json {
    my($data) = @_;
    require JSON::PP;
    JSON::PP->new->utf8->pretty->canonical->encode($data);
}

1;
