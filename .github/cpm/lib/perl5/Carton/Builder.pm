package Carton::Builder;
use strict;
use Class::Tiny {
    mirror => undef,
    index  => undef,
    cascade => sub { 1 },
    without => sub { [] },
    cpanfile => undef,
};

sub effective_mirrors {
    my $self = shift;

    # push default CPAN mirror always, as a fallback
    # TODO don't pass fallback if --cached is set?

    my @mirrors = ($self->mirror);
    push @mirrors, Carton::Mirror->default if $self->custom_mirror;
    push @mirrors, Carton::Mirror->new('http://backpan.perl.org/');

    @mirrors;
}

sub custom_mirror {
    my $self = shift;
    ! $self->mirror->is_default;
}

sub bundle {
    my($self, $path, $cache_path, $snapshot) = @_;

    for my $dist ($snapshot->distributions) {
        my $source = $path->child("cache/authors/id/" . $dist->pathname);
        my $target = $cache_path->child("authors/id/" . $dist->pathname);

        if ($source->exists) {
            warn "Copying ", $dist->pathname, "\n";
            $target->parent->mkpath;
            $source->copy($target) or warn "$target: $!";
        } else {
            warn "Couldn't find @{[ $dist->pathname ]}\n";
        }
    }

    my $has_io_gzip = eval { require IO::Compress::Gzip; 1 };

    my $ext   = $has_io_gzip ? ".txt.gz" : ".txt";
    my $index = $cache_path->child("modules/02packages.details$ext");
    $index->parent->mkpath;

    warn "Writing $index\n";

    my $out = $index->openw;
    if ($has_io_gzip) {
        $out = IO::Compress::Gzip->new($out)
          or die "gzip failed: $IO::Compress::Gzip::GzipError";
    }

    $snapshot->index->write($out);
    close $out;

    unless ($has_io_gzip) {
        unlink "$index.gz";
        !system 'gzip', $index
          or die "Running gzip command failed: $!";
    }
}

sub install {
    my($self, $path) = @_;

    $self->run_install(
        "-L", $path,
        (map { ("--mirror", $_->url) } $self->effective_mirrors),
        ( $self->index ? ("--mirror-index", $self->index) : () ),
        ( $self->cascade ? "--cascade-search" : () ),
        ( $self->custom_mirror ? "--mirror-only" : () ),
        "--save-dists", "$path/cache",
        $self->groups,
        "--cpanfile", $self->cpanfile,
        "--installdeps", $self->cpanfile->dirname,
    ) or die "Installing modules failed\n";
}

sub groups {
    my $self = shift;

    # TODO support --without test (don't need test on deployment)
    my @options = ('--with-all-features', '--with-develop');

    for my $group (@{$self->without}) {
        push @options, '--without-develop' if $group eq 'develop';
        push @options, "--without-feature=$group";
    }

    return @options;
}

sub update {
    my($self, $path, @modules) = @_;

    $self->run_install(
        "-L", $path,
        (map { ("--mirror", $_->url) } $self->effective_mirrors),
        ( $self->custom_mirror ? "--mirror-only" : () ),
        "--save-dists", "$path/cache",
        @modules
    ) or die "Updating modules failed\n";
}

sub run_install {
    my($self, @args) = @_;

    require Menlo::CLI::Compat;
    local $ENV{PERL_CPANM_OPT};

    my $cli = Menlo::CLI::Compat->new;
    $cli->parse_options("--quiet", "--notest", @args);
    $cli->run;

    !$cli->status;
}

1;
