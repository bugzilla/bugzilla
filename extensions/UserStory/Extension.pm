# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::UserStory;
use strict;
use warnings;

use base qw(Bugzilla::Extension);
our $VERSION = '1';

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Extension::UserStory::Constants;
use Text::Diff;

BEGIN {
    *Bugzilla::Product::user_story_group = \&_product_user_story_group;
}

sub _product_user_story_group {
    my ($self) = @_;
    return USER_STORY_PRODUCTS->{$self->name};
}

# ensure user is allowed to edit the story
sub bug_check_can_change_field {
    my ($self, $args) = @_;
    my ($bug, $field, $priv_results) = @$args{qw(bug field priv_results)};
    return unless $field eq 'cf_user_story';

    my $user = Bugzilla->user;
    my $group = $bug->product_obj->user_story_group()
        || return;
    if (!$user->in_group($group)) {
        push (@$priv_results, PRIVILEGES_REQUIRED_EMPOWERED);
    }
}

# store just a diff of the changes in the bugs_activity table
sub bug_update_before_logging {
    my ($self, $args) = @_;
    my $changes = $args->{changes};
    return unless exists $changes->{cf_user_story};
    my $diff = diff(
        \$changes->{cf_user_story}->[0],
        \$changes->{cf_user_story}->[1],
        {
            CONTEXT => 0,
        },
    );
    $changes->{cf_user_story} = [ '', $diff ];
}

# stop inline-history from displaying changes to the user story
sub inline_history_activtiy {
    my ($self, $args) = @_;
    foreach my $activity (@{ $args->{activity} }) {
        foreach my $change (@{ $activity->{changes} }) {
            if ($change->{fieldname} eq 'cf_user_story') {
                $change->{removed} = '';
                $change->{added} = '(updated)';
            }
        }
    }
}

# create cf_user_story field
sub install_update_db {
    my ($self, $args) = @_;
    return if Bugzilla::Field->new({ name => 'cf_user_story'});
    Bugzilla::Field->create({
        name        => 'cf_user_story',
        description => 'User Story',
        type        => FIELD_TYPE_TEXTAREA,
        mailhead    => 0,
        enter_bug   => 0,
        obsolete    => 0,
        custom      => 1,
        buglist     => 0,
    });
}

__PACKAGE__->NAME;
