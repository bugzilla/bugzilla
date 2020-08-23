package HTTP::Tinyish::Base;
use strict;
use warnings;

for my $sub_name ( qw/get head put post delete patch/ ) {
    my $req_method = uc $sub_name;
    eval <<"HERE";
    sub $sub_name {
        my (\$self, \$url, \$args) = \@_;
        \@_ == 2 || (\@_ == 3 && ref \$args eq 'HASH')
        or Carp::croak(q/Usage: \$http->$sub_name(URL, [HASHREF])/ . "\n");
        return \$self->request('$req_method', \$url, \$args || {});
    }

HERE
}

sub parse_http_header {
    my($self, $header, $res) = @_;

    # it might have multiple headers in it because of redirects
    $header =~ s/.*^(HTTP\/\d(?:\.\d)?)/$1/ms;

    # grab the first chunk until the line break
    if ($header =~ /^(.*?\x0d?\x0a\x0d?\x0a)/) {
        $header = $1;
    }

    # parse into lines
    my @header = split /\x0d?\x0a/,$header;
    my $status_line = shift @header;

    # join folded lines
    my @out;
    for (@header) {
        if(/^[ \t]+/) {
            return -1 unless @out;
            $out[-1] .= $_;
        } else {
            push @out, $_;
        }
    }

    my($proto, $status, $reason) = split / /, $status_line, 3;
    return unless $proto and $proto =~ /^HTTP\/(\d+)(\.(\d+))?$/i;

    $res->{status} = $status;
    $res->{reason} = $reason;
    $res->{success} = $status =~ /^(?:2|304)/;
    $res->{protocol} = $proto;

    # import headers
    my $token = qr/[^][\x00-\x1f\x7f()<>@,;:\\"\/?={} \t]+/;
    my $k;
    for my $header (@out) {
        if ( $header =~ s/^($token): ?// ) {
            $k = lc $1;
        } elsif ( $header =~ /^\s+/) {
            # multiline header
        } else {
            return -1;
        }

        if (exists $res->{headers}{$k}) {
            $res->{headers}{$k} = [$res->{headers}{$k}]
              unless ref $res->{headers}{$k};
            push @{$res->{headers}{$k}}, $header;
        } else {
            $res->{headers}{$k} = $header;
        }
    }
}

sub internal_error {
    my($self, $url, $message) = @_;

    return {
        content => $message,
        headers => { "content-length" => length($message), "content-type" => "text/plain" },
        reason  => "Internal Exception",
        status  => 599,
        success => "",
        url     => $url,
    };
}

1;
