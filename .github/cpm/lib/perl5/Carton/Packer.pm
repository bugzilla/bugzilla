package Carton::Packer;
use Class::Tiny;
use warnings NONFATAL => 'all';
use App::FatPacker;
use File::pushd ();
use Path::Tiny ();
use CPAN::Meta ();
use File::Find ();

sub fatpack_carton {
    my($self, $dir) = @_;

    my $temp = Path::Tiny->tempdir;
    my $pushd = File::pushd::pushd $temp;

    my $file = $temp->child('carton.pre.pl');

    $file->spew(<<'EOF');
#!/usr/bin/env perl
use strict;
use 5.008001;
use Carton::CLI;
$Carton::Fatpacked = 1;
exit Carton::CLI->new->run(@ARGV);
EOF

    my $fatpacked = $self->do_fatpack($file);

    my $executable = $dir->child('carton');
    warn "Bundling $executable\n";

    $dir->mkpath;
    $executable->spew($fatpacked);
    chmod 0755, $executable;
}

sub do_fatpack {
    my($self, $file) = @_;

    my $packer = App::FatPacker->new;

    my @modules = split /\r?\n/, $packer->trace(args => [$file], use => $self->required_modules);
    my @packlists = $packer->packlists_containing(\@modules);
    $packer->packlists_to_tree(Path::Tiny->new('fatlib')->absolute, \@packlists);

    my $fatpacked = do {
        local $SIG{__WARN__} = sub {};
        $packer->fatpack_file($file);
    };

    # HACK: File::Spec bundled into arch in < 5.16, but is loadable as pure-perl
    use Config;
    $fatpacked =~ s/\$fatpacked\{"$Config{archname}\/(Cwd|File)/\$fatpacked{"$1/g;

    $fatpacked;
}

sub required_modules {
    my $self = shift;

    my %requirements;
    for my $dist (qw( Carton Menlo-Legacy Menlo )) {
        $requirements{$_} = 1 for $self->required_modules_for($dist);
    }

    # these modules are needed, but lazy-loaded, so FatPacker wont bundle them by default.
    my @extra = qw(Menlo::Index::Mirror);

    [ keys %requirements, @extra ];
}

sub required_modules_for {
    my($self, $dist) = @_;

    my $meta = $self->installed_meta($dist)
        or die "Couldn't find install metadata for $dist";

    my %excludes = (
        perl => 1,
        'ExtUtils::MakeMaker' => 1,
        'Module::Build' => 1,
    );

    grep !$excludes{$_},
        $meta->effective_prereqs->requirements_for('runtime', 'requires')->required_modules;
}

sub installed_meta {
    my($self, $dist) = @_;

    my @meta;
    my $finder = sub {
        if (m!\b$dist-.*[\\/]MYMETA.json!) {
            my $meta = CPAN::Meta->load_file($_);
            push @meta, $meta if $meta->name eq $dist;
        }
    };

    my @meta_dirs = grep -d, map "$_/.meta", @INC;
    File::Find::find({ wanted => $finder, no_chdir => 1 }, @meta_dirs)
        if @meta_dirs;

    # return the latest version
    @meta = sort { version->new($b->version) cmp version->new($a->version) } @meta;

    return $meta[0];
}

1;
