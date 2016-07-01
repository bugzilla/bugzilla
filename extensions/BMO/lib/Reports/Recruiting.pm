# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BMO::Reports::Recruiting;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Error;
use Bugzilla::Bug;
use Bugzilla::Product;
use Bugzilla::Component;

sub report {
    my ($vars) = @_;
    my $user = Bugzilla->user;

    $user->in_group('hr')
        || ThrowUserError('auth_failure', { group  => 'hr',
                                            action => 'run',
                                            object => 'recruiting_dashboard' });

    my $product   = Bugzilla::Product->check({ name => 'Recruiting', cache => 1 });
    my $component = Bugzilla::Component->new({ product => $product, name => 'General', cache => 1 });

    # find all open recruiting bugs
    my $bugs = Bugzilla::Bug->match({
        product_id   => $product->id,
        component_id => $component->id,
        resolution   => '',
    });

    # filter bugs based on visibility and re-bless
    $user->visible_bugs($bugs);
    $bugs = [
        map  { bless($_, 'RecruitingBug') }
        grep { $user->can_see_bug($_->id) }
        @$bugs
    ];

    $vars->{bugs} = $bugs;
}

1;

package RecruitingBug;
use strict;
use warnings;

use base qw(Bugzilla::Bug);

use Bugzilla::Comment;
use Bugzilla::Util qw(trim);

sub _extract {
    my ($self) = @_;
    return if exists $self->{recruitment_data};
    $self->{recruitment_data} = {};

    # we only need the first comment
    my $comment = Bugzilla::Comment->match({
        bug_id => $self->id,
        LIMIT  => 1,
    })->[0]->body;

    # extract just what we need
    # changing the comment will break this

    if ($comment =~ /\nHiring Manager:\s+(.+)VP Authority:\n/s) {
        $self->{recruitment_data}->{hiring_manager} = trim($1);
    }
    if ($comment =~ /\nVP Authority:\s+(.+)HRBP:\n/s) {
        $self->{recruitment_data}->{scvp} = trim($1);
    }
    if ($comment =~ /\nWhat part of your strategic plan does this role impact\?\s+(.+)Why is this critical for success\?\n/s) {
        $self->{recruitment_data}->{strategic_plan} = trim($1);
    }
    if ($comment =~ /\nWhy is this critical for success\?\s+(.+)$/s) {
        $self->{recruitment_data}->{why_critical} = trim($1);
    }
}

sub hiring_manager {
    my ($self) = @_;
    $self->_extract();
    return $self->{recruitment_data}->{hiring_manager};
}

sub scvp {
    my ($self) = @_;
    $self->_extract();
    return $self->{recruitment_data}->{scvp};
}

sub strategic_plan {
    my ($self) = @_;
    $self->_extract();
    return $self->{recruitment_data}->{strategic_plan};
}

sub why_critical {
    my ($self) = @_;
    $self->_extract();
    return $self->{recruitment_data}->{why_critical};
}

1;
