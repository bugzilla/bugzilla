# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Install::Requirements;

# NOTE: This package MUST NOT "use" any Bugzilla modules other than
# Bugzilla::Constants, anywhere. We may "use" standard perl modules.
#
# Subroutines may "require" and "import" from modules, but they
# MUST NOT "use."

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Constants;
use Bugzilla::Install::Util qw(install_string bin_loc success
                               extension_requirement_packages);
use List::Util qw(max);
use Term::ANSIColor;
use CPAN::Meta;
use CPAN::Meta::Prereqs;
use CPAN::Meta::Requirements;
use Module::Metadata;

use parent qw(Exporter);
use autodie;

our @EXPORT = qw(
    FEATURE_FILES

    check_cpan_requirements
    check_cpan_feature
    check_all_cpan_features
    check_webdotbase
    check_font_file
    map_files_to_features
);

our $checking_for_indent = 0;

# This is how many *'s are in the top of each "box" message printed
# by checksetup.pl.
use constant TABLE_WIDTH => 71;

# Optional Apache modules that have no Perl component to them.
# If these are installed, Bugzilla has additional functionality.
#
# The keys are the names of the modules, the values are what the module
# is called in the output of "apachectl -t -D DUMP_MODULES".
use constant APACHE_MODULES => {
    mod_headers => 'headers_module',
    mod_env     => 'env_module',
    mod_expires => 'expires_module',
    mod_rewrite => 'rewrite_module',
    mod_version => 'version_module'
};

# These are all of the binaries that we could possibly use that can
# give us info about which Apache modules are installed.
# If we can't use "apachectl", the "httpd" binary itself takes the same
# parameters. Note that on Debian and Gentoo, there is an "apache2ctl",
# but it takes different parameters on each of those two distros, so we
# don't use apache2ctl.
use constant APACHE => qw(apachectl httpd apache2 apache);

# If we don't find any of the above binaries in the normal PATH,
# these are extra places we look.
use constant APACHE_PATH => [qw(
    /usr/sbin
    /usr/local/sbin
    /usr/libexec
    /usr/local/libexec
)];

# This maps features to the files that require that feature in order
# to compile. It is used by t/001compile.t and mod_perl.pl.
use constant FEATURE_FILES => (
    jsonrpc       => ['Bugzilla/WebService/Server/JSONRPC.pm', 'jsonrpc.cgi'],
    xmlrpc        => ['Bugzilla/WebService/Server/XMLRPC.pm', 'xmlrpc.cgi',
                      'Bugzilla/WebService.pm', 'Bugzilla/WebService/*.pm'],
    rest          => ['Bugzilla/API/Server.pm', 'rest.cgi', 'Bugzilla/API/*/*.pm',
                      'Bugzilla/API/*/Server.pm', 'Bugzilla/API/*/Resource/*.pm'],
    csp           => ['Bugzilla/CGI/ContentSecurityPolicy.pm'],
    psgi          => ['app.psgi'],
    moving        => ['importxml.pl'],
    auth_ldap     => ['Bugzilla/Auth/Verify/LDAP.pm'],
    auth_radius   => ['Bugzilla/Auth/Verify/RADIUS.pm'],
    documentation => ['docs/makedocs.pl'],
    inbound_email => ['email_in.pl'],
    jobqueue      => ['Bugzilla/Job/*', 'Bugzilla/JobQueue.pm',
                      'Bugzilla/JobQueue/*', 'jobqueue.pl'],
    patch_viewer  => ['Bugzilla/Attachment/PatchReader.pm'],
    updates       => ['Bugzilla/Update.pm'],
    mfa           => ['Bugzilla/MFA/*.pm'],
    markdown      => ['Bugzilla/Markdown.pm'],
    memcached     => ['Bugzilla/Memcache.pm'],
    auth_delegation => ['auth.cgi'],
    s3            => ['Bugzilla/S3.pm', 'Bugzilla/S3/Bucket.pm', 'Bugzilla/Attachment/S3.pm']
);

sub check_all_cpan_features {
    my ($meta, $dirs, $output) = @_;
    my %report;

    local $checking_for_indent = 2;

    print "\nOptional features:\n" if $output;
    my @features = sort { $a->identifier cmp $b->identifier } $meta->features;
    foreach my $feature (@features) {
        next if $feature->identifier eq 'features';
        printf "Feature '%s': %s\n", $feature->identifier, $feature->description if $output;
        my $result = check_cpan_feature($feature, $dirs, $output);
        print "\n" if $output;

        $report{$feature->identifier} = {
            description => $feature->description,
            result => $result,
        };
    }

    return \%report;
}

sub check_cpan_feature {
    my ($feature, $dirs, $output) = @_;

    return _check_prereqs($feature->prereqs, $dirs, $output);
}

sub check_cpan_requirements {
    my ($meta, $dirs, $output) = @_;

    my $result = _check_prereqs($meta->effective_prereqs, $dirs, $output);
    print colored(install_string('installation_failed'), COLOR_ERROR), "\n" if !$result->{ok} && $output;
    return $result;
}

sub _check_prereqs {
    my ($prereqs, $dirs, $output) = @_;
    $dirs //= \@INC;
    my $reqs = Bugzilla::CPAN->cpan_requirements($prereqs);
    my @found;
    my @missing;

    foreach my $module (sort $reqs->required_modules) {
        my $ok = _check_module($reqs, $module, $dirs, $output);
        if ($ok) {
            push @found, $module;
        }
        else {
            push @missing, $module;
        }
    }

    return { ok => (@missing == 0), found => \@found, missing => \@missing };
}

sub _check_module {
    my ($reqs, $module, $dirs, $output) = @_;
    my $required_version = $reqs->requirements_for_module($module);

    if ($module eq 'perl') {
        my $ok = $reqs->accepts_module($module, $]);
        _checking_for({package => "perl", found => $], wanted => $required_version, ok => $ok}) if $output;
        return $ok;
    } else {
        my $metadata = Module::Metadata->new_from_module($module, inc => $dirs);
        my $version = eval { $metadata->version };
        my $ok = $metadata && $version && $reqs->accepts_module($module, $version || 0);
        _checking_for({package => $module, $version ? ( found => $version ) : (), wanted => $required_version, ok => $ok}) if $output;

        return $ok;
    }
}


sub _get_apachectl {
    foreach my $bin_name (APACHE) {
        my $bin = bin_loc($bin_name);
        return $bin if $bin;
    }
    # Try again with a possibly different path.
    foreach my $bin_name (APACHE) {
        my $bin = bin_loc($bin_name, APACHE_PATH);
        return $bin if $bin;
    }
    return undef;
}

sub check_webdotbase {
    my ($output) = @_;

    my $webdotbase = Bugzilla->localconfig->{'webdotbase'};
    return 1 if $webdotbase =~ /^https?:/;

    my $return;
    $return = 1 if -x $webdotbase;

    if ($output) {
        _checking_for({ package => 'GraphViz', ok => $return });
    }

    if (!$return) {
        print install_string('bad_executable', { bin => $webdotbase }), "\n";
    }

    my $webdotdir = bz_locations()->{'webdotdir'};
    # Check .htaccess allows access to generated images
    if (-e "$webdotdir/.htaccess") {
        my $htaccess = new IO::File("$webdotdir/.htaccess", 'r')
            || die "$webdotdir/.htaccess: " . $!;
        if (!grep(/ \\\.png\$/, $htaccess->getlines)) {
            print STDERR install_string('webdot_bad_htaccess',
                                        { dir => $webdotdir }), "\n";
        }
        $htaccess->close;
    }

    return $return;
}

sub check_font_file {
    my ($output) = @_;

    my $font_file = Bugzilla->localconfig->{'font_file'};

    my $readable;
    $readable = 1 if -r $font_file;

    my $ttf;
    $ttf = 1 if $font_file =~ /\.(ttf|otf)$/;

    if ($output) {
        _checking_for({ package => 'Font file', ok => $readable && $ttf});
    }

    if (!$readable) {
        print install_string('bad_font_file', { file => $font_file }), "\n";
    }
    elsif (!$ttf) {
        print install_string('bad_font_file_name', { file => $font_file }), "\n";
    }

    return $readable && $ttf;
}

sub _checking_for {
    my ($params) = @_;
    my ($package, $ok, $wanted, $blacklisted, $found) =
        @$params{qw(package ok wanted blacklisted found)};

    my $ok_string = $ok ? install_string('module_ok') : '';

    # If we're actually checking versions (like for Perl modules), then
    # we have some rather complex logic to determine what we want to
    # show. If we're not checking versions (like for GraphViz) we just
    # show "ok" or "not found".
    if (exists $params->{found}) {
        my $found_string;
        # We do a string compare in case it's non-numeric. We make sure
        # it's not a version object as negative versions are forbidden.
        if ($found && !ref($found) && $found eq '-1') {
            $found_string = install_string('module_not_found');
        }
        elsif ($found) {
            $found_string = install_string('module_found', { ver => $found });
        }
        else {
            $found_string = install_string('module_unknown_version');
        }
        $ok_string = $ok ? "$ok_string: $found_string" : $found_string;
    }
    elsif (!$ok) {
        $ok_string = install_string('module_not_found');
    }

    my $black_string = $blacklisted ? install_string('blacklisted') : '';
    my $want_string  = $wanted ? "$wanted" : install_string('any');

    my $str = sprintf "%s %20s %-11s $ok_string $black_string\n",
      ( ' ' x $checking_for_indent ) . install_string('checking_for'),
      $package, "($want_string)";
    print $ok ? $str : colored($str, COLOR_ERROR);
}

# This does a reverse mapping for FEATURE_FILES.
sub map_files_to_features {
    my %features = FEATURE_FILES;
    my %files;
    foreach my $feature (keys %features) {
        my @my_files = @{ $features{$feature} };
        foreach my $pattern (@my_files) {
            foreach my $file (glob $pattern) {
                $files{$file} = $feature;
            }
        }
    }
    return \%files;
}

1;

__END__

=head1 NAME

Bugzilla::Install::Requirements - Functions and variables dealing
  with Bugzilla's perl-module requirements.

=head1 DESCRIPTION

This module is used primarily by C<checksetup.pl> to determine whether
or not all of Bugzilla's prerequisites are installed. (That is, all the
perl modules it requires.)

=head1 CONSTANTS

=over

=item C<FEATURE_FILES>

A hashref that describes what files should only be compiled if a certain
feature is enabled. The feature is the key, and the values are arrayrefs
of file names (which are passed to C<glob>, so shell patterns work).

=back

=head1 SUBROUTINES

=over 4

=item C<check_cpan_requirements>

=over

=item B<Description>

This checks what required perl modules are installed, like
C<checksetup.pl> does.

=item B<Params>

=over

=item C<$meta> - A C<CPAN::Meta> object.

=item C<$dirs> - the include dirs to search for modules, defaults to @INC.

=item C<$output> - C<true> if you want the function to print out information
about what it's doing, and the versions of everything installed.

=back

=item B<Returns>

A hashref containing these values:

=over

=item C<ok> - if all the requirements are met, this is true.

=item C<found> - an arrayref of found modules

=item C<missing> - an arrayref of missing modules

=back

=back

=item C<check_cpan_feature>

=over

=item B<Description>

This checks that the optional Perl modules required for a feature are installed.

=item B<Params>

=over

=item C<$feature> - A C<CPAN::Meta::Feature> object.

=item C<$dirs> - the include dirs to search for modules, defaults to @INC.

=item C<$output> - C<true> if you want the function to print out information about what it's doing, and the versions of everything installed.

=back

=item B<Returns>

A hashref containing these values:

=over

=item C<ok> - if all the requirements are met, this is true.

=item C<found> - an arrayref of found modules

=item C<missing> - an arrayref of missing modules

=back

=item C<check_all_cpan_features>

=over

=item B<Description>

This checks which optional Perl modules are currently installed which can enable optional features.

=item B<Params>

=over

=item C<$meta> - A C<CPAN::Meta> object.

=item C<$dirs> - the include dirs to search for modules, defaults to @INC.

=item C<$output> - C<true> if you want the function to print out information
about what it's doing, and the versions of everything installed.

=back

=item B<Returns>

A hashref keyed on the feature name. The values
are hashrefs containing C<description> and C<result> keys.

C<description> is the English description of the feature.

C<result> is a hashref in the same format as the return value of C<check_cpan_requirements()>,
described previously.

=back

=item C<check_webdotbase($output)>

Description: Checks if the graphviz binary specified in the
  C<webdotbase> parameter is a valid binary, or a valid URL.

Params:      C<$output> - C<$true> if you want the function to
                 print out information about what it's doing.

Returns:     C<1> if the check was successful, C<0> otherwise.

=item C<check_font_file($output)>

Description: Checks if the font file specified in the C<font_type> parameter
  is a valid-looking font file.

Params:      C<$output> - C<$true> if you want the function to
                 print out information about what it's doing.

Returns:     C<1> if the check was successful, C<0> otherwise.

=item C<map_files_to_features>

Returns a hashref where file names are the keys and the value is the feature
that must be enabled in order to compile that file.

=back

=back
