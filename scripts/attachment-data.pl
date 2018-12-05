#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use strict;
use warnings;
use 5.10.1;

use File::Basename;
use File::Spec;

BEGIN {
  require lib;
  my $dir = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));
  lib->import(
    $dir,
    File::Spec->catdir($dir, 'lib'),
    File::Spec->catdir($dir, qw(local lib perl5))
  );
}

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Attachment;
use Bugzilla::Attachment::Archive;
use Getopt::Long;
use Pod::Usage;

BEGIN { Bugzilla->extensions }

# set Bugzilla usage mode to USAGE_MODE_CMDLINE
Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my ($help, $file);
GetOptions('help|h' => \$help, 'file|f=s' => \$file,);
pod2usage(1) if $help || !$file;

my $archive = Bugzilla::Attachment::Archive->new(file => $file);
my $cmd = shift @ARGV;

if ($cmd eq 'export') {
  while (my $attach_id = <ARGV>) {
    chomp $attach_id;
    my $attachment = Bugzilla::Attachment->new($attach_id);
    unless ($attachment) {
      warn "No attachment: $attach_id\n";
      next;
    }
    warn "writing $attach_id\n";
    $archive->write_attachment($attachment);
  }
  $archive->write_checksum;
}
elsif ($cmd eq 'import') {
  while (my $mem = $archive->read_member) {
    warn "read $mem->{attach_id}\n";

    my $attachment = Bugzilla::Attachment->new($mem->{attach_id});
    next unless $mem->{data_len};
    next unless check_attachment($attachment, $mem->{bug_id}, $mem->{data_len});

    Bugzilla::Attachment::current_storage()->store($attachment->id, $mem->{data});
  }
}
elsif ($cmd eq 'check') {
  while (my $mem = $archive->read_member()) {
    warn "checking $mem->{attach_id}\n";
    my $attachment = Bugzilla::Attachment->new($mem->{attach_id});
    next unless $mem->{data_len};
    die "bad attachment\n"
      unless check_attachment($attachment, $mem->{bug_id}, $mem->{data_len});
  }
}
elsif ($cmd eq 'remove') {
  my %remove_ok;
  while (my $mem = $archive->read_member) {
    warn "checking $mem->{attach_id}\n";

    my $attachment = Bugzilla::Attachment->new($mem->{attach_id});
    die "bad attachment\n"
      unless check_attachment($attachment, $mem->{bug_id}, $mem->{data_len});
    $remove_ok{$mem->{attach_id}} = 1;
  }
  while (my $attach_id = <ARGV>) {
    chomp $attach_id;
    if ($remove_ok{$attach_id}) {
      warn "removing $attach_id\n";
      Bugzilla::Attachment::current_storage()->remove($attach_id);
    }
    else {
      warn "Unable to remove $attach_id, as it did not occur in the archive.\n";
    }
  }
}

sub check_attachment {
  my ($attachment, $bug_id, $data_len) = @_;

  unless ($attachment) {
    warn "No attachment found. Skipping record.\n";
    return 0;
  }
  unless ($attachment->bug_id == $bug_id) {
    warn 'Wrong bug id (should be ' . $attachment->bug_id . ")\n";
    return 0;
  }
  unless ($attachment->datasize == $data_len) {
    warn 'Wrong size (should be ' . $attachment->datasize . ")\n";
    return 0;
  }

  return 1;
}


__DATA__

=head1 NAME

attachment-data.pl - import, export, and purge attachment data

=head1 SYNOPSIS

    ./scripts/attachment-data.pl export -f attachments.dat < attachment-ids.txt
    ./scripts/attachment-data.pl remove -f attachments.dat < attachment-ids.txt
    ./scripts/attachment-data.pl import -f attachments.dat


=head1 SEE ALSO

L<./scripts/attachment-export.pl>


