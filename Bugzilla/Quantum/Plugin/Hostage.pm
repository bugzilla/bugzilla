package Bugzilla::Quantum::Plugin::Hostage;
use 5.10.1;
use Mojo::Base 'Mojolicious::Plugin';
use Bugzilla::Logging;

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
    my $val = $base;
    $val =~ s{^https?://}{}s;
    $val =~ s{/$}{}s;
    my $regex = quotemeta $val;
    $regex =~ s/\\\%bugid\\\%/\\d+/g;
    return qr/^$regex$/s;
}

sub register {
    my ( $self, $app, $conf ) = @_;

    $app->hook( before_routes => \&_before_routes );
}

sub _before_routes {
    my ($c) = @_;
    state $urlbase               = Bugzilla->localconfig->{urlbase};
    state $urlbase_uri           = URI->new($urlbase);
    state $urlbase_host          = $urlbase_uri->host;
    state $urlbase_host_regex    = qr/^bug(\d+)\.\Q$urlbase_host\E$/;
    state $attachment_base       = Bugzilla->localconfig->{attachment_base};
    state $attachment_root       = _attachment_root($attachment_base);
    state $attachment_host_regex = _attachment_host_regex($attachment_base);

    my $stash = $c->stash;
    my $req   = $c->req;
    my $url   = $req->url->to_abs;

    return if $stash->{'mojo.static'};

    my $hostname = $url->host;
    return if $hostname eq $urlbase_host;

    my $path = $url->path;
    return if $path eq '/__lbheartbeat__';

    if ( $attachment_base && $hostname eq $attachment_root ) {
        DEBUG("redirecting to $urlbase because $hostname is $attachment_root");
        $c->redirect_to($urlbase);
        return;
    }
    elsif ( $attachment_base && $hostname =~ $attachment_host_regex ) {
        if ( $path =~ m{^/attachment\.cgi}s ) {
            return;
        }
        else {
            my $new_uri = $url->clone;
            $new_uri->scheme( $urlbase_uri->scheme );
            $new_uri->host($urlbase_host);
            DEBUG("redirecting to $new_uri because $hostname matches attachment regex");
            $c->redirect_to($new_uri);
            return;
        }
    }
    elsif ( my ($id) = $hostname =~ $urlbase_host_regex ) {
        my $new_uri = $urlbase_uri->clone;
        $new_uri->path('/show_bug.cgi');
        $new_uri->query_form( id => $id );
        DEBUG("redirecting to $new_uri because $hostname includes bug id");
        $c->redirect_to($new_uri);
        return;
    }
    else {
        DEBUG("redirecting to $urlbase because $hostname doesn't make sense");
        $c->redirect_to($urlbase);
        return;
    }
}

1;
