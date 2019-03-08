# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Model;
use Mojo::Base 'DBIx::Class::Schema';

__PACKAGE__->load_namespaces(default_resultset_class => 'ResultSet');
__PACKAGE__->load_components('Helper::Schema::QuoteNames');

1;

=head1 NAME

Bugzilla::Model - a DBIx::Class::Schema for Bugzilla

=head1 SYNOPSIS

  my $model      = Bugzilla->dbh->model;
  my $firefox_rs = $model->resultset('Bug')->search({'product.name' => 'Firefox'},
    {join => ['product', {bug_keywords => 'keyword'}]});
  my @report = $firefox_rs->group_by('bug_id')->columns({
    bug_id   => 'bug.bug_id',
    summary  => 'bug.short_desc',
    product  => 'product.name',
    keywords => {group_concat => 'keyword.name'}
  })->hri->all;
  is(
    \@report,
    [
      {
        bug_id   => 1,
        keywords => 'regression,relnote',
        product  => 'Firefox',
        summary  => 'Some bug'
      },
      {
        bug_id   => 2,
        keywords => undef,
        product  => 'Firefox',
        summary  => 'some other bug'
      }
    ]
  );

=head1 SEE ALSO

See L<DBIx::Class> and L<DBIx::Class::Helper::ResultSet::Shortcut> for more examples of usage.
