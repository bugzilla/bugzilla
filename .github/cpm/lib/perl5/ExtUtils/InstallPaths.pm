package ExtUtils::InstallPaths;
$ExtUtils::InstallPaths::VERSION = '0.012';
use 5.006;
use strict;
use warnings;

use File::Spec ();
use Carp ();
use ExtUtils::Config 0.002;

my %complex_accessors = map { $_ => 1 } qw/prefix_relpaths install_sets/;
my %hash_accessors = map { $_ => 1 } qw/install_path install_base_relpaths original_prefix /;

my %defaults = (
	installdirs     => 'site',
	install_base    => undef,
	prefix          => undef,
	verbose         => 0,
	create_packlist => 1,
	dist_name       => undef,
	module_name     => undef,
	destdir         => undef,
	install_path    => sub { {} },
	install_sets    => \&_default_install_sets,
	original_prefix => \&_default_original_prefix,
	install_base_relpaths => \&_default_base_relpaths,
	prefix_relpaths => \&_default_prefix_relpaths,
);

sub _merge_shallow {
	my ($name, $filter) = @_;
	return sub {
		my ($override, $config) = @_;
		my $defaults = $defaults{$name}->($config);
		$filter->($_) for grep $filter, values %$override;
		return { %$defaults, %$override };
	}
}

sub _merge_deep {
	my ($name, $filter) = @_;
	return sub {
		my ($override, $config) = @_;
		my $defaults = $defaults{$name}->($config);
		my $pair_for = sub {
			my $key = shift;
			my %override = %{ $override->{$key} || {} };
			$filter && $filter->($_) for values %override;
			return $key => { %{ $defaults->{$key} }, %override };
		};
		return { map { $pair_for->($_) } keys %$defaults };
	}
}

my %allowed_installdir = map { $_ => 1 } qw/core site vendor/;
my $must_be_relative = sub { Carp::croak('Value must be a relative path') if File::Spec->file_name_is_absolute($_[0]) };
my %deep_filter = map { $_ => $must_be_relative } qw/install_base_relpaths prefix_relpaths/;
my %filter = (
	installdirs => sub {
		my $value = shift;
		$value = 'core', Carp::carp('Perhaps you meant installdirs to be "core" rather than "perl"?') if $value eq 'perl';
		Carp::croak('installdirs must be one of "core", "site", or "vendor"') if not $allowed_installdir{$value};
		return $value;
	},
	(map { $_ => _merge_shallow($_, $deep_filter{$_}) } qw/original_prefix install_base_relpaths/),
	(map { $_ => _merge_deep($_, $deep_filter{$_}) } qw/install_sets prefix_relpaths/),
);

sub new {
	my ($class, %args) = @_;
	my $config = $args{config} || ExtUtils::Config->new;
	my %self = (
		config => $config,
		map { $_ => exists $args{$_} ? $filter{$_} ? $filter{$_}->($args{$_}, $config) : $args{$_} : ref $defaults{$_} ? $defaults{$_}->($config) : $defaults{$_} } keys %defaults,
	);
	$self{module_name} ||= do { my $module_name = $self{dist_name}; $module_name =~ s/-/::/g; $module_name } if defined $self{dist_name};
	return bless \%self, $class;
}

for my $attribute (keys %defaults) {
	no strict qw/refs/;
	*{$attribute} = $hash_accessors{$attribute} ? 
	sub {
		my ($self, $key) = @_;
		Carp::confess("$attribute needs key") if not defined $key;
		return $self->{$attribute}{$key};
	} :
	$complex_accessors{$attribute} ?
	sub {
		my ($self, $installdirs, $key) = @_;
		Carp::confess("$attribute needs installdir") if not defined $installdirs;
		Carp::confess("$attribute needs key") if not defined $key;
		return $self->{$attribute}{$installdirs}{$key};
	} :
	sub {
		my $self = shift;
		return $self->{$attribute};
	};
}

my $script = $] > 5.008000 ? 'script' : 'bin';
my @install_sets_keys = qw/lib arch bin script bindoc libdoc binhtml libhtml/;
my @install_sets_tail = ('bin', $script, qw/man1dir man3dir html1dir html3dir/);
my %install_sets_values = (
	core   => [ qw/privlib archlib /, @install_sets_tail ],
	site   => [ map { "site$_" } qw/lib arch/, @install_sets_tail ],
	vendor => [ map { "vendor$_" } qw/lib arch/, @install_sets_tail ],
);

sub _default_install_sets {
	my $c = shift;

	my %ret;
	for my $installdir (qw/core site vendor/) {
		@{$ret{$installdir}}{@install_sets_keys} = map { $c->get("install$_") } @{ $install_sets_values{$installdir} };
	}
	return \%ret;
}

sub _default_base_relpaths {
	my $config = shift;
	return {
		lib     => ['lib', 'perl5'],
		arch    => ['lib', 'perl5', $config->get('archname')],
		bin     => ['bin'],
		script  => ['bin'],
		bindoc  => ['man', 'man1'],
		libdoc  => ['man', 'man3'],
		binhtml => ['html'],
		libhtml => ['html'],
	};
}

my %common_prefix_relpaths = (
	bin        => ['bin'],
	script     => ['bin'],
	bindoc     => ['man', 'man1'],
	libdoc     => ['man', 'man3'],
	binhtml    => ['html'],
	libhtml    => ['html'],
);

sub _default_prefix_relpaths {
	my $c = shift;

	my @libstyle = $c->get('installstyle') ?  File::Spec->splitdir($c->get('installstyle')) : qw(lib perl5);
	my $arch     = $c->get('archname');
	my $version  = $c->get('version');

	return {
		core => {
			lib        => [@libstyle],
			arch       => [@libstyle, $version, $arch],
			%common_prefix_relpaths,
		},
		vendor => {
			lib        => [@libstyle],
			arch       => [@libstyle, $version, $arch],
			%common_prefix_relpaths,
		},
		site => {
			lib        => [@libstyle, 'site_perl'],
			arch       => [@libstyle, 'site_perl', $version, $arch],
			%common_prefix_relpaths,
		},
	};
}

sub _default_original_prefix {
	my $c = shift;

	my %ret = (
		core   => $c->get('installprefixexp'),
		site   => $c->get('siteprefixexp'),
		vendor => $c->get('usevendorprefix') ? $c->get('vendorprefixexp') : '',
	);

	return \%ret;
}

sub _log_verbose {
	my $self = shift;
	print @_ if $self->verbose;
	return;
}

# Given a file type, will return true if the file type would normally
# be installed when neither install-base nor prefix has been set.
# I.e. it will be true only if the path is set from Config.pm or
# set explicitly by the user via install-path.
sub is_default_installable {
	my $self = shift;
	my $type = shift;
	my $installable = $self->install_destination($type) && ( $self->install_path($type) || $self->install_sets($self->installdirs, $type));
	return $installable ? 1 : 0;
}

sub _prefixify_default {
	my $self = shift;
	my $type = shift;
	my $rprefix = shift;

	my $default = $self->prefix_relpaths($self->installdirs, $type);
	if( !$default ) {
		$self->_log_verbose("    no default install location for type '$type', using prefix '$rprefix'.\n");
		return $rprefix;
	} else {
		return File::Spec->catdir(@{$default});
	}
}

# Translated from ExtUtils::MM_Unix::prefixify()
sub _prefixify_novms {
	my($self, $path, $sprefix, $type) = @_;

	my $rprefix = $self->prefix;
	$rprefix .= '/' if $sprefix =~ m{/$};

	$self->_log_verbose("  prefixify $path from $sprefix to $rprefix\n") if defined $path && length $path;

	if (not defined $path or length $path == 0 ) {
		$self->_log_verbose("  no path to prefixify, falling back to default.\n");
		return $self->_prefixify_default( $type, $rprefix );
	} elsif( !File::Spec->file_name_is_absolute($path) ) {
		$self->_log_verbose("    path is relative, not prefixifying.\n");
	} elsif( $path !~ s{^\Q$sprefix\E\b}{}s ) {
		$self->_log_verbose("    cannot prefixify, falling back to default.\n");
		return $self->_prefixify_default( $type, $rprefix );
	}

	$self->_log_verbose("    now $path in $rprefix\n");

	return $path;
}

sub _catprefix_vms {
	my ($self, $rprefix, $default) = @_;

	my ($rvol, $rdirs) = File::Spec->splitpath($rprefix);
	if ($rvol) {
		return File::Spec->catpath($rvol, File::Spec->catdir($rdirs, $default), '');
	}
	else {
		return File::Spec->catdir($rdirs, $default);
	}
}
sub _prefixify_vms {
	my($self, $path, $sprefix, $type) = @_;
	my $rprefix = $self->prefix;

	return '' unless defined $path;

	$self->_log_verbose("  prefixify $path from $sprefix to $rprefix\n");

	require VMS::Filespec;
	# Translate $(PERLPREFIX) to a real path.
	$rprefix = VMS::Filespec::vmspath($rprefix) if $rprefix;
	$sprefix = VMS::Filespec::vmspath($sprefix) if $sprefix;

	$self->_log_verbose("  rprefix translated to $rprefix\n  sprefix translated to $sprefix\n");

	if (length($path) == 0 ) {
		$self->_log_verbose("  no path to prefixify.\n")
	}
	elsif (!File::Spec->file_name_is_absolute($path)) {
		$self->_log_verbose("	path is relative, not prefixifying.\n");
	}
	elsif ($sprefix eq $rprefix) {
		$self->_log_verbose("  no new prefix.\n");
	}
	else {
		my ($path_vol, $path_dirs) = File::Spec->splitpath( $path );
		my $vms_prefix = $self->config->get('vms_prefix');
		if ($path_vol eq $vms_prefix.':') {
			$self->_log_verbose("  $vms_prefix: seen\n");

			$path_dirs =~ s{^\[}{\[.} unless $path_dirs =~ m{^\[\.};
			$path = $self->_catprefix_vms($rprefix, $path_dirs);
		}
		else {
			$self->_log_verbose("	cannot prefixify.\n");
			return File::Spec->catdir($self->prefix_relpaths($self->installdirs, $type));
		}
	}

	$self->_log_verbose("	now $path\n");

	return $path;
}

BEGIN { *_prefixify = $^O eq 'VMS' ? \&_prefixify_vms : \&_prefixify_novms }

# Translated from ExtUtils::MM_Any::init_INSTALL_from_PREFIX
sub prefix_relative {
	my ($self, $installdirs, $type) = @_;

	my $relpath = $self->install_sets($installdirs, $type);

	return $self->_prefixify($relpath, $self->original_prefix($installdirs), $type);
}

sub install_destination {
	my ($self, $type) = @_;

	return $self->install_path($type) if $self->install_path($type);

	if ( $self->install_base ) {
		my $relpath = $self->install_base_relpaths($type);
		return $relpath ? File::Spec->catdir($self->install_base, @{$relpath}) : undef;
	}

	if ( $self->prefix ) {
		my $relpath = $self->prefix_relative($self->installdirs, $type);
		return $relpath ? File::Spec->catdir($self->prefix, $relpath) : undef;
	}
	return $self->install_sets($self->installdirs, $type);
}

sub install_types {
	my $self = shift;

	my %types = ( %{ $self->{install_path} }, 
		  $self->install_base ?  %{ $self->{install_base_relpaths} }
		: $self->prefix ? %{ $self->{prefix_relpaths}{ $self->installdirs } }
		: %{ $self->{install_sets}{ $self->installdirs } });

	return sort keys %types;
}

sub install_map {
	my ($self, $dirs) = @_;

	my %localdir_for;
	if ($dirs && %$dirs) {
		%localdir_for = %$dirs;
	}
	else {
		foreach my $type ($self->install_types) {
			$localdir_for{$type} = File::Spec->catdir('blib', $type);
		}
	}

	my (%map, @skipping);
	foreach my $type (keys %localdir_for) {
		next if not -e $localdir_for{$type};
		if (my $dest = $self->install_destination($type)) {
			$map{$localdir_for{$type}} = $dest;
		} else {
			push @skipping, $type;
		}
	}

	warn "WARNING: Can't figure out install path for types: @skipping\nFiles will not be installed.\n" if @skipping;

	# Write the packlist into the same place as ExtUtils::MakeMaker.
	if ($self->create_packlist and my $module_name = $self->module_name) {
		my $archdir = $self->install_destination('arch');
		my @ext = split /::/, $module_name;
		$map{write} = File::Spec->catfile($archdir, 'auto', @ext, '.packlist');
	}

	# Handle destdir
	if (length(my $destdir = $self->destdir || '')) {
		foreach (keys %map) {
			# Need to remove volume from $map{$_} using splitpath, or else
			# we'll create something crazy like C:\Foo\Bar\E:\Baz\Quux
			# VMS will always have the file separate than the path.
			my ($volume, $path, $file) = File::Spec->splitpath( $map{$_}, 0 );

			# catdir needs a list of directories, or it will create something
			# crazy like volume:[Foo.Bar.volume.Baz.Quux]
			my @dirs = File::Spec->splitdir($path);

			# First merge the directories
			$path = File::Spec->catdir($destdir, @dirs);

			# Then put the file back on if there is one.
			if ($file ne '') {
			    $map{$_} = File::Spec->catfile($path, $file)
			} else {
			    $map{$_} = $path;
			}
		}
	}

	$map{read} = '';  # To keep ExtUtils::Install quiet

	return \%map;
}

1;

# ABSTRACT: Build.PL install path logic made easy

__END__

=pod

=encoding UTF-8

=head1 NAME

ExtUtils::InstallPaths - Build.PL install path logic made easy

=head1 VERSION

version 0.012

=head1 SYNOPSIS

 use ExtUtils::InstallPaths;
 use ExtUtils::Install 'install';
 GetOptions(\my %opt, 'install_base=s', 'install_path=s%', 'installdirs=s', 'destdir=s', 'prefix=s', 'uninst:1', 'verbose:1');
 my $paths = ExtUtils::InstallPaths->new(%opt, dist_name => $dist_name);
 install($paths->install_map, $opt{verbose}, 0, $opt{uninst});

=head1 DESCRIPTION

This module tries to make install path resolution as easy as possible.

When you want to install a module, it needs to figure out where to install things. The nutshell version of how this works is that default installation locations are determined from L<ExtUtils::Config>, and they may be individually overridden by using the C<install_path> attribute. An C<install_base> attribute lets you specify an alternative installation root like F</home/foo> and C<prefix> does something similar in a rather different (and more complicated) way. C<destdir> lets you specify a temporary installation directory like F</tmp/install> in case you want to create bundled-up installable packages.

The following types are supported by default.

=over 4

=item * lib

Usually pure-Perl module files ending in F<.pm> or F<.pod>.

=item * arch

"Architecture-dependent" module files, usually produced by compiling XS, L<Inline>, or similar code.

=item * script

Programs written in pure Perl.  In order to improve reuse, you may want to make these as small as possible - put the code into modules whenever possible.

=item * bin

"Architecture-dependent" executable programs, i.e. compiled C code or something.  Pretty rare to see this in a perl distribution, but it happens.

=item * bindoc

Documentation for the stuff in C<script> and C<bin>.  Usually generated from the POD in those files.  Under Unix, these are manual pages belonging to the 'man1' category. Unless explicitly set, this is only available on platforms supporting manpages.

=item * libdoc

Documentation for the stuff in C<lib> and C<arch>.  This is usually generated from the POD in F<.pm> and F<.pod> files.  Under Unix, these are manual pages belonging to the 'man3' category. Unless explicitly set, this is only available on platforms supporting manpages.

=item * binhtml

This is the same as C<bindoc> above, but applies to HTML documents. Unless explicitly set, this is only available when perl was configured to do so.

=item * libhtml

This is the same as C<libdoc> above, but applies to HTML documents. Unless explicitly set, this is only available when perl was configured to do so.

=back

=head1 ATTRIBUTES

=head2 installdirs

The default destinations for these installable things come from entries in your system's configuration. You can select from three different sets of default locations by setting the C<installdirs> parameter as follows:

                          'installdirs' set to:
                   core          site                vendor

              uses the following defaults from ExtUtils::Config:

  lib     => installprivlib  installsitelib      installvendorlib
  arch    => installarchlib  installsitearch     installvendorarch
  script  => installscript   installsitescript   installvendorscript
  bin     => installbin      installsitebin      installvendorbin
  bindoc  => installman1dir  installsiteman1dir  installvendorman1dir
  libdoc  => installman3dir  installsiteman3dir  installvendorman3dir
  binhtml => installhtml1dir installsitehtml1dir installvendorhtml1dir [*]
  libhtml => installhtml3dir installsitehtml3dir installvendorhtml3dir [*]

  * Under some OS (eg. MSWin32) the destination for HTML documents is determined by the C<Config.pm> entry C<installhtmldir>.

The default value of C<installdirs> is "site".

=head2 install_base

You can also set the whole bunch of installation paths by supplying the C<install_base> parameter to point to a directory on your system.  For instance, if you set C<install_base> to "/home/ken" on a Linux system, you'll install as follows:

  lib     => /home/ken/lib/perl5
  arch    => /home/ken/lib/perl5/i386-linux
  script  => /home/ken/bin
  bin     => /home/ken/bin
  bindoc  => /home/ken/man/man1
  libdoc  => /home/ken/man/man3
  binhtml => /home/ken/html
  libhtml => /home/ken/html

=head2 prefix

This sets a prefix, identical to ExtUtils::MakeMaker's PREFIX option. This does something similar to C<install_base> in a much more complicated way.

=head2 config()

The L<ExtUtils::Config|ExtUtils::Config> object used for this object.

=head2 verbose

The verbosity of ExtUtils::InstallPaths. It defaults to 0

=head2 create_packlist

Together with C<module_name> this controls whether a packlist will be added; it defaults to 1.

=head2 dist_name

The name of the current module.

=head2 module_name

The name of the main module of the package. This is required for packlist creation, but in the future it may be replaced by dist_name. It defaults to C<dist_name =~ s/-/::/gr> if dist_name is set.

=head2 destdir

If you want to install everything into a temporary directory first (for instance, if you want to create a directory tree that a package manager like C<rpm> or C<dpkg> could create a package from), you can use the C<destdir> parameter. E.g. Setting C<destdir> to C<"/tmp/foo"> will effectively install to "/tmp/foo/$sitelib", "/tmp/foo/$sitearch", and the like, except that it will use C<File::Spec> to make the pathnames work correctly on whatever platform you're installing on.

=head1 METHODS

=head2 new

Create a new ExtUtils::InstallPaths object. B<All attributes are valid arguments> to the constructor, as well as this:

=over 4

=item * install_path

This must be a hashref with the type as keys and the destination as values.

=item * install_base_relpaths

This must be a hashref with types as keys and a path relative to the install_base as value.

=item * prefix_relpaths

This must be a hashref any of these three keys: core, vendor, site. Each of the values mush be a hashref with types as keys and a path relative to the prefix as value. You probably want to make these three hashrefs identical.

=item * original_prefix

This must be a hashref with the legal installdirs values as keys and the prefix directories as values.

=item * install_sets

This mush be a hashref with the legal installdirs are keys, and the values being hashrefs with types as keys and locations as values.

=back

=head2 install_map()

Return a map suitable for use with L<ExtUtils::Install>. B<In most cases, this is the only method you'll need>.

=head2 install_destination($type)

Returns the destination of a certain type.

=head2 install_types()

Return a list of all supported install types in the current configuration.

=head2 is_default_installable($type)

Given a file type, will return true if the file type would normally be installed when neither install-base nor prefix has been set.  I.e. it will be true only if the path is set from the configuration object or set explicitly by the user via install_path.

=head2 install_path($type)

Gets the install path for a certain type.

=head2 install_sets($installdirs, $type)

Get the path for a certain C<$type> with a certain C<$installdirs>.

=head2 install_base_relpaths($type, $relpath)

Get the relative paths for use with install_base for a certain type.

=head2 prefix_relative($installdirs, $type)

Gets the path of a certain C<$type> and C<$installdirs> relative to the prefix.

=head2 prefix_relpaths($install_dirs, $type)

Get the default relative path to use in case the config install paths cannot be prefixified. You do not want to use this to get any relative path, but may require it to set it for custom types.

=head2 original_prefix($installdirs)

Get the original prefix for a certain type of $installdirs.

=head1 SEE ALSO

=over 4

=item * L<Build.PL spec|http://github.com/dagolden/cpan-api-buildpl/blob/master/lib/CPAN/API/BuildPL.pm>

=back

=head1 AUTHORS

=over 4

=item *

Ken Williams <kwilliams@cpan.org>

=item *

Leon Timmermans <leont@cpan.org>

=back

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Ken Williams, Leon Timmermans.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
