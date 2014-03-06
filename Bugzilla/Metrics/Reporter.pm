# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Metrics::Reporter;

use strict;
use warnings;

use Bugzilla::Constants;
use File::Slurp;
use File::Temp;
use JSON;

# most reporters should detach from the httpd process.
# reporters which do not detach will block completion of the http response.
use constant DETACH => 1;

# class method to start the delivery script in the background
sub background {
    my ($class, $collector) = @_;

    # we need to remove parent links to avoid looped structures, which
    # encode_json chokes on
    _walk_timers($collector->{root}, sub { delete $_[0]->{parent} });

    # serialisation
    my $json = encode_json({ env => $collector->{env}, times => $collector->{root} });

    # write to temp filename
    my $fh = File::Temp->new( UNLINK => 0 );
    if (!$fh) {
        warn "Failed to create temp file: $!\n";
        return;
    }
    binmode($fh, ':utf8');
    print $fh $json;
    close($fh) or die "$fh : $!";
    my $filename = $fh->filename;

    # spawn delivery worker
    my $command = bz_locations()->{'cgi_path'} . "/metrics.pl '$class' '$filename' &";
    $ENV{PATH} = '';
    system($command);
}

# run the reporter immediately
sub foreground {
    my ($class, $collector) = @_;
    my $reporter = $class->new({ hashref => { env => $collector->{env}, times => $collector->{root} } });
    $reporter->report();
}

sub new {
    my ($invocant, $args) = @_;
    my $class = ref($invocant) || $invocant;

    # load from either a json_filename or hashref
    my $self;
    if ($args->{json_filename}) {
        $self = decode_json(read_file($args->{json_filename}, binmode => ':utf8'));
        unlink($args->{json_filename});
    }
    else {
        $self = $args->{hashref};
    }
    bless($self, $class);

    # remove redundant data
    $self->walk_timers(sub {
        my ($timer) = @_;
        $timer->{start_time} = delete $timer->{first_time};
        delete $timer->{children}
            if exists $timer->{children} && !scalar(@{ $timer->{children} });
    });

    return $self;
}

sub walk_timers {
    my ($self, $callback) = @_;
    _walk_timers($self->{times}, $callback, undef);
}

sub _walk_timers {
    my ($timer, $callback, $parent) = @_;
    $callback->($timer, $parent);
    if (exists $timer->{children}) {
        foreach my $child (@{ $timer->{children} }) {
            _walk_timers($child, $callback, $timer);
        }
    }
}

sub report {
    die "abstract method call";
}

1;
