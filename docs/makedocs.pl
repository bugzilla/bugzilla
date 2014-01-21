#!/usr/bin/perl -w
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# This script compiles all the documentation.
#
# Required software:
#
# 1) Sphinx documentation builder (python-sphinx package on Debian/Ubuntu)
#
# 2) pdflatex, which means the following Debian/Ubuntu packages:
#    * texlive-latex-base
#    * texlive-latex-recommended
#    * texlive-latex-extra
#    * texlive-fonts-recommended
#
# All these TeX packages together are close to a gig :-| But after you've
# installed them, you can remove texlive-latex-extra-doc to save 400MB.

use 5.10.1;
use strict;

use Cwd;

# We need to be in this directory to use our libraries.
BEGIN {
    require File::Basename;
    import File::Basename qw(dirname);
    chdir dirname($0);
}

use lib qw(.. ../lib lib);

# We only compile our POD if Pod::Simple is installed. We do the checks
# this way so that if there's a compile error in Pod::Simple::HTML::Bugzilla,
# makedocs doesn't just silently fail, but instead actually tells us there's
# a compile error.
my $pod_simple;
if (eval { require Pod::Simple }) {
    require Pod::Simple::HTMLBatch::Bugzilla;
    require Pod::Simple::HTML::Bugzilla;
    $pod_simple = 1;
};

use Bugzilla::Install::Requirements
    qw(REQUIRED_MODULES OPTIONAL_MODULES);
use Bugzilla::Constants qw(DB_MODULE BUGZILLA_VERSION);

use File::Path qw(rmtree);
use File::Which qw(which);

###############################################################################
# Generate minimum version list
###############################################################################

my $modules = REQUIRED_MODULES;
my $opt_modules = OPTIONAL_MODULES;

my $template;
{
    open(TEMPLATE, '<', 'definitions.rst.tmpl')
      or die('Could not open definitions.rst.tmpl: ' . $!);
    local $/;
    $template = <TEMPLATE>;
    close TEMPLATE;
}

# This file is included at the end of Sphinx's conf.py. Unfortunately there's
# no way to 'epilog' a file, only text.
open(SUBSTS, '>', 'definitions.rst') or die('Could not open definitions.rst: ' . $!);
print SUBSTS 'rst_epilog = """' . "\n$template\n";
print SUBSTS ".. Module Versions\n\n";

foreach my $module (@$modules, @$opt_modules)
{
    my $name = $module->{'module'};
    $name =~ s/::/-/g;
    $name = lc($name);
    #This needs to be a string comparison, due to the modules having
    #version numbers like 0.9.4
    my $version = $module->{'version'} eq 0 ? 'any' : $module->{'version'};
    print SUBSTS '.. |min-' . $name . '-ver| replace:: ' . $version . "\n";
}

print SUBSTS "\n.. Database Versions\n\n";

my $db_modules = DB_MODULE;
foreach my $db (keys %$db_modules) {
    my $dbd  = $db_modules->{$db}->{dbd};
    my $name = $dbd->{module};
    $name =~ s/::/-/g;
    $name = lc($name);
    my $version    = $dbd->{version} || 'any';
    my $db_version = $db_modules->{$db}->{'db_version'};
    print SUBSTS '.. |min-' . $name . '-ver| replace:: ' . $version . "\n";
    print SUBSTS '.. |min-' . lc($db) . '-ver| replace:: ' . $db_version . "\n";
}

print SUBSTS '"""';

close(SUBSTS);

###############################################################################
# Subs
###############################################################################

sub MakeDocs {
    my ($name, $cmdline) = @_;

    say "Creating $name documentation ..." if defined $name;
    say "$cmdline\n";
    system $cmdline;
    print "\n";
}

sub make_pod {
    say "Creating API documentation...";

    my $converter = Pod::Simple::HTMLBatch::Bugzilla->new;
    # Don't output progress information.
    $converter->verbose(0);
    $converter->html_render_class('Pod::Simple::HTML::Bugzilla');

    my $doctype      = Pod::Simple::HTML::Bugzilla->DOCTYPE;
    my $content_type = Pod::Simple::HTML::Bugzilla->META_CT;
    my $bz_version   = BUGZILLA_VERSION;

    my $contents_start = <<END_HTML;
$doctype
<html>
  <head>
    $content_type
    <title>Bugzilla $bz_version API Documentation</title>
  </head>
  <body class="contentspage">
    <h1>Bugzilla $bz_version API Documentation</h1>
END_HTML

    $converter->contents_page_start($contents_start);
    $converter->contents_page_end("</body></html>");
    $converter->add_css('./../../../style.css');
    $converter->javascript_flurry(0);
    $converter->css_flurry(0);
    mkdir("html");
    mkdir("html/api");
    $converter->batch_convert(['../../'], 'html/api/');

    print "\n";
}

###############################################################################
# Make the docs ...
###############################################################################

my @langs;
# search for sub directories which have a 'rst' sub-directory
opendir(LANGS, './');
foreach my $dir (readdir(LANGS)) {
    next if (($dir eq '.') || ($dir eq '..') || (! -d $dir));
    if (-d "$dir/rst") {
        push(@langs, $dir);
    }
}
closedir(LANGS);

my $docparent = getcwd();
foreach my $lang (@langs) {
    chdir "$docparent/$lang";

    make_pod() if $pod_simple;

    next if grep { $_ eq '--pod-only' } @ARGV;

    MakeDocs('HTML', 'make html');
    MakeDocs('TXT', 'make text');

    if (grep { $_ eq '--with-pdf' } @ARGV) {
        if (which('pdflatex')) {
            MakeDocs('PDF', 'make latexpdf');
        }
        elsif (which('rst2pdf')) {
            rmtree('pdf', 0, 1);
            MakeDocs('PDF', 'make pdf');
        }
        else {
            say 'pdflatex or rst2pdf not found. Skipping PDF file creation';
        }
    }
}
