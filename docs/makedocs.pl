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
use File::Find;
use File::Copy;

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

use Bugzilla::Constants qw(BUGZILLA_VERSION);

use File::Path qw(rmtree);
use File::Which qw(which);

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

    # Collect up local extension documentation into the extensions/ dir.
    sub wanted {
        if ($File::Find::dir =~ /\/doc\/?$/ &&
            $_ =~ /\.rst$/)
        {
            copy($File::Find::name, "rst/extensions");
        }
    };

    # Clear out old extensions docs
    rmtree('rst/extensions', 0, 1);
    mkdir('rst/extensions');
    
    find({
        'wanted' => \&wanted,
        'no_chdir' => 1,
    }, "$docparent/../extensions");

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

    rmtree('doctrees', 0, 1);
}
