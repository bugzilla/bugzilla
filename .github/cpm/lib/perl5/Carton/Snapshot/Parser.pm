package Carton::Snapshot::Parser;
use Class::Tiny;
use warnings NONFATAL => 'all';
use Carton::Dist;
use Carton::Error;

my $machine = {
    init => [
        {
            re => qr/^\# carton snapshot format: version (1\.0)/,
            code => sub {
                my($stash, $snapshot, $ver) = @_;
                $snapshot->version($ver);
            },
            goto => 'section',
        },
        # TODO support pasing error and version mismatch etc.
    ],
    section => [
        {
            re => qr/^DISTRIBUTIONS$/,
            goto => 'dists',
        },
        {
            re => qr/^__EOF__$/,
            done => 1,
        },
    ],
    dists => [
        {
            re => qr/^  (\S+)$/,
            code => sub { $_[0]->{dist} = Carton::Dist->new(name => $1) },
            goto => 'distmeta',
        },
        {
            re => qr/^\S/,
            goto => 'section',
            redo => 1,
        },
    ],
    distmeta => [
        {
            re => qr/^    pathname: (.*)$/,
            code => sub { $_[0]->{dist}->pathname($1) },
        },
        {
            re => qr/^\s{4}provides:$/,
            code => sub { $_[0]->{property} = 'provides' },
            goto => 'properties',
        },
        {
            re => qr/^\s{4}requirements:$/,
            code => sub {
                $_[0]->{property} = 'requirements';
            },
            goto => 'properties',
        },
        {
            re => qr/^\s{0,2}\S/,
            code => sub {
                my($stash, $snapshot) = @_;
                $snapshot->add_distribution($stash->{dist});
                %$stash = (); # clear
            },
            goto => 'dists',
            redo => 1,
        },
    ],
    properties => [
        {
            re => qr/^\s{6}([0-9A-Za-z_:]+) ([v0-9\._,=\!<>\s]+|undef)/,
            code => sub {
                my($stash, $snapshot, $module, $version) = @_;
                if ($stash->{property} eq 'provides') {
                    $stash->{dist}->provides->{$module} = { version => $version };
                } else {
                    $stash->{dist}->add_string_requirement($module, $version);
                }
            },
        },
        {
            re => qr/^\s{0,4}\S/,
            goto => 'distmeta',
            redo => 1,
        },
    ],
};

sub parse {
    my($self, $data, $snapshot) = @_;

    my @lines = split /\r?\n/, $data;

    my $state = $machine->{init};
    my $stash = {};

    LINE:
    for my $line (@lines, '__EOF__') {
        last LINE unless @$state;

    STATE: {
            for my $trans (@{$state}) {
                if (my @match = $line =~ $trans->{re}) {
                    if (my $code = $trans->{code}) {
                        $code->($stash, $snapshot, @match);
                    }
                    if (my $goto = $trans->{goto}) {
                        $state = $machine->{$goto};
                        if ($trans->{redo}) {
                            redo STATE;
                        } else {
                            next LINE;
                        }
                    }

                    last STATE;
                }
            }

            Carton::Error::SnapshotParseError->throw(error => "Could not parse snapshot file: $line");
        }
    }
}

1;
