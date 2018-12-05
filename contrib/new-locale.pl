#!/usr/bin/perl -w

use File::Find;
use File::Copy::Recursive qw(dircopy);

($ARGV[0] && $ARGV[0] =~ /\w\w(-\w\w)?/) || usage();

sub process {
  if ($_ eq 'en' && $File::Find::name !~ /\/data\//) {
    dircopy($_, $ARGV[0]);
  }
}

find(\&process, ".");

sub usage {
  print "Usage: new-locale.pl <lang code>\n";
  print " e.g.: new-locale.pl fr\n";
}
