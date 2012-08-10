# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Extension::ProductDashboard::Util;

use strict;

use base qw(Exporter);
@Bugzilla::Extension::ProductDashboard::Util::EXPORT = qw(
    bug_link_all
    bug_link_open
    bug_link_closed
    open_states
    closed_states
    quoted_open_states
    quoted_closed_states
    filter_bugs
    bug_milestone_link_total
    bug_milestone_link_open
    bug_milestone_link_closed
);

use Bugzilla::Status;
use Bugzilla::Util;

use Bugzilla::Status;

our $_open_states;
sub open_states {
    $_open_states ||= Bugzilla::Status->match({ is_open => 1, isactive => 1 });
    return wantarray ? @$_open_states : $_open_states;
}

our $_quoted_open_states;
sub quoted_open_states {
    my $dbh = Bugzilla->dbh;
    $_quoted_open_states ||= [ map { $dbh->quote($_->name) } open_states() ];
    return wantarray ? @$_quoted_open_states : $_quoted_open_states;
}

our $_closed_states;
sub closed_states {
    $_closed_states ||= Bugzilla::Status->match({ is_open => 0, isactive => 1 });
    return wantarray ? @$_closed_states : $_closed_states;
}

our $_quoted_closed_states;
sub quoted_closed_states {
    my $dbh = Bugzilla->dbh;
    $_quoted_closed_states ||= [ map { $dbh->quote($_->name) } closed_states() ];
    return wantarray ? @$_quoted_closed_states : $_quoted_closed_states;
}

sub bug_link_all {
    my $product = shift;

    return correct_urlbase() . 'buglist.cgi?product=' . url_quote($product->name);
}

sub bug_link_open {
    my $product = shift;

    return correct_urlbase() . 'buglist.cgi?product=' . url_quote($product->name) . 
        "&bug_status=__open__";
}

sub bug_link_closed {
    my $product = shift;

    return correct_urlbase() . 'buglist.cgi?product=' . url_quote($product->name) . 
        "&bug_status=__closed__";
}

sub bug_milestone_link_total {
    my ($product, $milestone) = @_;

    return correct_urlbase() . 'buglist.cgi?product=' . url_quote($product->name) . 
        "&target_milestone=" . url_quote($milestone->name);
}

sub bug_milestone_link_open {
    my ($product, $milestone) = @_;

    return correct_urlbase() . 'buglist.cgi?product=' . url_quote($product->name) . 
        "&target_milestone=" . url_quote($milestone->name) . "&bug_status=__open__";
}

sub bug_milestone_link_closed {
    my ($product, $milestone) = @_;

    return correct_urlbase() . 'buglist.cgi?product=' . url_quote($product->name) . 
        "&target_milestone=" . url_quote($milestone->name) . "&bug_status=__closed__";
}

sub filter_bugs {
    my ($unfiltered_bugs) = @_;
    my $dbh = Bugzilla->dbh;

    # Filter out which bugs that cannot be viewed
    my $params = Bugzilla::CGI->new({ bug_id => [ map { $_->{'id'} } @$unfiltered_bugs ] });
    my $search = Bugzilla::Search->new(fields => ['bug_id' ], params => $params );
    my %filtered_bug_ids = map { $_ => 1 } @{$dbh->selectcol_arrayref($search->getSQL())};

    my @filtered_bugs;
    foreach my $bug (@$unfiltered_bugs) {
        next if !$filtered_bug_ids{$bug->{'id'}};
        push(@filtered_bugs, $bug);
    }

    return \@filtered_bugs;
}

1;
