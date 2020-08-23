package HTTP::Tinyish::Wget;
use strict;
use warnings;
use parent qw(HTTP::Tinyish::Base);

use IPC::Run3 qw(run3);
use File::Which qw(which);

my %supports;
my $wget;
my $method_supported;

sub _run_wget {
    run3([$wget, @_], \undef, \my $out, \my $err);
    wantarray ? ($out, $err) : $out;
}

sub configure {
    my $class = shift;
    my %meta;

    $wget = which('wget');

    eval {
        local $ENV{LC_ALL} = 'en_US';

        $meta{$wget} = _run_wget('--version');
        unless ($meta{$wget} =~ /GNU Wget 1\.(\d+)/ and $1 >= 12) {
            die "Wget version is too old. $meta{$wget}";
        }

        my $config = $class->new(agent => __PACKAGE__);
        my @options = grep { $_ ne '--quiet' } $config->build_options("GET");

        my(undef, $err) = _run_wget(@options, 'https://');
        if ($err && $err =~ /HTTPS support not compiled/) {
            $supports{http} = 1;
        } elsif ($err && $err =~ /Invalid host/) {
            $supports{http} = $supports{https} = 1;
        }

        (undef, $err) = _run_wget('--method', 'GET', 'http://');
        if ($err && $err =~ /Invalid host/) {
            $method_supported = $meta{method_supported} = 1;
        }

    };

    \%meta;
}

sub supports { $supports{$_[1]} }

sub new {
    my($class, %attr) = @_;
    bless \%attr, $class;
}

sub request {
    my($self, $method, $url, $opts) = @_;
    $opts ||= {};

    my($stdout, $stderr);
    eval {
        run3 [
            $wget,
            $self->build_options($method, $url, $opts),
            $url,
            '-O', '-',
        ], \undef, \$stdout, \$stderr;
    };

    # wget exit codes: (man wget)
    # 4   Network failure.
    # 5   SSL verification failure.
    # 6   Username/password authentication failure.
    # 7   Protocol errors.
    # 8   Server issued an error response.
    if ($@ or $? && ($? >> 8) <= 5) {
        return $self->internal_error($url, $@ || $stderr);
    }

    my $header = '';
    $stderr =~ s{^  (\S.*)$}{ $header .= $1."\n" }gem;

    my $res = { url => $url, content => $stdout };
    $self->parse_http_header($header, $res);
    $res;
}

sub mirror {
    my($self, $url, $file, $opts) = @_;
    $opts ||= {};

    # This doesn't send If-Modified-Since because -O and -N are mutually exclusive :(
    my($stdout, $stderr);
    eval {
        run3 [$wget, $self->build_options("GET", $url, $opts), $url, '-O', $file], \undef, \$stdout, \$stderr;
    };

    if ($@ or $?) {
        return $self->internal_error($url, $@ || $stderr);
    }

    $stderr =~ s/^  //gm;

    my $res = { url => $url, content => $stdout };
    $self->parse_http_header($stderr, $res);
    $res;
}

sub build_options {
    my($self, $method, $url, $opts) = @_;

    my @options = (
        '--retry-connrefused',
        '--server-response',
        '--timeout', ($self->{timeout} || 60),
        '--tries', 1,
        '--max-redirect', ($self->{max_redirect} || 5),
        '--user-agent', ($self->{agent} || "HTTP-Tinyish/$HTTP::Tinyish::VERSION"),
    );

    if ($method_supported) {
        push @options, "--method", $method;
    } else {
        if ($method eq 'GET' or $method eq 'POST') {
            # OK
        } elsif ($method eq 'HEAD') {
            push @options, '--spider';
        } else {
            die "This version of wget doesn't support specifying HTTP method '$method'";
        }
    }

    if ($self->{agent}) {
        push @options, '--user-agent', $self->{agent};
    }

    my %headers;
    if ($self->{default_headers}) {
        %headers = %{$self->{default_headers}};
    }
    if ($opts->{headers}) {
        %headers = (%headers, %{$opts->{headers}});
    }
    $self->_translate_headers(\%headers, \@options);

    if ($supports{https} && !$self->{verify_SSL}) {
        push @options, '--no-check-certificate';
    }

    if ($opts->{content}) {
        my $content;
        if (ref $opts->{content} eq 'CODE') {
            while (my $chunk = $opts->{content}->()) {
                $content .= $chunk;
            }
        } else {
            $content = $opts->{content};
        }

        if ($method_supported) {
            push @options, '--body-data', $content;
        } else {
            push @options, '--post-data', $content;
        }
    }

    @options;
}

sub _translate_headers {
    my($self, $headers, $options) = @_;

    for my $field (keys %$headers) {
        my $value = $headers->{$field};
        if (ref $value eq 'ARRAY') {
            # wget doesn't honor multiple header fields
            push @$options, '--header', "$field:" . join(",", @$value);
        } else {
            push @$options, '--header', "$field:$value";
        }
    }
}

1;
