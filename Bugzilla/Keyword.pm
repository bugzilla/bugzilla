# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Keyword;

use 5.14.0;
use strict;
use warnings;

use parent qw(Bugzilla::Object);

use Bugzilla::Error;
use Bugzilla::Util;

###############################
####    Initialization     ####
###############################

use constant IS_CONFIG => 1;

use constant DB_COLUMNS => qw(
  keyworddefs.id
  keyworddefs.name
  keyworddefs.description
  keyworddefs.is_active
);

use constant DB_TABLE => 'keyworddefs';

use constant VALIDATORS => {
  name        => \&_check_name,
  description => \&_check_description,
  is_active   => \&_check_is_active,
};

use constant UPDATE_COLUMNS => qw(
  name
  description
  is_active
);

###############################
####      Accessors      ######
###############################

sub description { return $_[0]->{'description'}; }

sub bug_count {
  my ($self) = @_;
  return $self->{'bug_count'} if defined $self->{'bug_count'};
  ($self->{'bug_count'})
    = Bugzilla->dbh->selectrow_array(
    'SELECT COUNT(*) FROM keywords WHERE keywordid = ?',
    undef, $self->id);
  return $self->{'bug_count'};
}

###############################
####       Mutators       #####
###############################

sub set_name        { $_[0]->set('name',        $_[1]); }
sub set_description { $_[0]->set('description', $_[1]); }
sub set_is_active   { $_[0]->set('is_active',   $_[1]); }

###############################
####      Subroutines    ######
###############################

sub get_all_with_bug_count {
  my $class    = shift;
  my $dbh      = Bugzilla->dbh;
  my $keywords = $dbh->selectall_arrayref(
    'SELECT ' . join(', ', $class->_get_db_columns) . ',
                                       COUNT(keywords.bug_id) AS bug_count
                                  FROM keyworddefs
                             LEFT JOIN keywords
                                    ON keyworddefs.id = keywords.keywordid '
      . $dbh->sql_group_by(
      'keyworddefs.id', 'keyworddefs.name,
                                                      keyworddefs.description'
      ) . '
                                 ORDER BY keyworddefs.name',
    {'Slice' => {}}
  );
  if (!$keywords) {
    return [];
  }

  foreach my $keyword (@$keywords) {
    bless($keyword, $class);
  }
  return $keywords;
}

###############################
###       Validators        ###
###############################

sub _check_name {
  my ($self, $name) = @_;

  $name = trim($name);
  if (!defined $name or $name eq "") {
    ThrowUserError("keyword_blank_name");
  }
  if ($name =~ /[\s,]/) {
    ThrowUserError("keyword_invalid_name");
  }

  # We only want to validate the non-existence of the name if
  # we're creating a new Keyword or actually renaming the keyword.
  if (!ref($self) || lc($self->name) ne lc($name)) {
    my $keyword = new Bugzilla::Keyword({name => $name});
    ThrowUserError("keyword_already_exists", {name => $name}) if $keyword;
  }

  return $name;
}

sub _check_description {
  my ($self, $desc) = @_;
  $desc = trim($desc);
  if (!defined $desc or $desc eq '') {
    ThrowUserError("keyword_blank_description");
  }
  return $desc;
}

sub _check_is_active { return $_[1] ? 1 : 0 }

sub is_active { return $_[0]->{is_active} }

1;

__END__

=head1 NAME

Bugzilla::Keyword - A Keyword that can be added to a bug.

=head1 SYNOPSIS

 use Bugzilla::Keyword;

 my $description = $keyword->description;

 my $keywords = Bugzilla::Keyword->get_all_with_bug_count();

=head1 DESCRIPTION

Bugzilla::Keyword represents a keyword that can be added to a bug.

This implements all standard C<Bugzilla::Object> methods. See
L<Bugzilla::Object> for more details.

=head1 METHODS

This is only a list of methods specific to C<Bugzilla::Keyword>.
See L<Bugzilla::Object> for more methods that this object
implements.

=over

=item C<get_all_with_bug_count()> 

 Description: Returns all defined keywords. This is an efficient way
              to get the associated bug counts, as only one SQL query
              is executed with this method, instead of one per keyword
              when calling get_all and then bug_count.
 Params:      none
 Returns:     A reference to an array of Keyword objects, or an empty
              arrayref if there are no keywords.

=item C<is_active>

 Description: Indicates if the keyword may be used on a bug
 Params:      none
 Returns:     a boolean value that is true if the keyword can be applied to bugs.

=item C<set_is_active($is_active)>

 Description: Set the is_active property to a boolean value
 Params:      the new value of the is_active property.
 Returns:     nothing

=back

=cut

=head1 B<Methods in need of POD>

=over

=item set_description

=item bug_count

=item set_name

=item description

=back
