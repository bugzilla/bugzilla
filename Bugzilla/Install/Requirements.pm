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

use parent qw(Exporter);
use autodie;

our @EXPORT = qw(
    FEATURE_FILES

    check_requirements
    check_webdotbase
    check_font_file
    map_files_to_features
);

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
    markdown      => ['Bugzilla/Markdown.pm'],
    memcached     => ['Bugzilla/Memcache.pm'],
    auth_delegation => ['auth.cgi'],
);

sub check_requirements {
    my ($output) = @_;

    my $missing_apache = _missing_apache_modules(APACHE_MODULES, $output);

    # If we're running on Windows, reset the input line terminator so that
    # console input works properly - loading CGI tends to mess it up
    $/ = "\015\012" if ON_WINDOWS;

    return { apache  => $missing_apache };
}

sub _missing_apache_modules {
    my ($modules, $output) = @_;
    my $apachectl = _get_apachectl();
    return [] if !$apachectl;
    my $command = "$apachectl -t -D DUMP_MODULES";
    my $cmd_info = `$command 2>&1`;
    # If apachectl returned a value greater than 0, then there was an
    # error parsing Apache's configuration, and we can't check modules.
    my $retval = $?;
    if ($retval > 0) {
        print STDERR install_string('apachectl_failed', 
            { command => $command, root => ROOT_USER }), "\n";
        return [];
    }
    my @missing;
    foreach my $module (sort keys %$modules) {
        my $ok = _check_apache_module($module, $modules->{$module}, 
                                      $cmd_info, $output);
        push(@missing, $module) if !$ok;
    }
    return \@missing;
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

sub _check_apache_module {
    my ($module, $config_name, $mod_info, $output) = @_;
    my $ok;
    if ($mod_info =~ /^\s+\Q$config_name\E\b/m) {
        $ok = 1;
    }
    if ($output) {
        _checking_for({ package => $module, ok => $ok });
    }
    return $ok;
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
    my $want_string  = $wanted ? "v$wanted" : install_string('any');

    my $str = sprintf "%s %20s %-11s $ok_string $black_string\n",
                install_string('checking_for'), $package, "($want_string)";
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

=item C<check_requirements>

=over

=item B<Description>

This checks what optional or required perl modules are installed, like
C<checksetup.pl> does.

=item B<Params>

=over

=item C<$output> - C<true> if you want the function to print out information
about what it's doing, and the versions of everything installed.

=back

=item B<Returns>

A hashref containing these values:

=over

=item C<apache> - The name of each optional Apache module that is missing.

=back

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

