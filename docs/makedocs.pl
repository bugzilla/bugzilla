#!/usr/bin/perl -w
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# This script compiles all the documentation.

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

###############################################################################
# Generate minimum version list
###############################################################################

my $modules = REQUIRED_MODULES;
my $opt_modules = OPTIONAL_MODULES;

my $template;
{
    open(TEMPLATE, '<', 'bugzilla.ent.tmpl')
      or die('Could not open bugzilla.ent.tmpl: ' . $!);
    local $/;
    $template = <TEMPLATE>;
    close TEMPLATE;
}
open(ENTITIES, '>', 'bugzilla.ent') or die('Could not open bugzilla.ent: ' . $!);
print ENTITIES "$template\n";
print ENTITIES '<!-- Module Versions -->' . "\n";
foreach my $module (@$modules, @$opt_modules)
{
    my $name = $module->{'module'};
    $name =~ s/::/-/g;
    $name = lc($name);
    #This needs to be a string comparison, due to the modules having
    #version numbers like 0.9.4
    my $version = $module->{'version'} eq 0 ? 'any' : $module->{'version'};
    print ENTITIES '<!ENTITY min-' . $name . '-ver "'.$version.'">' . "\n";
}

print ENTITIES "\n <!-- Database Versions --> \n";

my $db_modules = DB_MODULE;
foreach my $db (keys %$db_modules) {
    my $dbd  = $db_modules->{$db}->{dbd};
    my $name = $dbd->{module};
    $name =~ s/::/-/g;
    $name = lc($name);
    my $version    = $dbd->{version} || 'any';
    my $db_version = $db_modules->{$db}->{'db_version'};
    print ENTITIES '<!ENTITY min-' . $name . '-ver "'.$version.'">' . "\n";
    print ENTITIES '<!ENTITY min-' . lc($db) . '-ver "'.$db_version.'">' . "\n";
}
close(ENTITIES);

###############################################################################
# Subs
###############################################################################

sub MakeDocs {

    my ($name, $cmdline) = @_;

    print "Creating $name documentation ...\n" if defined $name;
    print "$cmdline\n\n";
    system $cmdline;
    print "\n";

}

sub make_pod {

    print "Creating API documentation...\n";

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
    $converter->batch_convert(['../../'], 'html/api/');

    print "\n";
}

###############################################################################
# Make the docs ...
###############################################################################

my @langs;
# search for sub directories which have a 'xml' sub-directory
opendir(LANGS, './');
foreach my $dir (readdir(LANGS)) {
    next if (($dir eq '.') || ($dir eq '..') || (! -d $dir));
    if (-d "$dir/xml") {
        push(@langs, $dir);
    }
}
closedir(LANGS);

my $docparent = getcwd();
foreach my $lang (@langs) {
    chdir "$docparent/$lang";
    MakeDocs(undef, 'cp ../bugzilla.ent ./xml/');

    if (!-d 'txt') {
        unlink 'txt';
        mkdir 'txt', 0755;
    }
    if (!-d 'pdf') {
        unlink 'pdf';
        mkdir 'pdf', 0755;
    }
    if (!-d 'html') {
        unlink 'html';
        mkdir 'html', 0755;
    }
    if (!-d 'html/api') {
        unlink 'html/api';
        mkdir 'html/api', 0755;
    }

    make_pod() if $pod_simple;

    MakeDocs('separate HTML', 'xmlto -m ../xsl/chunks.xsl -o html html xml/Bugzilla-Guide.xml');
    MakeDocs('big HTML', 'xmlto -m ../xsl/nochunks.xsl -o html html-nochunks xml/Bugzilla-Guide.xml');
    MakeDocs('big text', 'lynx -dump -justify=off -nolist html/Bugzilla-Guide.html > txt/Bugzilla-Guide.txt');

    if (! grep($_ eq "--with-pdf", @ARGV)) {
        next;
    }

    MakeDocs('PDF', 'dblatex -p ../xsl/pdf.xsl -o pdf/Bugzilla-Guide.pdf xml/Bugzilla-Guide.xml');
}
