# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Log::Log4perl::Layout::Mozilla;
use 5.10.1;
use Moo;
use Sys::Hostname;
use JSON::MaybeXS ();
use English qw(-no_match_vars $PID);

use constant LOGGING_FORMAT_VERSION => 2.0;

extends 'Log::Log4perl::Layout';

has 'name' => (
    is      => 'ro',
    default => 'Bugzilla',
);

has 'max_json_length' => (
    is      => 'ro',
    isa     => sub { die "must be at least 1024\n" if $_[0] < 1024 },
    default => 4096,
);

sub BUILDARGS {
    my ($class, $params) = @_;

    delete $params->{value};
    foreach my $key (keys %$params) {
        if (ref $params->{$key} eq 'HASH') {
            $params->{$key} = $params->{$key}{value};
        }
    }
    return $params;
}

sub render {
    my ( $self, $msg, $category, $priority, $caller_level ) = @_;

    state $HOSTNAME = hostname();
    state $JSON     = JSON::MaybeXS->new(
        indent          => 0,    # to prevent newlines (and save space)
        ascii           => 1,    # to avoid encoding issues downstream
        allow_unknown   => 1,    # encode null on bad value (instead of exception)
        convert_blessed => 1,    # call TO_JSON on blessed ref, if it exists
        allow_blessed   => 1,    # encode null on blessed ref that can't be converted
    );

    my $mdc = Log::Log4perl::MDC->get_context;
    my $fields = $mdc->{fields} // {};
    my %out = (
        EnvVersion => LOGGING_FORMAT_VERSION,
        Hostname   => $HOSTNAME,
        Logger     => $self->name,
        Pid        => $PID,
        Severity   => $Log::Log4perl::Level::SYSLOG{$priority},
        Timestamp  => time() * 1e9,
        Type       => $category,
        Fields     => { msg => $msg, %$fields },
    );

    my $json_text = $JSON->encode(\%out) . "\n";
    if (length($json_text) > $self->max_json_length) {
        my $scary_msg = sprintf 'DANGER! LOG MESSAGE TOO BIG %d > %d', length($json_text), $self->max_json_length;
        $out{Fields}   = { remote_ip => $mdc->{remote_ip}, msg => $scary_msg };
        $out{Severity} = 1; # alert
        $json_text     = $JSON->encode(\%out) . "\n";
    }

    return $json_text;
}

1;

__END__

=head1 NAME

Log::Log4perl::Layout::Mozilla - Implement the mozilla-services json log format

=head1 SYNOPSIS

Example configuration:

    log4perl.appender.Example.layout = Log::Log4perl::Layout::Mozilla
    log4perl.appender.Example.layout.max_json_length = 16384
    log4perl.appender.Example.layout.name = Bugzilla

=head1 DESCRIPTION

This class implements a C<Log::Log4perl> layout format
that implements the recommend json format using in Mozilla services.
L<https://wiki.mozilla.org/Firefox/Services/Logging#MozLog_JSON_schema>.

The JSON hash is ASCII encoded, with no newlines or other whitespace, and is
suitable for output, via Log::Log4perl appenders, to files and syslog etc.

Contextual data in the L<Log::Log4perl::MDC> hash will be put into the Fields
hash.

=head1 LAYOUT CONFIGURATION

=head2 name

Data source, server that is doing the logging, e.g. "Sync-1_5".

Use the server's name, and avoid implementation details. "FxaAuthWebserver", not "NginxLogs".

=head2 max_json_length

Set the maximum JSON length in bytes. The default is 4096,
and it cannot be smaller than 1024.

    log4perl.appender.Example.layout.max_json_length = 16384

This is useful where some downstream system has a limit on the maximum size of
a message.

If the message is larger than this limit, the message will be replaced
with a scary message at a severity level of ALERT.