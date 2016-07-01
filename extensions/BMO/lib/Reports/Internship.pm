# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BMO::Reports::Internship;

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
                                            object => 'internship_dashboard' });

    my $product   = Bugzilla::Product->check({ name => 'Recruiting', cache => 1 });
    my $component = Bugzilla::Component->new({ product => $product, name => 'Intern', cache => 1 });

    # find all open internship bugs
    my $bugs = Bugzilla::Bug->match({
        product_id   => $product->id,
        component_id => $component->id,
        resolution   => '',
    });

    # filter bugs based on visibility and re-bless
    $user->visible_bugs($bugs);
    $bugs = [
        map  { bless($_, 'InternshipBug') }
        grep { $user->can_see_bug($_->id) }
        @$bugs
    ];

    $vars->{bugs} = $bugs;
}

1;

package InternshipBug;
use strict;
use warnings;

use base qw(Bugzilla::Bug);

use Bugzilla::Comment;
use Bugzilla::Util qw(trim);

sub _extract {
    my ($self) = @_;
    return if exists $self->{internship_data};
    $self->{internship_data} = {};

    # we only need the first comment
    my $comment = Bugzilla::Comment->match({
        bug_id => $self->id,
        LIMIT  => 1,
    })->[0]->body;

    # extract just what we need
    # changing the comment will break this

    if ($comment =~ /Hiring Manager:\s+(.+)\nTeam:\n/s) {
        $self->{internship_data}->{hiring_manager} = trim($1);
    }
    if ($comment =~ /\nVP Authority:\s+(.+)\nProduct Line:\n/s) {
        $self->{internship_data}->{scvp} = trim($1);
    }
    if ($comment =~ /\nProduct Line:\s+(.+)\nLevel 1/s) {
        $self->{internship_data}->{product_line} = trim($1);
    }
    if ($comment =~ /\nBusiness Need:\s+(.+)\nPotential Project:\n/s) {
        $self->{internship_data}->{business_need} = trim($1);
    }
    if ($comment =~ /\nName:\s+(.+)$/s) {
        $self->{internship_data}->{intern_name} = trim($1);
    }
}

sub hiring_manager {
    my ($self) = @_;
    $self->_extract();
    return $self->{internship_data}->{hiring_manager};
}

sub scvp {
    my ($self) = @_;
    $self->_extract();
    return $self->{internship_data}->{scvp};
}

sub business_need {
    my ($self) = @_;
    $self->_extract();
    return $self->{internship_data}->{business_need};
}

sub product_line {
    my ($self) = @_;
    $self->_extract();
    return $self->{internship_data}->{product_line};
}

sub intern_name {
    my ($self) = @_;
    $self->_extract();
    return $self->{internship_data}->{intern_name};
}

1;
