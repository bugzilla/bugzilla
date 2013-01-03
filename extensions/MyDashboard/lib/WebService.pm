# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Extension::MyDashboard::WebService;

use strict;
use warnings;

use base qw(Bugzilla::WebService Bugzilla::WebService::Bug);

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Util qw(detaint_natural trick_taint);
use Bugzilla::WebService::Util qw(validate);

use Bugzilla::Extension::MyDashboard::Queries qw(QUERY_DEFS query_bugs query_flags);

use constant READ_ONLY => qw(
    prod_comp_search
    run_bug_query
    run_flag_query
);

sub prod_comp_search {
    my ($self, $params) = @_;
    my $user = Bugzilla->user;
    my $dbh = Bugzilla->switch_to_shadow_db();

    my $search = $params->{'search'};
    $search || ThrowCodeError('param_required',
        { function => 'Bug.prod_comp_search', param => 'search' });

    my $limit = detaint_natural($params->{'limit'}) 
                ? $dbh->sql_limit($params->{'limit'}) 
                : '';

    # We do this in the DB directly as we want it to be fast and
    # not have the overhead of loading full product objects

    # All products which the user has "Entry" access to.
    my $enterable_ids = $dbh->selectcol_arrayref(
           'SELECT products.id FROM products
         LEFT JOIN group_control_map
                   ON group_control_map.product_id = products.id
                      AND group_control_map.entry != 0
                      AND group_id NOT IN (' . $user->groups_as_string . ')
            WHERE group_id IS NULL
                  AND products.isactive = 1');

    if (scalar @$enterable_ids) {
        # And all of these products must have at least one component
        # and one version.
        $enterable_ids = $dbh->selectcol_arrayref(
            'SELECT DISTINCT products.id FROM products
              WHERE ' . $dbh->sql_in('products.id', $enterable_ids) .
              ' AND products.id IN (SELECT DISTINCT components.product_id
                                      FROM components
                                     WHERE components.isactive = 1)
                AND products.id IN (SELECT DISTINCT versions.product_id
                                      FROM versions
                                     WHERE versions.isactive = 1)');
    }

    return { products => [] } if !scalar @$enterable_ids;

    my @list;
    foreach my $word (split(/[\s,]+/, $search)) {
        if ($word ne "") {
            my $sql_word = $dbh->quote($word);
            trick_taint($sql_word);
            # XXX CONCAT_WS is MySQL specific
            my $field = "CONCAT_WS(' ', products.name, components.name, components.description)";
            push(@list, $dbh->sql_iposition($sql_word, $field) . " > 0");
        }
    }

    my $products = $dbh->selectall_arrayref("
        SELECT products.name AS product,
               components.name AS component
          FROM products 
               INNER JOIN components ON products.id = components.product_id
         WHERE (" . join(" AND ", @list) . ")
               AND products.id IN (" . join(",", @$enterable_ids) . ")
      ORDER BY products.name $limit", 
        { Slice => {} });

    return { products => $products };
}

sub run_bug_query {
    my($self, $params) = @_;
    my $dbh = Bugzilla->dbh;
    my $user = Bugzilla->login(LOGIN_REQUIRED);

    defined $params->{query}
        || ThrowCodeError('param_required',
                          { function => 'MyDashboard.run_bug_query',
                            param    => 'query' });

    my $result;
    foreach my $qdef (QUERY_DEFS) {
        next if $qdef->{name} ne $params->{query};
        my ($bugs, $query_string) = query_bugs($qdef);
        
        # Add last changes to each bug
        foreach my $b (@$bugs) {
            my $last_changes = {};
            my $activity = $self->history({ ids => [ $b->{bug_id} ], 
                                           start_time => $b->{changeddate} });
            if (@{$activity->{bugs}[0]{history}}) {
                $last_changes->{activity} = $activity->{bugs}[0]{history}[0]{changes};
                $last_changes->{email} = $activity->{bugs}[0]{history}[0]{who};
                $last_changes->{when} = $activity->{bugs}[0]{history}[0]{when};
            }
            my $last_comment_id = $dbh->selectrow_array("
                SELECT comment_id FROM longdescs 
                WHERE bug_id = ? AND bug_when >= ?",
                undef, $b->{bug_id}, $b->{changeddate});
            if ($last_comment_id) {
                my $comments = $self->comments({ comment_ids => [ $last_comment_id ] });
                $last_changes->{comment} = $comments->{comments}{$last_comment_id}{text};
                $last_changes->{email} = $comments->{comments}{$last_comment_id}{creator} if !$last_changes->{email};
                $last_changes->{when} = $comments->{comments}{$last_comment_id}{creation_time} if !$last_changes->{when};
            }
            $b->{last_changes} = $last_changes;
        }
        
        $query_string =~ s/^POSTDATA=&//;
        $qdef->{bugs}   = $bugs;
        $qdef->{buffer} = $query_string;
        $result = $qdef;
        last;
    }

    return { result => $result };
}

sub run_flag_query {
    my ($self, $params) =@_;
    my $user = Bugzilla->login(LOGIN_REQUIRED);

    defined $params->{type}
        || ThrowCodeError('param_required',
                         { function => 'MyDashboard.run_flag_query',
                           param    => 'type' });

    my $type = $params->{type};
    my $results = query_flags($type);

    return { result => { $type => $results }};
}

1;

__END__

=head1 NAME

Bugzilla::Extension::MyDashboard::Webservice - The MyDashboard WebServices API

=head1 DESCRIPTION

This module contains API methods that are useful to user's of bugzilla.mozilla.org.

=head1 METHODS

See L<Bugzilla::WebService> for a description of how parameters are passed, 
and what B<STABLE>, B<UNSTABLE>, and B<EXPERIMENTAL> mean.
