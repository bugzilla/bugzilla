package Menlo::Builder::Static;
use strict;
use warnings;

use CPAN::Meta;
use ExtUtils::Config 0.003;
use ExtUtils::Helpers 0.020 qw/make_executable split_like_shell man1_pagename man3_pagename detildefy/;
use ExtUtils::Install qw/pm_to_blib install/;
use ExtUtils::InstallPaths 0.002;
use File::Basename qw/dirname/;
use File::Find ();
use File::Path qw/mkpath/;
use File::Spec::Functions qw/catfile catdir rel2abs abs2rel splitdir curdir/;
use Getopt::Long 2.36 qw/GetOptionsFromArray/;

sub new {
    my($class, %args) = @_;
    bless {
        meta => $args{meta},
    }, $class;
}

sub meta {
    my $self = shift;
    $self->{meta};
}

sub manify {
	my ($input_file, $output_file, $section, $opts) = @_;
	return if -e $output_file && -M $input_file <= -M $output_file;
	my $dirname = dirname($output_file);
	mkpath($dirname, $opts->{verbose}) if not -d $dirname;
	require Pod::Man;
	Pod::Man->new(section => $section)->parse_from_file($input_file, $output_file);
	print "Manifying $output_file\n" if $opts->{verbose} && $opts->{verbose} > 0;
	return;
}

sub find {
	my ($pattern, $dir) = @_;
	my @ret;
	File::Find::find(sub { push @ret, $File::Find::name if /$pattern/ && -f }, $dir) if -d $dir;
	return @ret;
}

my %actions = (
	build => sub {
		my %opt = @_;
		my %modules = map { $_ => catfile('blib', $_) } find(qr/\.p(?:m|od)$/, 'lib');
		my %scripts = map { $_ => catfile('blib', $_) } find(qr//, 'script');
		my %shared  = map { $_ => catfile(qw/blib lib auto share dist/, $opt{meta}->name, abs2rel($_, 'share')) } find(qr//, 'share');
		pm_to_blib({ %modules, %scripts, %shared }, catdir(qw/blib lib auto/));
		make_executable($_) for values %scripts;
		mkpath(catdir(qw/blib arch/), $opt{verbose});

		if ($opt{install_paths}->install_destination('bindoc') && $opt{install_paths}->is_default_installable('bindoc')) {
			manify($_, catfile('blib', 'bindoc', man1_pagename($_)), $opt{config}->get('man1ext'), \%opt) for keys %scripts;
		}
		if ($opt{install_paths}->install_destination('libdoc') && $opt{install_paths}->is_default_installable('libdoc')) {
			manify($_, catfile('blib', 'libdoc', man3_pagename($_)), $opt{config}->get('man3ext'), \%opt) for keys %modules;
		}
                1;
	},
	test => sub {
		my %opt = @_;
		die "Must run `./Build build` first\n" if not -d 'blib';
		require TAP::Harness::Env;
		my %test_args = (
			(verbosity => $opt{verbose}) x!! exists $opt{verbose},
			(jobs => $opt{jobs}) x!! exists $opt{jobs},
			(color => 1) x !!-t STDOUT,
			lib => [ map { rel2abs(catdir(qw/blib/, $_)) } qw/arch lib/ ],
		);
		my $tester = TAP::Harness::Env->create(\%test_args);
		$tester->runtests(sort +find(qr/\.t$/, 't'))->has_errors and return;
                1;
	},
	install => sub {
		my %opt = @_;
		die "Must run `./Build build` first\n" if not -d 'blib';
		install($opt{install_paths}->install_map, @opt{qw/verbose dry_run uninst/});
                1;
	},
);

sub build {
	my $self = shift;
	my $action = @_ && $_[0] =~ /\A\w+\z/ ? shift @_ : 'build';
	die "No such action '$action'\n" if not $actions{$action};
	my %opt;
	GetOptionsFromArray([@$_], \%opt, qw/install_base=s install_path=s% installdirs=s destdir=s prefix=s config=s% uninst:1 verbose:1 dry_run:1 pureperl-only:1 create_packlist=i jobs=i/) for ($self->{env}, $self->{configure_args}, \@_);
	$_ = detildefy($_) for grep { defined } @opt{qw/install_base destdir prefix/}, values %{ $opt{install_path} };
	@opt{ 'config', 'meta' } = (ExtUtils::Config->new($opt{config}), $self->meta);
	$actions{$action}->(%opt, install_paths => ExtUtils::InstallPaths->new(%opt, dist_name => $opt{meta}->name));
}

sub configure {
	my $self = shift;   
	$self->{env} = defined $ENV{PERL_MB_OPT} ? [split_like_shell($ENV{PERL_MB_OPT})] : [];
        $self->{configure_args} = [@_];
	$self->meta->save(@$_) for ['MYMETA.json'], [ 'MYMETA.yml' => { version => 1.4 } ];
}

1;

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Leon Timmermans, David Golden.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
