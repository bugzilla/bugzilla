#!/usr/bin/perl
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
# 2a) rst2pdf
# or
# 2b) pdflatex, which means the following Debian/Ubuntu packages:
#     * texlive-latex-base
#     * texlive-latex-recommended
#     * texlive-latex-extra
#     * texlive-fonts-recommended
#
# All these TeX packages together are close to a gig :-| But after you've
# installed them, you can remove texlive-latex-extra-doc to save 400MB.

use 5.14.0;
use strict;
use warnings;

use File::Basename;
BEGIN { chdir dirname($0); }

use lib qw(.. ../lib lib ../local/lib/perl5);
use open ':encoding(utf8)';

use Cwd;
use File::Copy::Recursive qw(rcopy);
use File::Path qw(rmtree make_path);
use File::Which qw(which);
use Pod::Simple;
use Pod::ParseLink;

use Bugzilla::Constants qw(BUGZILLA_VERSION bz_locations);
use Pod::Simple::Search;
use Pod::POM::View::Restructured;
use Tie::File;
use File::Spec::Functions qw(:ALL);

###############################################################################
# Subs
###############################################################################

my $error_found = 0;

sub MakeDocs {
  my ($name, $cmdline) = @_;

  say "Creating $name documentation ..." if defined $name;
  system('make', $cmdline) == 0 or $error_found = 1;
  print "\n";
}

# Compile all the POD and make it part of the API docs
# Also duplicate some Extension docs into the User section, Admin section, and
# WebService docs
sub pod2rst {
  my $path = shift;

  say "Converting POD to RST...";
  my $name2path
    = Pod::Simple::Search->new->inc(0)->verbose(0)->survey(@{['../']});

  my $ind_path = catdir($path, 'rst', 'integrating', 'internals');
  rmtree($ind_path);
  make_path($ind_path);

  my $FILE;
  open($FILE, '>', catfile($ind_path, 'index.rst')) || die("Can't open rst file");
  print($FILE <<'EOI');
.. highlight:: perl

.. _developer

===================================
Developer Documentation
===================================

This section exposes the POD for all modules and scripts, including extensions,
in Bugzilla.

.. toctree::
   :maxdepth: 2

EOI

  foreach my $mod (sort keys %$name2path) {

    # Ignoring library files;
    if ($mod =~ /^b?(lib::|local)/) {
      delete $name2path->{$mod};
      next;
    }

    my $title = $mod;

    my $ext = $title =~ s/^extensions:://;
    $title =~ s/lib:://;
    $title =~ s/::Extension$// if ($ext);
    my $header = "=" x length($title);

    my $abs_path = $name2path->{$mod};
    my $fpath = abs2rel($abs_path, '..');
    my ($volume, $directories, $file) = splitpath($fpath);
    $directories =~ s/lib\///;
    $directories = '.' if ($directories eq '');

    my $dir_path = catdir($ind_path, $directories);
    make_path($dir_path);
    $file =~ s/\.[^.]*$//;
    my $out_file = $file . '.rst';
    my $full_out_file = catfile($dir_path, $out_file);

    my $callbacks = {
      link => sub {
        my $text = shift;

        my @results = parselink($text);

        # A link to another page.
        if (defined($results[1]) && defined($results[2])) {
          if ($results[2] =~ /^http/) {
            return ($results[2], $results[1]);
          }
          elsif ($results[2] =~ m/Bugzilla/) {
            my $depth = scalar(split('/', $directories));
            my @split = split('::', $results[2]);
            my $base  = '../' x $depth;
            my $url   = $base . join('/', @split);
            $url .= '.html';
            $url .= '#' . $results[3] if defined $results[3];
            return ($url, $results[1]);
          }
          else {
            # Not a Bugzilla package, link to CPAN.
            my $url = 'http://search.cpan.org/search?query=' . $results[2] . '&mode=all';
            return ($url, $results[1]);
          }
        }

        # A Link within a page
        elsif (defined($results[1]) && defined($results[4])) {
          my $anchor = $results[1];
          $anchor =~ s/"//g;
          return ("#$anchor", $anchor);
        }
        else {
          die "Don't know how to parse $text";
        }
      }
    };
    my $conv = Pod::POM::View::Restructured->new(
      {namespace => $title, callbacks => $callbacks});
    my $rv = $conv->convert_file($abs_path, $title, $full_out_file, $callbacks);
    print($FILE "   ", catfile($directories, $out_file), "\n");

    if ($ext) {
      my $api_path = catdir($path, 'rst', $directories);
      my $adminfile = catfile($api_path, "index-admin.rst");
      my $userfile  = catfile($api_path, "index-user.rst");
      my $apifile   = catfile($api_path, 'api', 'v1', 'index.rst');
      make_path($api_path) unless -d $api_path;

      # Add Core doc to User & Admin guides
      if ($file eq 'Extension') {
        my $FH;
        open($FH, '<', $full_out_file) || die "$full_out_file: $!";
        my @lines = <$FH>;
        close $FH;

        my @array;

        # ensure out of order docs are at the top of the page without
        # playing with file handles
        tie @array, 'Tie::File', $adminfile or die "$adminfile: $!";
        unshift @array, @lines, "", "", ".. toctree::", "", "";
        untie @array;

        tie @array, 'Tie::File', $userfile or die "$userfile: $!";
        unshift @array, @lines, "", "", ".. toctree::", "", "";
        untie @array;

      }

      # Add Config doc to Admin guide
      elsif ($file eq 'Config') {
        rcopy($full_out_file, $api_path);
        `perl -E 'say "   $file.rst"' >> "$adminfile"`;
      }

      # Add WebServices doc to API docs
      elsif ($file eq 'WebService') {
        my $apidir = catdir($api_path, 'api', 'v1');
        make_path($apidir) unless -d $apidir;
        `perl -E 'say ".. toctree::\n\n"' >> $apifile` unless -f $apifile;

        my $FH;
        open($FH, '<', $full_out_file) || die "$full_out_file: $!";
        my @lines = <$FH>;
        close $FH;

        my @array;

        tie @array, 'Tie::File', $apifile or die "$apifile: $!";
        unshift @array, @lines;
        untie @array;
      }
      elsif ($api_path =~ /WebService\/$/) {
        my $apidir = catdir($api_path, '..', 'api', 'v1');
        $apifile = catfile($apidir, 'index.rst');
        make_path($apidir) unless -d $apidir;
        rcopy($full_out_file, $apidir);
        `perl -E 'say ".. toctree::\n\n"' >> $apifile` unless -f $apifile;
        `perl -E 'say "   $file.rst"' >> $apifile`;
      }
    }
  }

  close($FILE);
}

###############################################################################
# Make the docs ...
###############################################################################

my @langs;

# search for sub directories which have a 'rst' sub-directory
opendir(LANGS, './');
foreach my $dir (readdir(LANGS)) {
  next if (($dir eq '.') || ($dir eq '..') || (!-d $dir));
  if (-d "$dir/rst") {
    push(@langs, $dir);
  }
}
closedir(LANGS);

my $docparent = getcwd();
foreach my $lang (@langs) {

  rmtree("$lang/html", 0, 1);
  rmtree("$lang/txt",  0, 1);

  my @sub_dirs = grep {-d} glob("$lang/rst/extensions/*");
  rmtree(@sub_dirs, {verbose => 0, safe => 1});

  pod2rst("$docparent/$lang");

  next if grep { $_ eq '--pod-only' } @ARGV;

  chdir "$docparent/$lang";

  MakeDocs('HTML', 'html');
  MakeDocs('TXT',  'text');

  if (grep { $_ eq '--with-pdf' } @ARGV) {
    if (which('pdflatex')) {
      MakeDocs('PDF', 'latexpdf');
    }
    elsif (which('rst2pdf')) {
      rmtree('pdf', 0, 1);
      MakeDocs('PDF', 'pdf');
    }
    else {
      say 'pdflatex or rst2pdf not found. Skipping PDF file creation';
    }
  }

  rmtree('doctrees', 0, 1);
}

die "Error occurred building the documentation\n" if $error_found;
