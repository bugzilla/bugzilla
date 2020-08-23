use 5.008001;
use strict;
use warnings;

package CPAN::Common::Index;
# ABSTRACT: Common library for searching CPAN modules, authors and distributions

our $VERSION = '0.010';

use Carp ();

use Class::Tiny;

#--------------------------------------------------------------------------#
# Document abstract methods
#--------------------------------------------------------------------------#

#pod =method search_packages (ABSTRACT)
#pod
#pod     $result = $index->search_packages( { package => "Moose" });
#pod     @result = $index->search_packages( \%advanced_query );
#pod
#pod Searches the index for a package such as listed in the CPAN
#pod F<02packages.details.txt> file.  The query must be provided as a hash
#pod reference.  Valid keys are
#pod
#pod =for :list
#pod * package -- a string, regular expression or code reference
#pod * version -- a version number or code reference
#pod * dist -- a string, regular expression or code reference
#pod
#pod If the query term is a string or version number, the query will be for an exact
#pod match.  If a code reference, the code will be called with the value of the
#pod field for each potential match.  It should return true if it matches.
#pod
#pod Not all backends will implement support for all fields or all types of queries.
#pod If it does not implement either, it should "decline" the query with an empty
#pod return.
#pod
#pod The return should be context aware, returning either a
#pod single result or a list of results.
#pod
#pod The result must be formed as follows:
#pod
#pod     {
#pod       package => 'MOOSE',
#pod       version => '2.0802',
#pod       uri     => "cpan:///distfile/ETHER/Moose-2.0802.tar.gz"
#pod     }
#pod
#pod The C<uri> field should be a valid URI.  It may be a L<URI::cpan> or any other
#pod URI.  (It is up to a client to do something useful with any given URI scheme.)
#pod
#pod =method search_authors (ABSTRACT)
#pod
#pod     $result = $index->search_authors( { id => "DAGOLDEN" });
#pod     @result = $index->search_authors( \%advanced_query );
#pod
#pod Searches the index for author data such as from the CPAN F<01mailrc.txt> file.
#pod The query must be provided as a hash reference.  Valid keys are
#pod
#pod =for :list
#pod * id -- a string, regular expression or code reference
#pod * fullname -- a string, regular expression or code reference
#pod * email -- a string, regular expression or code reference
#pod
#pod If the query term is a string, the query will be for an exact match.  If a code
#pod reference, the code will be called with the value of the field for each
#pod potential match.  It should return true if it matches.
#pod
#pod Not all backends will implement support for all fields or all types of queries.
#pod If it does not implement either, it should "decline" the query with an empty
#pod return.
#pod
#pod The return should be context aware, returning either a single result or a list
#pod of results.
#pod
#pod The result must be formed as follows:
#pod
#pod     {
#pod         id       => 'DAGOLDEN',
#pod         fullname => 'David Golden',
#pod         email    => 'dagolden@cpan.org',
#pod     }
#pod
#pod The C<email> field may not reflect an actual email address.  The 01mailrc file
#pod on CPAN often shows "CENSORED" when email addresses are concealed.
#pod
#pod =cut

#--------------------------------------------------------------------------#
# stub methods
#--------------------------------------------------------------------------#

#pod =method index_age
#pod
#pod     $epoch = $index->index_age;
#pod
#pod Returns the modification time of the index in epoch seconds.  This may not make sense
#pod for some backends.  By default it returns the current time.
#pod
#pod =cut

sub index_age { time }

#pod =method refresh_index
#pod
#pod     $index->refresh_index;
#pod
#pod This ensures the index source is up to date.  For example, a remote
#pod mirror file would be re-downloaded.  By default, it does nothing.
#pod
#pod =cut

sub refresh_index { 1 }

#pod =method attributes
#pod
#pod Return attributes and default values as a hash reference.  By default
#pod returns an empty hash reference.
#pod
#pod =cut

sub attributes { {} }

#pod =method validate_attributes
#pod
#pod     $self->validate_attributes;
#pod
#pod This is called by the constructor to validate any arguments.  Subclasses
#pod should override the default one to perform validation.  It should not be
#pod called by application code.  By default, it does nothing.
#pod
#pod =cut

sub validate_attributes { 1 }

1;


# vim: ts=4 sts=4 sw=4 et:

__END__

=pod

=encoding UTF-8

=head1 NAME

CPAN::Common::Index - Common library for searching CPAN modules, authors and distributions

=head1 VERSION

version 0.010

=head1 SYNOPSIS

    use CPAN::Common::Index::Mux::Ordered;
    use Data::Dumper;

    $index = CPAN::Common::Index::Mux::Ordered->assemble(
        MetaDB => {},
        Mirror => { mirror => "http://cpan.cpantesters.org" },
    );

    $result = $index->search_packages( { package => "Moose" } );

    print Dumper($result);

    # {
    #   package => 'MOOSE',
    #   version => '2.0802',
    #   uri     => "cpan:///distfile/ETHER/Moose-2.0802.tar.gz"
    # }

=head1 DESCRIPTION

This module provides a common library for working with a variety of CPAN index
services.  It is intentionally minimalist, trying to use as few non-core
modules as possible.

The C<CPAN::Common::Index> module is an abstract base class that defines a
common API.  Individual backends deliver the API for a particular index.

As shown in the SYNOPSIS, one interesting application is multiplexing -- using
different index backends, querying each in turn, and returning the first
result.

=head1 METHODS

=head2 search_packages (ABSTRACT)

    $result = $index->search_packages( { package => "Moose" });
    @result = $index->search_packages( \%advanced_query );

Searches the index for a package such as listed in the CPAN
F<02packages.details.txt> file.  The query must be provided as a hash
reference.  Valid keys are

=over 4

=item *

package -- a string, regular expression or code reference

=item *

version -- a version number or code reference

=item *

dist -- a string, regular expression or code reference

=back

If the query term is a string or version number, the query will be for an exact
match.  If a code reference, the code will be called with the value of the
field for each potential match.  It should return true if it matches.

Not all backends will implement support for all fields or all types of queries.
If it does not implement either, it should "decline" the query with an empty
return.

The return should be context aware, returning either a
single result or a list of results.

The result must be formed as follows:

    {
      package => 'MOOSE',
      version => '2.0802',
      uri     => "cpan:///distfile/ETHER/Moose-2.0802.tar.gz"
    }

The C<uri> field should be a valid URI.  It may be a L<URI::cpan> or any other
URI.  (It is up to a client to do something useful with any given URI scheme.)

=head2 search_authors (ABSTRACT)

    $result = $index->search_authors( { id => "DAGOLDEN" });
    @result = $index->search_authors( \%advanced_query );

Searches the index for author data such as from the CPAN F<01mailrc.txt> file.
The query must be provided as a hash reference.  Valid keys are

=over 4

=item *

id -- a string, regular expression or code reference

=item *

fullname -- a string, regular expression or code reference

=item *

email -- a string, regular expression or code reference

=back

If the query term is a string, the query will be for an exact match.  If a code
reference, the code will be called with the value of the field for each
potential match.  It should return true if it matches.

Not all backends will implement support for all fields or all types of queries.
If it does not implement either, it should "decline" the query with an empty
return.

The return should be context aware, returning either a single result or a list
of results.

The result must be formed as follows:

    {
        id       => 'DAGOLDEN',
        fullname => 'David Golden',
        email    => 'dagolden@cpan.org',
    }

The C<email> field may not reflect an actual email address.  The 01mailrc file
on CPAN often shows "CENSORED" when email addresses are concealed.

=head2 index_age

    $epoch = $index->index_age;

Returns the modification time of the index in epoch seconds.  This may not make sense
for some backends.  By default it returns the current time.

=head2 refresh_index

    $index->refresh_index;

This ensures the index source is up to date.  For example, a remote
mirror file would be re-downloaded.  By default, it does nothing.

=head2 attributes

Return attributes and default values as a hash reference.  By default
returns an empty hash reference.

=head2 validate_attributes

    $self->validate_attributes;

This is called by the constructor to validate any arguments.  Subclasses
should override the default one to perform validation.  It should not be
called by application code.  By default, it does nothing.

=for Pod::Coverage method_names_here

=for :stopwords cpan testmatrix url annocpan anno bugtracker rt cpants kwalitee diff irc mailto metadata placeholders metacpan

=head1 SUPPORT

=head2 Bugs / Feature Requests

Please report any bugs or feature requests through the issue tracker
at L<https://github.com/Perl-Toolchain-Gang/CPAN-Common-Index/issues>.
You will be notified automatically of any progress on your issue.

=head2 Source Code

This is open source software.  The code repository is available for
public review and contribution under the terms of the license.

L<https://github.com/Perl-Toolchain-Gang/CPAN-Common-Index>

  git clone https://github.com/Perl-Toolchain-Gang/CPAN-Common-Index.git

=head1 AUTHOR

David Golden <dagolden@cpan.org>

=head1 CONTRIBUTORS

=for stopwords David Golden Helmut Wollmersdorfer Kenichi Ishigaki Shoichi Kaji Tatsuhiko Miyagawa

=over 4

=item *

David Golden <xdg@xdg.me>

=item *

Helmut Wollmersdorfer <helmut@wollmersdorfer.at>

=item *

Kenichi Ishigaki <ishigaki@cpan.org>

=item *

Shoichi Kaji <skaji@cpan.org>

=item *

Tatsuhiko Miyagawa <miyagawa@bulknews.net>

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2013 by David Golden.

This is free software, licensed under:

  The Apache License, Version 2.0, January 2004

=cut
