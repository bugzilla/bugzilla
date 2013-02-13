# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::RestrictComments;

use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Constants;

BEGIN {
    *Bugzilla::Bug::restrict_comments = \&_bug_restrict_comments;
}

sub _bug_restrict_comments {
    my ($self) = @_;
    return $self->{restrict_comments};
}

sub bug_check_can_change_field {
    my ($self, $args) = @_;
    my ($bug, $priv_results) = @$args{qw(bug priv_results)};
    my $user = Bugzilla->user;

    if ($user->id
        && $bug->restrict_comments
        && !$user->in_group(Bugzilla->params->{'restrict_comments_group'}))
    {
        push(@$priv_results, PRIVILEGES_REQUIRED_EMPOWERED);
        return;
    }
}

sub _can_restrict_comments {
    my ($self, $object) = @_;
    return unless $object->isa('Bugzilla::Bug');
    $self->{setter_group} ||= Bugzilla->params->{'restrict_comments_enable_group'};
    return Bugzilla->user->in_group($self->{setter_group});
}

sub object_end_of_set_all {
    my ($self, $args) = @_;
    my $object = $args->{object};
    if ($self->_can_restrict_comments($object)) {
        my $input = Bugzilla->input_params;
        $object->set('restrict_comments', $input->{restrict_comments} ? 1 : undef);
    }
}

sub object_update_columns {
    my ($self, $args) = @_;
    my ($object, $columns) = @$args{qw(object columns)};
    if ($self->_can_restrict_comments($object)) {
        push(@$columns, 'restrict_comments');
    }
}

sub object_columns {
    my ($self, $args) = @_;
    my ($class, $columns) = @$args{qw(class columns)};
    if ($class->isa('Bugzilla::Bug')) {
        push(@$columns, 'restrict_comments');
    }
}

sub bug_fields {
    my ($self, $args) = @_;
    my $fields = $args->{'fields'};
    push (@$fields, 'restrict_comments')
}

sub config_add_panels {
    my ($self, $args) = @_;
    my $modules = $args->{panel_modules};
    $modules->{RestrictComments} = "Bugzilla::Extension::RestrictComments::Config";
}

sub install_update_db {
    my $dbh = Bugzilla->dbh;

    my $field = new Bugzilla::Field({ name => 'restrict_comments' });
    if (!$field) {
        Bugzilla::Field->create({ name => 'restrict_comments', description => 'Restrict Comments' });
    }

    $dbh->bz_add_column('bugs', 'restrict_comments', { TYPE => 'BOOLEAN' });
}

__PACKAGE__->NAME;
