package Carton::Snapshot::Emitter;
use Class::Tiny;
use warnings NONFATAL => 'all';

sub emit {
    my($self, $snapshot) = @_;

    my $data = '';
    $data .= "# carton snapshot format: version @{[$snapshot->version]}\n";
    $data .= "DISTRIBUTIONS\n";

    for my $dist (sort { $a->name cmp $b->name } $snapshot->distributions) {
        $data .= "  @{[$dist->name]}\n";
        $data .= "    pathname: @{[$dist->pathname]}\n";

        $data .= "    provides:\n";
        for my $package (sort keys %{$dist->provides}) {
            my $version = $dist->provides->{$package}{version};
            $version = 'undef' unless defined $version;
            $data .= "      $package $version\n";
        }

        $data .= "    requirements:\n";
        for my $module (sort $dist->required_modules) {
            $data .= "      $module @{[ $dist->requirements_for_module($module) || '0' ]}\n";
        }
    }

    $data;
}

1;
