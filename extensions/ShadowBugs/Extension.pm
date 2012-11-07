# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::ShadowBugs;

use strict;

use base qw(Bugzilla::Extension);

use Bugzilla::Bug;
use Bugzilla::Error;
use Bugzilla::Field;
use Bugzilla::User;

our $VERSION = '1';

BEGIN {
    *Bugzilla::is_cf_shadow_bug_hidden = \&_is_cf_shadow_bug_hidden;
    *Bugzilla::Bug::cf_shadow_bug_obj = \&_cf_shadow_bug_obj;
}

# Determine if the shadow-bug / shadowed-by fields are visibile on the
# specified bug.
sub _is_cf_shadow_bug_hidden {
    my ($self, $bug) = @_;

    # completely hide unless you're a member of the right group
    return 1 unless Bugzilla->user->in_group('can_shadow_bugs');

    my $is_public = Bugzilla::User->new()->can_see_bug($bug->id);
    if ($is_public) {
        # hide on public bugs, unless it's shadowed
        my $related = $bug->related_bugs(Bugzilla->process_cache->{shadow_bug_field});
        return 1 if !@$related;
    }
}

sub _cf_shadow_bug_obj {
    my ($self) = @_;
    return unless $self->cf_shadow_bug;
    return $self->{cf_shadow_bug_obj} ||= Bugzilla::Bug->new($self->cf_shadow_bug);
}

sub template_before_process {
    my ($self, $args) = @_;
    my $file = $args->{'file'};
    my $vars = $args->{'vars'};

    Bugzilla->process_cache->{shadow_bug_field} ||= Bugzilla::Field->new({ name => 'cf_shadow_bug' });

    return unless Bugzilla->user->in_group('can_shadow_bugs');
    return unless
        $file eq 'bug/edit.html.tmpl'
        || $file eq 'bug/show.html.tmpl'
        || $file eq 'bug/show-header.html.tmpl';
    my $bug = exists $vars->{'bugs'} ? $vars->{'bugs'}[0] : $vars->{'bug'};
    return unless $bug->cf_shadow_bug;
    $vars->{is_shadow_bug} = 1;

    if ($file eq 'bug/edit.html.tmpl') {
        # load comments from other bug
        $vars->{shadow_comments} = $bug->cf_shadow_bug_obj->comments;
    }
}

sub bug_end_of_update {
    my ($self, $args) = @_;

    # don't allow shadowing non-public bugs
    if (exists $args->{changes}->{cf_shadow_bug}) {
        my ($old_id, $new_id) = @{ $args->{changes}->{cf_shadow_bug} };
        if ($new_id) {
            if (!Bugzilla::User->new()->can_see_bug($new_id)) {
                ThrowUserError('illegal_shadow_bug_public', { id => $new_id });
            }
        }
    }

    # if a shadow bug is made public, clear the shadow_bug field
    if (exists $args->{changes}->{bug_group}) {
        my $bug = $args->{bug};
        return unless my $shadow_id = $bug->cf_shadow_bug;
        my $is_public = Bugzilla::User->new()->can_see_bug($bug->id);
        if ($is_public) {
            Bugzilla->dbh->do(
                "UPDATE bugs SET cf_shadow_bug=NULL WHERE bug_id=?",
                undef, $bug->id);
            LogActivityEntry($bug->id, 'cf_shadow_bug', $shadow_id, '',
                            Bugzilla->user->id, $args->{timestamp});

        }
    }
}

__PACKAGE__->NAME;
