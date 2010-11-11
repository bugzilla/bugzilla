# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# Contributor(s): Max Kanat-Alexander <mkanat@bugzilla.org>
#                 Marc Schumann <wurblzap@gmail.com>

package Bugzilla::Install::Requirements;

# NOTE: This package MUST NOT "use" any Bugzilla modules other than
# Bugzilla::Constants, anywhere. We may "use" standard perl modules.
#
# Subroutines may "require" and "import" from modules, but they
# MUST NOT "use."

use strict;

use Bugzilla::Constants;
use Bugzilla::Install::Util qw(vers_cmp install_string);
use List::Util qw(max);
use Safe;

use base qw(Exporter);
our @EXPORT = qw(
    REQUIRED_MODULES
    OPTIONAL_MODULES

    check_requirements
    check_graphviz
    have_vers
    install_command
);

# This is how many *'s are in the top of each "box" message printed
# by checksetup.pl.
use constant TABLE_WIDTH => 71;

# The below two constants are subroutines so that they can implement
# a hook. Other than that they are actually constants.

# "package" is the perl package we're checking for. "module" is the name
# of the actual module we load with "require" to see if the package is
# installed or not. "version" is the version we need, or 0 if we'll accept
# any version.
#
# "blacklist" is an arrayref of regular expressions that describe versions that
# are 'blacklisted'--that is, even if the version is high enough, Bugzilla
# will refuse to say that it's OK to run with that version.
sub REQUIRED_MODULES {
    my $perl_ver = sprintf('%vd', $^V);
    my @modules = (
    {
        package => 'CGI.pm',
        module  => 'CGI',
        # Perl 5.10 requires CGI 3.33 due to a taint issue when
        # uploading attachments, see bug 416382.
        # Require CGI 3.21 for -httponly support, see bug 368502.
        version => (vers_cmp($perl_ver, '5.10') > -1) ? '3.33' : '3.21',
        # CGI::Carp in 3.46 and 3.47 breaks Template Toolkit
        blacklist => ['^3\.46$', '^3\.47$'],
    },
    {
        package => 'Digest-SHA',
        module  => 'Digest::SHA',
        version => 0
    },
    {
        package => 'TimeDate',
        module  => 'Date::Format',
        version => '2.21'
    },
    # 0.28 fixed some important bugs in DateTime.
    {
        package => 'DateTime',
        module  => 'DateTime',
        version => '0.28'
    },
    # 0.79 is required to work on Windows Vista and Windows Server 2008.
    # As correctly detecting the flavor of Windows is not easy,
    # we require this version for all Windows installations.
    # 0.71 fixes a major bug affecting all platforms.
    {
        package => 'DateTime-TimeZone',
        module  => 'DateTime::TimeZone',
        version => ON_WINDOWS ? '0.79' : '0.71'
    },
    {
        package => 'DBI',
        module  => 'DBI',
        version => '1.41'
    },
    # 2.22 fixes various problems related to UTF8 strings in hash keys,
    # as well as line endings on Windows.
    {
        package => 'Template-Toolkit',
        module  => 'Template',
        version => '2.22'
    },
    {
        package => 'Email-Send',
        module  => 'Email::Send',
        version => ON_WINDOWS ? '2.16' : '2.00',
        blacklist => ['^2\.196$']
    },
    {
        package => 'Email-MIME',
        module  => 'Email::MIME',
        version => '1.861'
    },
    {
        package => 'Email-MIME-Encodings',
        module  => 'Email::MIME::Encodings',
        # Fixes bug 486206
        version => '1.313',
    },
    {
        package => 'Email-MIME-Modifier',
        module  => 'Email::MIME::Modifier',
        version => '1.442'
    },
    {
        package => 'URI',
        module  => 'URI',
        version => 0
    },
    );

    my $all_modules = _get_extension_requirements(
        'REQUIRED_MODULES', \@modules);
    return $all_modules;
};

sub OPTIONAL_MODULES {
    my @modules = (
    {
        package => 'GD',
        module  => 'GD',
        version => '1.20',
        feature => 'Graphical Reports, New Charts, Old Charts'
    },
    {
        package => 'Chart',
        module  => 'Chart::Base',
        version => '1.0',
        feature => 'New Charts, Old Charts'
    },
    {
        package => 'Template-GD',
        # This module tells us whether or not Template-GD is installed
        # on Template-Toolkits after 2.14, and still works with 2.14 and lower.
        module  => 'Template::Plugin::GD::Image',
        version => 0,
        feature => 'Graphical Reports'
    },
    {
        package => 'GDTextUtil',
        module  => 'GD::Text',
        version => 0,
        feature => 'Graphical Reports'
    },
    {
        package => 'GDGraph',
        module  => 'GD::Graph',
        version => 0,
        feature => 'Graphical Reports'
    },
    {
        package => 'XML-Twig',
        module  => 'XML::Twig',
        version => 0,
        feature => 'Move Bugs Between Installations'
    },
    {
        package => 'MIME-tools',
        # MIME::Parser is packaged as MIME::Tools on ActiveState Perl
        module  => ON_WINDOWS ? 'MIME::Tools' : 'MIME::Parser',
        version => '5.406',
        feature => 'Move Bugs Between Installations'
    },
    {
        package => 'libwww-perl',
        module  => 'LWP::UserAgent',
        version => 0,
        feature => 'Automatic Update Notifications'
    },
    {
        package => 'PatchReader',
        module  => 'PatchReader',
        version => '0.9.4',
        feature => 'Patch Viewer'
    },
    {
        package => 'PerlMagick',
        module  => 'Image::Magick',
        version => 0,
        feature => 'Optionally Convert BMP Attachments to PNGs'
    },
    {
        package => 'perl-ldap',
        module  => 'Net::LDAP',
        version => 0,
        feature => 'LDAP Authentication'
    },
    {
        package => 'Authen-SASL',
        module  => 'Authen::SASL',
        version => 0,
        feature => 'SMTP Authentication'
    },
    {
        package => 'RadiusPerl',
        module  => 'Authen::Radius',
        version => 0,
        feature => 'RADIUS Authentication'
    },
    {
        package => 'SOAP-Lite',
        module  => 'SOAP::Lite',
        # 0.710.04 is required for correct UTF-8 handling, but .04 and .05 are
        # affected by bug 468009.
        version => '0.710.06',
        feature => 'XML-RPC Interface'
    },
    {
        # We need the 'utf8_mode' method of HTML::Parser, for HTML::Scrubber.
        package => 'HTML-Parser',
        module  => 'HTML::Parser',
        version => '3.40',
        feature => 'More HTML in Product/Group Descriptions'
    },
    {
        package => 'HTML-Scrubber',
        module  => 'HTML::Scrubber',
        version => 0,
        feature => 'More HTML in Product/Group Descriptions'
    },

    # Inbound Email
    {
        package => 'Email-MIME-Attachment-Stripper',
        module  => 'Email::MIME::Attachment::Stripper',
        version => 0,
        feature => 'Inbound Email'
    },
    {
        package => 'Email-Reply',
        module  => 'Email::Reply',
        version => 0,
        feature => 'Inbound Email'
    },

    # Mail Queueing
    {
        package => 'TheSchwartz',
        module  => 'TheSchwartz',
        version => 0,
        feature => 'Mail Queueing',
    },
    {
        package => 'Daemon-Generic',
        module  => 'Daemon::Generic',
        version => 0,
        feature => 'Mail Queueing',
    },

    # mod_perl
    {
        package => 'mod_perl',
        module  => 'mod_perl2',
        version => '1.999022',
        feature => 'mod_perl'
    },

    {
        package => 'CGI.pm',
        module  => 'CGI',
        # 3.50 fixes a security problem that affects Bugzilla.
        # (bug 591165)
        version => '3.50',
        feature => 'Recommended important security fix'
    },
    );

    my $all_modules = _get_extension_requirements(
        'OPTIONAL_MODULES', \@modules);
    return $all_modules;
};

# This implements the install-requirements hook described in Bugzilla::Hook.
sub _get_extension_requirements {
    my ($function, $base_modules) = @_;
    my @all_modules;
    # get a list of all extensions
    my @extensions = glob(bz_locations()->{'extensionsdir'} . "/*");
    foreach my $extension (@extensions) {
        my $file = "$extension/code/install-requirements.pl";
        if (-e $file) {
            my $safe = new Safe;
            # This is a very liberal Safe.
            $safe->permit(qw(:browse require entereval caller));
            $safe->rdo($file);
            if ($@) {
                warn $@;
                next;
            }
            my $modules = eval { &{$safe->varglob($function)}($base_modules) };
            next unless $modules;
            push(@all_modules, @$modules);
        }
    }

    unshift(@all_modules, @$base_modules);
    return \@all_modules;
};

sub check_requirements {
    my ($output) = @_;

    print "\n", install_string('checking_modules'), "\n" if $output;
    my $root = ROOT_USER;
    my $missing = _check_missing(REQUIRED_MODULES, $output);

    print "\n", install_string('checking_dbd'), "\n" if $output;
    my $have_one_dbd = 0;
    my $db_modules = DB_MODULE;
    foreach my $db (keys %$db_modules) {
        my $dbd = $db_modules->{$db}->{dbd};
        $have_one_dbd = 1 if have_vers($dbd, $output);
    }

    print "\n", install_string('checking_optional'), "\n" if $output;
    my $missing_optional = _check_missing(OPTIONAL_MODULES, $output);

    # If we're running on Windows, reset the input line terminator so that
    # console input works properly - loading CGI tends to mess it up
    $/ = "\015\012" if ON_WINDOWS;

    my $pass = !scalar(@$missing) && $have_one_dbd;
    return {
        pass     => $pass,
        one_dbd  => $have_one_dbd,
        missing  => $missing,
        optional => $missing_optional,
        any_missing => !$pass || scalar(@$missing_optional),
    };
}

# A helper for check_requirements
sub _check_missing {
    my ($modules, $output) = @_;

    my @missing;
    foreach my $module (@$modules) {
        unless (have_vers($module, $output)) {
            push(@missing, $module);
        }
    }

    return \@missing;
}

# Returns the build ID of ActivePerl. If several versions of
# ActivePerl are installed, it won't be able to know which one
# you are currently running. But that's our best guess.
sub _get_activestate_build_id {
    eval 'use Win32::TieRegistry';
    return 0 if $@;
    my $key = Win32::TieRegistry->new('LMachine\Software\ActiveState\ActivePerl')
      or return 0;
    return $key->GetValue("CurrentVersion");
}

sub print_module_instructions {
    my ($check_results, $output) = @_;

    # First we print the long explanatory messages.

    if (scalar @{$check_results->{missing}}) {
        print install_string('modules_message_required');
    }

    if (!$check_results->{one_dbd}) {
        print install_string('modules_message_db');
    }

    if (my @missing = @{$check_results->{optional}} and $output) {
        print install_string('modules_message_optional');
        # Now we have to determine how large the table cols will be.
        my $longest_name = max(map(length($_->{package}), @missing));

        # The first column header is at least 11 characters long.
        $longest_name = 11 if $longest_name < 11;

        # The table is TABLE_WIDTH characters long. There are seven mandatory
        # characters (* and space) in the string. So, we have a total
        # of TABLE_WIDTH - 7 characters to work with.
        my $remaining_space = (TABLE_WIDTH - 7) - $longest_name;
        print '*' x TABLE_WIDTH . "\n";
        printf "* \%${longest_name}s * %-${remaining_space}s *\n",
               'MODULE NAME', 'ENABLES FEATURE(S)';
        print '*' x TABLE_WIDTH . "\n";
        foreach my $package (@missing) {
            printf "* \%${longest_name}s * %-${remaining_space}s *\n",
                   $package->{package}, $package->{feature};
        }
    }

    # We only print the PPM repository note if we have to.
    if ((!$output && @{$check_results->{missing}})
        || ($output && $check_results->{any_missing}))
    {
        if (ON_WINDOWS) {
            my $perl_ver = sprintf('%vd', $^V);
            
            # URL when running Perl 5.8.x.
            my $url_to_theory58S = 'http://theoryx5.uwinnipeg.ca/ppms';
            # Packages for Perl 5.10 are not compatible with Perl 5.8.
            if (vers_cmp($perl_ver, '5.10') > -1) {
                $url_to_theory58S = 'http://cpan.uwinnipeg.ca/PPMPackages/10xx/';
            }
            print install_string('ppm_repo_add', 
                                 { theory_url => $url_to_theory58S });
            # ActivePerls older than revision 819 require an additional command.
            if (_get_activestate_build_id() < 819) {
                print install_string('ppm_repo_up');
            }
        }

        # If any output was required, we want to close the "table"
        print "*" x TABLE_WIDTH . "\n";
    }

    # And now we print the actual installation commands.

    if (my @missing = @{$check_results->{optional}} and $output) {
        print install_string('commands_optional') . "\n\n";
        foreach my $module (@missing) {
            my $command = install_command($module);
            printf "%15s: $command\n", $module->{package};
        }
        print "\n";
    }

    if (!$check_results->{one_dbd}) {
        print install_string('commands_dbd') . "\n";
        my %db_modules = %{DB_MODULE()};
        foreach my $db (keys %db_modules) {
            my $command = install_command($db_modules{$db}->{dbd});
            printf "%10s: \%s\n", $db_modules{$db}->{name}, $command;
        }
        print "\n";
    }

    if (my @missing = @{$check_results->{missing}}) {
        print install_string('commands_required') . "\n";
        foreach my $package (@missing) {
            my $command = install_command($package);
            print "    $command\n";
        }
    }

    if ($output && $check_results->{any_missing} && !ON_WINDOWS) {
        print install_string('install_all', { perl => $^X });
    }
}

sub check_graphviz {
    my ($output) = @_;

    return 1 if (Bugzilla->params->{'webdotbase'} =~ /^https?:/);

    printf("Checking for %15s %-9s ", "GraphViz", "(any)") if $output;

    my $return = 0;
    if(-x Bugzilla->params->{'webdotbase'}) {
        print "ok: found\n" if $output;
        $return = 1;
    } else {
        print "not a valid executable: " . Bugzilla->params->{'webdotbase'} . "\n";
    }

    my $webdotdir = bz_locations()->{'webdotdir'};
    # Check .htaccess allows access to generated images
    if (-e "$webdotdir/.htaccess") {
        my $htaccess = new IO::File("$webdotdir/.htaccess", 'r') 
            || die "$webdotdir/.htaccess: " . $!;
        if (!grep(/png/, $htaccess->getlines)) {
            print "Dependency graph images are not accessible.\n";
            print "delete $webdotdir/.htaccess and re-run checksetup.pl to fix.\n";
        }
        $htaccess->close;
    }

    return $return;
}

# This was originally clipped from the libnet Makefile.PL, adapted here to
# use the below vers_cmp routine for accurate version checking.
sub have_vers {
    my ($params, $output) = @_;
    my $module  = $params->{module};
    my $package = $params->{package};
    if (!$package) {
        $package = $module;
        $package =~ s/::/-/g;
    }
    my $wanted  = $params->{version};

    eval "require $module;";

    # VERSION is provided by UNIVERSAL::
    my $vnum = eval { $module->VERSION } || -1;

    # CGI's versioning scheme went 2.75, 2.751, 2.752, 2.753, 2.76
    # That breaks the standard version tests, so we need to manually correct
    # the version
    if ($module eq 'CGI' && $vnum =~ /(2\.7\d)(\d+)/) {
        $vnum = $1 . "." . $2;
    }

    my $vstr;
    if ($vnum eq "-1") { # string compare just in case it's non-numeric
        $vstr = install_string('module_not_found');
    }
    elsif (vers_cmp($vnum,"0") > -1) {
        $vstr = install_string('module_found', { ver => $vnum });
    }
    else {
        $vstr = install_string('module_unknown_version');
    }

    my $vok = (vers_cmp($vnum,$wanted) > -1);
    my $blacklisted;
    if ($vok && $params->{blacklist}) {
        $blacklisted = grep($vnum =~ /$_/, @{$params->{blacklist}});
        $vok = 0 if $blacklisted;
    }

    if ($output) {
        my $ok           = $vok ? install_string('module_ok') : '';
        my $black_string = $blacklisted ? install_string('blacklisted') : '';
        my $want_string  = $wanted ? "v$wanted" : install_string('any');

        $ok = "$ok:" if $ok;
        printf "%s %19s %-9s $ok $vstr $black_string\n",
            install_string('checking_for'), $package, "($want_string)";
    }
    
    return $vok ? 1 : 0;
}

sub install_command {
    my $module = shift;
    my ($command, $package);

    if (ON_WINDOWS) {
        $command = 'ppm install %s';
        $package = $module->{package};
    }
    else {
        $command = "$^X install-module.pl \%s";
        # Non-Windows installations need to use module names, because
        # CPAN doesn't understand package names.
        $package = $module->{module};
    }
    return sprintf $command, $package;
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

=over 4

=item C<REQUIRED_MODULES>

An arrayref of hashrefs that describes the perl modules required by 
Bugzilla. The hashes have two keys, C<name> and C<version>, which
represent the name of the module and the version that we require.

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

=item C<pass> - Whether or not we have all the mandatory requirements.

=item C<missing> - An arrayref containing any required modules that
are not installed or that are not up-to-date. Each item in the array is
a hashref in the format of items from L</REQUIRED_MODULES>.

=item C<optional> - The same as C<missing>, but for optional modules.

=item C<have_one_dbd> - True if at least one C<DBD::> module is installed.

=item C<any_missing> - True if there are any missing modules, even optional
modules.

=back

=back

=item C<check_graphviz($output)>

Description: Checks if the graphviz binary specified in the 
  C<webdotbase> parameter is a valid binary, or a valid URL.

Params:      C<$output> - C<$true> if you want the function to
                 print out information about what it's doing.

Returns:     C<1> if the check was successful, C<0> otherwise.

=item C<have_vers($module, $output)>

 Description: Tells you whether or not you have the appropriate
              version of the module requested. It also prints
              out a message to the user explaining the check
              and the result.

 Params:      C<$module> - A hashref, in the format of an item from 
                           L</REQUIRED_MODULES>.
              C<$output> - Set to true if you want this function to
                           print information to STDOUT about what it's
                           doing.

 Returns:   C<1> if you have the module installed and you have the
            appropriate version. C<0> otherwise.

=item C<install_command($module)>

 Description: Prints out the appropriate command to install the
              module specified, depending on whether you're
              on Windows or Linux.

 Params:      C<$module> - A hashref, in the format of an item from
                           L</REQUIRED_MODULES>.

 Returns:     nothing

=back
