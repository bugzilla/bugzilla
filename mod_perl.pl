#!/usr/bin/perl -wT
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

package Bugzilla::ModPerl;
use strict;
use warnings;

# This sets up our libpath without having to specify it in the mod_perl
# configuration.
use File::Basename ();
use lib File::Basename::dirname(__FILE__);
use Bugzilla::Constants ();
use lib Bugzilla::Constants::bz_locations()->{'ext_libpath'};

# If you have an Apache2::Status handler in your Apache configuration,
# you need to load Apache2::Status *here*, so that any later-loaded modules
# can report information to Apache2::Status.
#use Apache2::Status ();

# We don't want to import anything into the global scope during
# startup, so we always specify () after using any module in this
# file.

use Apache2::Log ();
use Apache2::ServerUtil;
use ModPerl::RegistryLoader ();
use File::Slurp ();

# This loads most of our modules.
use Bugzilla ();
use Bugzilla::Extension ();

# Make warnings go to the virtual host's log and not the main
# server log.
BEGIN { *CORE::GLOBAL::warn = \&Apache2::ServerRec::warn; }

# Pre-compile the CGI.pm methods that we're going to use.
Bugzilla::CGI->compile(qw(:cgi :push));

# Preload all other packages
# This works by detecting which packages were loaded at run-time within our
# CleanupHandler and writing that list to data/mod_perl_preload.
# This ensures that even conditional packages (such as the database handler)
# will be pre-loaded.
$Bugzilla::extension_packages = Bugzilla::Extension->load_all();
my $data_path = Bugzilla::Constants::bz_locations()->{datadir};
my $preload_file = "$data_path/mod_perl_preload";
my %preloaded_files;
if (-e $preload_file) {
    my @files = File::Slurp::read_file($preload_file, { err_mode => 'carp' });
    chomp(@files);
    foreach my $file (@files) {
        $preloaded_files{$file} = 1;
        Bugzilla::Util::trick_taint($file);
        eval { require $file };
    }
}

use Apache2::SizeLimit;
# This means that every httpd child will die after processing a request if it
# is taking up more than 700MB of RAM all by itself, not counting RAM it is
# sharing with the other httpd processes.
if (Bugzilla->params->{'urlbase'} eq 'https://bugzilla.mozilla.org/') {
    Apache2::SizeLimit->set_max_unshared_size(700_000);
} else {
    Apache2::SizeLimit->set_max_unshared_size(250_000);
}

my $cgi_path = Bugzilla::Constants::bz_locations()->{'cgi_path'};

# Set up the configuration for the web server
my $server = Apache2::ServerUtil->server;
my $conf = <<EOT;
# Make sure each httpd child receives a different random seed (bug 476622).
# Bugzilla::RNG has one srand that needs to be called for
# every process, and Perl has another. (Various Perl modules still use
# the built-in rand(), even though we never use it in Bugzilla itself,
# so we need to srand() both of them.)
PerlChildInitHandler "sub { Bugzilla::RNG::srand(); srand(); }"
<Directory "$cgi_path">
    AddHandler perl-script .cgi
    # No need to PerlModule these because they're already defined in mod_perl.pl
    PerlResponseHandler Bugzilla::ModPerl::ResponseHandler
    PerlCleanupHandler  Apache2::SizeLimit Bugzilla::ModPerl::CleanupHandler
    PerlOptions +ParseHeaders
    Options +ExecCGI +FollowSymLinks
    AllowOverride Limit FileInfo Indexes
    DirectoryIndex index.cgi index.html
</Directory>
EOT

$server->add_config([split("\n", $conf)]);

package Bugzilla::ModPerl::ResponseHandler;
use strict;
use base qw(ModPerl::Registry);
use Bugzilla;
use Bugzilla::Constants qw(USAGE_MODE_REST);

sub handler : method {
    my $class = shift;

    # $0 is broken under mod_perl before 2.0.2, so we have to set it
    # here explicitly or init_page's shutdownhtml code won't work right.
    $0 = $ENV{'SCRIPT_FILENAME'};

    # Prevent "use lib" from modifying @INC in the case where a .cgi file
    # is being automatically recompiled by mod_perl when Apache is
    # running. (This happens if a file changes while Apache is already
    # running.)
    no warnings 'redefine';
    local *lib::import = sub {};
    use warnings;

    Bugzilla::init_page();
    my $result = $class->SUPER::handler(@_);

    # When returning data from the REST api we must only return 200 or 304,
    # which tells Apache not to append its error html documents to the
    # response.
    return Bugzilla->usage_mode == USAGE_MODE_REST && $result != 304
        ? Apache2::Const::OK
        : $result;
}


package Bugzilla::ModPerl::CleanupHandler;
use strict;
use Apache2::Const -compile => qw(OK);
use File::Slurp;

sub handler {
    my $r = shift;

    Bugzilla::_cleanup();
    # Sometimes mod_perl doesn't properly call DESTROY on all
    # the objects in pnotes()
    foreach my $key (keys %{$r->pnotes}) {
        delete $r->pnotes->{$key};
    }

    # Look for modules loaded post-startup
    my $dirty = 0;
    foreach my $file (keys %INC) {
        next unless $file =~ /\.pm$/;
        if (not exists $preloaded_files{$file}) {
            $preloaded_files{$file} = 1;
            $dirty = 1;
        }
    }
    if ($dirty) {
        write_file($preload_file, { atomic => 1, err_mode => 'carp' },
            join("\n", keys %preloaded_files) . "\n");
    }

    return Apache2::Const::OK;
}

1;
