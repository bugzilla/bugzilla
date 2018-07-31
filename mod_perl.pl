#!/usr/bin/perl -T
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::ModPerl;

use 5.10.1;
use strict;
use warnings;

# This sets up our libpath without having to specify it in the mod_perl
# configuration.
use File::Basename;
use File::Spec;
BEGIN {
    require lib;
    my $dir = dirname(__FILE__);
    lib->import($dir, File::Spec->catdir($dir, "lib"), File::Spec->catdir($dir, qw(local lib perl5)));
}

use Bugzilla::ModPerl::StartupFix;
use Taint::Util qw(untaint);

use constant USE_NYTPROF => !! $ENV{USE_NYTPROF};
use constant NYTPROF_DIR => do {
    my $dir = $ENV{NYTPROF_DIR};
    untaint($dir);
    $dir;
};
BEGIN {
    if (USE_NYTPROF) {
        $ENV{NYTPROF} = "savesrc=0:start=no:addpid=1";
    }
}
use if USE_NYTPROF, 'Devel::NYTProf::Apache';

use Bugzilla::Constants ();

# If you have an Apache2::Status handler in your Apache configuration,
# you need to load Apache2::Status *here*, so that any later-loaded modules
# can report information to Apache2::Status.
#use Apache2::Status ();

# We don't want to import anything into the global scope during
# startup, so we always specify () after using any module in this
# file.

use Apache2::Log ();
use Apache2::ServerUtil;
use Apache2::SizeLimit;
use ModPerl::RegistryLoader ();
use File::Basename ();
use File::Find ();
use English qw(-no_match_vars $OSNAME);

# This loads most of our modules.
use Bugzilla ();
# Loading Bugzilla.pm doesn't load this, though, and we want it preloaded.
use Bugzilla::BugMail ();
use Bugzilla::CGI ();
use Bugzilla::Extension ();
use Bugzilla::Install::Requirements ();
use Bugzilla::Util ();
use Bugzilla::RNG ();
use Bugzilla::ModPerl ();
use Mojo::Loader qw(find_modules);
use Module::Runtime qw(require_module);
use Bugzilla::WebService::Server::REST;

# Make warnings go to the virtual host's log and not the main
# server log.
BEGIN { *CORE::GLOBAL::warn = \&Apache2::ServerRec::warn; }

# Pre-compile the CGI.pm methods that we're going to use.
Bugzilla::CGI->compile(qw(:cgi :push));

# This means that every httpd child will die after processing a request if it
# is taking up more than $apache_size_limit of RAM all by itself, not counting RAM it is
# sharing with the other httpd processes.
my $limit = Bugzilla->localconfig->{apache_size_limit};
if ($OSNAME eq 'linux' && ! eval { require Linux::Smaps }) {
    WARN('SizeLimit requires Linux::Smaps on linux. size limit set to 800MB');
    $limit = 800_000;
}
Apache2::SizeLimit->set_max_unshared_size($limit);

my $cgi_path = Bugzilla::Constants::bz_locations()->{'cgi_path'};

# Set up the configuration for the web server
my $server = Apache2::ServerUtil->server;
my $conf = Bugzilla::ModPerl->apache_config($cgi_path);
$server->add_config([ grep { length $_ } split("\n", $conf)]);

# Pre-load localconfig. It might already be loaded, but we need to make sure.
Bugzilla->localconfig;
if ($ENV{LOCALCONFIG_ENV}) {
    delete @ENV{ (Bugzilla::Install::Localconfig::ENV_KEYS) };
}

# Pre-load all extensions
Bugzilla::Extension->load_all();

Bugzilla->preload_features();

require_module($_) for find_modules('Bugzilla::User::Setting');

Bugzilla::WebService::Server::REST->preload;

# Force instantiation of template so Bugzilla::Template::PreloadProvider can do its magic.
Bugzilla->preload_templates;

# Have ModPerl::RegistryLoader pre-compile all CGI scripts.
my $rl = new ModPerl::RegistryLoader();
# If we try to do this in "new" it fails because it looks for a
# Bugzilla/ModPerl/ResponseHandler.pm
$rl->{package} = 'Bugzilla::ModPerl::ResponseHandler';
my $feature_files = Bugzilla::Install::Requirements::map_files_to_features();

# Prevent "use lib" from doing anything when the .cgi files are compiled.
# This is important to prevent the current directory from getting into
# @INC and messing things up. (See bug 630750.)
no warnings 'redefine';
local *lib::import = sub {};
use warnings;

foreach my $file (glob "$cgi_path/*.cgi") {
    my $base_filename = File::Basename::basename($file);
    if (my $feature = $feature_files->{$base_filename}) {
        next if !Bugzilla->feature($feature);
    }
    Bugzilla::Util::trick_taint($file);
    $rl->handler($file, $file);
}

# Some items might already be loaded into the request cache
# best to make sure it starts out empty.
# Because of bug 1347335 we also do this in init_page().
Bugzilla::clear_request_cache();

package Bugzilla::ModPerl::ResponseHandler;
use strict;
use base qw(ModPerl::Registry);
use Bugzilla;
use Bugzilla::Constants qw(USAGE_MODE_REST bz_locations);
use Time::HiRes;
use Sys::Hostname;

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

    if (Bugzilla::ModPerl::USE_NYTPROF) {
        state $count = {};
        state $dir  = Bugzilla::ModPerl::NYTPROF_DIR // bz_locations()->{datadir};
        state $host = (split(/\./, hostname()))[0];
        my $script = File::Basename::basename($ENV{SCRIPT_FILENAME});
        $script =~ s/\.cgi$//;
        my $file = $dir . "/nytprof.$host.$script." . ++$count->{$$};
        DB::enable_profile($file);
    }
    Bugzilla::init_page();
    my $result = $class->SUPER::handler(@_);
    if (Bugzilla::ModPerl::USE_NYTPROF) {
        DB::disable_profile();
        DB::finish_profile();
    }

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

sub handler {
    my $r = shift;

    Bugzilla::_cleanup();

    return Apache2::Const::OK;
}

1;
