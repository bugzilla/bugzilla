use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

package Tie::Handle::SkipHeader;
# ABSTRACT: Tied handle that hides an RFC822-style header

our $VERSION = '0.004';

use Tie::Handle::Offset;
our @ISA = qw/Tie::Handle::Offset/;

sub TIEHANDLE
{
  my $class = shift;
  pop if ref $_[-1] eq 'HASH'; # we don't take any arguments
  return $class->SUPER::TIEHANDLE(@_);
}

# read to blank/whitespace line and set offset right after
sub OPEN
{
  my $self = shift;
  my $rc = $self->SUPER::OPEN(@_);
  while ( my $line = <$self> ) {
    last if $line =~ /\A\s*\Z/;
  }
  $self->offset( tell($self) );
  return $rc;
}

1;


# vim: ts=2 sts=2 sw=2 et:

__END__

=pod

=encoding UTF-8

=head1 NAME

Tie::Handle::SkipHeader - Tied handle that hides an RFC822-style header

=head1 VERSION

version 0.004

=head1 SYNOPSIS

  use Tie::Handle::SkipHeader;

  tie *FH, 'Tie::Handle::SkipHeader', "<", $filename;

=head1 DESCRIPTION

This subclass of L<Tie::Handle::Offset> automatically hides an email-style
message header.  After opening the file, it reads up to a blank or
white-space-only line and sets the offset to the next byte.

=for Pod::Coverage method_names_here

=head1 AUTHOR

David Golden <dagolden@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2012 by David Golden.

This is free software, licensed under:

  The Apache License, Version 2.0, January 2004

=cut
