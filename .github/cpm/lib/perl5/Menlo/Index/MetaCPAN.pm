use 5.008001;
use strict;
use warnings;

package Menlo::Index::MetaCPAN;
# ABSTRACT: Search index via MetaCPAN
# VERSION

use parent 'CPAN::Common::Index';

use Class::Tiny qw/uri include_dev/;

use Carp;
use HTTP::Tinyish;
use JSON::PP ();
use Time::Local ();

sub BUILD {
    my $self = shift;
    my $uri  = $self->uri;
    $uri = "https://fastapi.metacpan.org/v1/download_url/"
      unless defined $uri;
    # ensure URI ends in '/'
    $uri =~ s{/?$}{/};
    $self->uri($uri);
    return;
}

sub search_packages {
    my ( $self, $args ) = @_;
    Carp::croak("Argument to search_packages must be hash reference")
      unless ref $args eq 'HASH';

    my $range;
    if ( $args->{version} ) {
        $range = "== $args->{version}";
    } elsif ( $args->{version_range} ) {
        $range = $args->{version_range};
    }
    my %query = (
        ($self->include_dev ? (dev => 1) : ()),
        ($range ? (version => $range) : ()),
    );
    my $query = join "&", map { "$_=" . $self->_uri_escape($query{$_}) } sort keys %query;

    my $uri = $self->uri . $args->{package} . ($query ? "?$query" : "");
    my $res = HTTP::Tinyish->new->get($uri);
    return unless $res->{success};

    my $dist_meta = eval { JSON::PP::decode_json($res->{content}) };
    if ($dist_meta && $dist_meta->{download_url}) {
        (my $distfile = $dist_meta->{download_url}) =~ s!.+/authors/id/\w/\w\w/!!;

        return {
            package => $args->{package},
            version => $dist_meta->{version},
            uri => "cpan:///distfile/$distfile",
            download_uri => $self->_download_uri("http://cpan.metacpan.org", $distfile),
        };
    }

    return;
}

sub _parse_date {
    my($self, $date) = @_;
    my @date = $date =~ /^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)$/;
    Time::Local::timegm($date[5], $date[4], $date[3], $date[2], $date[1] - 1, $date[0] - 1900);
}

sub _uri_escape {
    my($self, $string) = @_;
    $string =~ s/([^a-zA-Z0-9_\-.])/uc sprintf("%%%02x",ord($1))/eg;
    $string;
}

sub _download_uri {
    my($self, $base, $distfile) = @_;
    join "/", $base, "authors/id", substr($distfile, 0, 1), substr($distfile, 0, 2), $distfile;
}

sub index_age { return time }    # pretend always current

sub search_authors { return }    # not supported

1;

=for Pod::Coverage attributes validate_attributes search_packages search_authors BUILD

=head1 SYNOPSIS

  use CPAN::Common::Index::MetaCPAN;

  $index = CPAN::Common::Index::MetaCPAN->new({ include_dev => 1 });
  $index->search_packages({ package => "Moose", version => "1.1" });
  $index->search_packages({ package => "Moose", version_range => ">= 1.1, < 2" });

=head1 DESCRIPTION

This module implements a CPAN::Common::Index that searches for packages against
the MetaCPAN API.

This backend supports searching modules with a version range (as
specified in L<CPAN::Meta::Spec>) which is translated into MetaCPAN
search query.

There is also a support for I<dev> release search, by passing
C<include_dev> parameter to the index object.

The result may include an optional field C<download_uri> which
suggests a specific mirror URL to download from, which can be
C<backpan.org> if the archive was deleted, or C<cpan.metacpan.org> if
the release date is within 1 day (because some mirrors might not have
synced it yet).

There is no support for searching packages with a regular expression, nor searching authors.

=cut

# vim: ts=4 sts=4 sw=4 et:
