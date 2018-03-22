package Bugzilla::ModPerl::Hostage;
use 5.10.1;
use strict;
use warnings;

use Apache2::Const qw(:common); ## no critic (Freenode::ModPerl)

sub _attachment_root {
    my ($base) = @_;
    return undef unless $base;
    return $base =~ m{^https?://(?:bug)?\%bugid\%\.([a-zA-Z\.-]+)}
        ? $1
        : undef;
}

sub _attachment_host_regex {
    my ($base) = @_;
    return undef unless $base;
    my $val   = $base;
    $val =~ s{^https?://}{}s;
    $val =~ s{/$}{}s;
    my $regex = quotemeta $val;
    $regex =~ s/\\\%bugid\\\%/\\d+/g;
    return qr/^$regex$/s;
}

sub handler {
    my $r = shift;
    state $urlbase               = Bugzilla->localconfig->{urlbase};
    state $urlbase_uri           = URI->new($urlbase);
    state $urlbase_host          = $urlbase_uri->host;
    state $urlbase_host_regex    = qr/^bug(\d+)\.\Q$urlbase_host\E$/;
    state $attachment_base       = Bugzilla->localconfig->{attachment_base};
    state $attachment_root       = _attachment_root($attachment_base);
    state $attachment_host_regex = _attachment_host_regex($attachment_base);

    my $hostname  = $r->hostname;
    return OK if $hostname eq $urlbase_host;

    my $path = $r->uri;
    return OK if $path eq '/__lbheartbeat__';

    if ($attachment_base && $hostname eq $attachment_root) {
        $r->headers_out->set(Location => $urlbase);
        return REDIRECT;
    }
    elsif ($attachment_base && $hostname =~ $attachment_host_regex) {
        if ($path =~ m{^/attachment\.cgi}s) {
            return OK;
        } else {
            my $new_uri = URI->new($r->unparsed_uri);
            $new_uri->scheme($urlbase_uri->scheme);
            $new_uri->host($urlbase_host);
            $r->headers_out->set(Location => $new_uri);
            return REDIRECT;
        }
    }
    elsif (my ($id) = $hostname =~ $urlbase_host_regex) {
        my $new_uri = $urlbase_uri->clone;
        $new_uri->path('/show_bug.cgi');
        $new_uri->query_form(id => $id);
        $r->headers_out->set(Location => $new_uri);
        return REDIRECT;
    }
    else {
        $r->headers_out->set(Location => $urlbase);
        return REDIRECT;
    }
}

1;