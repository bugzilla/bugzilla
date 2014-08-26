# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Review;
use strict;
use warnings;

use base qw(Bugzilla::Extension);
our $VERSION = '1';

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Extension::Review::FlagStateActivity;
use Bugzilla::Extension::Review::Util;
use Bugzilla::Install::Filesystem;
use Bugzilla::Search;
use Bugzilla::User;
use Bugzilla::Util qw(clean_text diff_arrays);

use constant UNAVAILABLE_RE => qr/\b(?:unavailable|pto|away)\b/i;

#
# monkey-patched methods
#

BEGIN {
    *Bugzilla::Product::reviewers         = \&_product_reviewers;
    *Bugzilla::Product::reviewers_objs    = \&_product_reviewers_objs;
    *Bugzilla::Product::reviewer_required = \&_product_reviewer_required;
    *Bugzilla::Component::reviewers       = \&_component_reviewers;
    *Bugzilla::Component::reviewers_objs  = \&_component_reviewers_objs;
    *Bugzilla::Bug::mentors               = \&_bug_mentors;
    *Bugzilla::Bug::bug_mentors           = \&_bug_mentors;
    *Bugzilla::Bug::is_mentor             = \&_bug_is_mentor;
    *Bugzilla::Bug::set_bug_mentors       = \&_bug_set_bug_mentors;
    *Bugzilla::User::review_count         = \&_user_review_count;
}

#
# monkey-patched methods
#

sub _product_reviewers         { _reviewers($_[0],      'product',   $_[1])   }
sub _product_reviewers_objs    { _reviewers_objs($_[0], 'product',   $_[1])   }
sub _component_reviewers       { _reviewers($_[0],      'component', $_[1]) }
sub _component_reviewers_objs  { _reviewers_objs($_[0], 'component', $_[1]) }

sub _reviewers {
    my ($object, $type, $include_disabled) = @_;
    return join(', ', map { $_->login } @{ _reviewers_objs($object, $type, $include_disabled) });
}

sub _reviewers_objs {
    my ($object, $type, $include_disabled) = @_;
    if (!$object->{reviewers}) {
        my $dbh = Bugzilla->dbh;
        my $user_ids = $dbh->selectcol_arrayref(
            "SELECT user_id FROM ${type}_reviewers WHERE ${type}_id = ? ORDER BY sortkey",
            undef,
            $object->id,
        );
        # new_from_list always sorts according to the object's definition,
        # so we have to reorder the list
        my $users = Bugzilla::User->new_from_list($user_ids);
        my %user_map = map { $_->id => $_ } @$users;
        my @reviewers = map { $user_map{$_} } @$user_ids;
        if (!$include_disabled) {
            @reviewers = grep { $_->is_enabled
                                && $_->name !~ UNAVAILABLE_RE } @reviewers;
        }
        $object->{reviewers} = \@reviewers;
    }
    return $object->{reviewers};
}

sub _user_review_count {
    my ($self) = @_;
    if (!exists $self->{review_count}) {
        my $dbh = Bugzilla->dbh;
        ($self->{review_count}) = $dbh->selectrow_array(
            "SELECT COUNT(*)
               FROM flags
                    INNER JOIN flagtypes ON flagtypes.id = flags.type_id
              WHERE flags.requestee_id = ?
                    AND " . $dbh->sql_in('flagtypes.name', [ "'review'", "'feedback'" ]),
            undef,
            $self->id,
        );
    }
    return $self->{review_count};
}

#
# mentor
#

sub _bug_mentors {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;
    if (!$self->{bug_mentors}) {
        my $mentor_ids = $dbh->selectcol_arrayref("
            SELECT user_id FROM bug_mentors WHERE bug_id = ?",
            undef,
            $self->id);
        $self->{bug_mentors} = [];
        foreach my $mentor_id (@$mentor_ids) {
            push(@{ $self->{bug_mentors} },
                 Bugzilla::User->new({ id => $mentor_id, cache => 1 }));
        }
        $self->{bug_mentors} = [
            sort { $a->login cmp $b->login } @{ $self->{bug_mentors} }
        ];
    }
    return $self->{bug_mentors};
}

sub _bug_is_mentor {
    my ($self, $user) = @_;
    my $user_id = ($user || Bugzilla->user)->id;
    return (grep { $_->id == $user_id} @{ $self->mentors }) ? 1 : 0;
}

sub _bug_set_bug_mentors {
    my ($self, $value) = @_;
    $self->set('bug_mentors', $value);
}

sub object_validators {
    my ($self, $args) = @_;
    return unless $args->{class} eq 'Bugzilla::Bug';
    $args->{validators}->{bug_mentors} = \&_bug_check_bug_mentors;
}

sub _bug_check_bug_mentors {
    my ($self, $value) = @_;
    return [
        map { Bugzilla::User->check({ name => $_, cache => 1 }) }
        ref($value) ? @$value : ($value)
    ];
}

sub bug_user_match_fields {
    my ($self, $args) = @_;
    $args->{fields}->{bug_mentors} = { type => 'multi' };
}

sub bug_before_create {
    my ($self, $args) = @_;
    my $params = $args->{params};
    my $stash = $args->{stash};
    $stash->{bug_mentors} = delete $params->{bug_mentors};
}

sub bug_end_of_create {
    my ($self, $args) = @_;
    my $bug = $args->{bug};
    my $stash = $args->{stash};
    if (my $mentors = $stash->{bug_mentors}) {
        $self->_update_user_table({
            object      => $bug,
            old_users   => [],
            new_users   => $self->_bug_check_bug_mentors($mentors),
            table       => 'bug_mentors',
            id_field    => 'bug_id',
        });
    }
}

sub _update_user_table {
    my ($self, $args) = @_;
    my ($object, $old_users, $new_users, $table, $id_field, $has_sortkey, $return) =
        @$args{qw(object old_users new_users table id_field has_sortkey return)};
    my $dbh = Bugzilla->dbh;
    my (@removed, @added);

    # remove deleted users
    foreach my $old_user (@$old_users) {
        if (!grep { $_->id == $old_user->id } @$new_users) {
            $dbh->do(
                "DELETE FROM $table WHERE $id_field = ? AND user_id = ?",
                undef,
                $object->id, $old_user->id,
            );
            push @removed, $old_user;
        }
    }
    # add new users
    foreach my $new_user (@$new_users) {
        if (!grep { $_->id == $new_user->id } @$old_users) {
            $dbh->do(
                "INSERT INTO $table ($id_field, user_id) VALUES (?, ?)",
                undef,
                $object->id, $new_user->id,
            );
            push @added, $new_user;
        }
    }

    return unless @removed || @added;

    if ($has_sortkey) {
        # update the sortkey for all users
        for (my $i = 0; $i < scalar(@$new_users); $i++) {
            $dbh->do(
                "UPDATE $table SET sortkey=? WHERE $id_field = ? AND user_id = ?",
                undef,
                ($i + 1) * 10, $object->id, $new_users->[$i]->id,
            );
        }
    }

    if (!$return) {
        return undef;
    }
    elsif ($return eq 'diff') {
        return [
            @removed ? join(', ', map { $_->login } @removed) : undef,
            @added   ? join(', ', map { $_->login } @added)   : undef,
        ];
    }
    elsif ($return eq 'old-new') {
        return [
            @$old_users ? join(', ', map { $_->login } @$old_users) : '',
            @$new_users ? join(', ', map { $_->login } @$new_users) : '',
        ];
    }
}

#
# reviewer-required, review counters, etc
#

sub _product_reviewer_required { $_[0]->{reviewer_required} }

sub object_columns {
    my ($self, $args) = @_;
    my ($class, $columns) = @$args{qw(class columns)};
    if ($class->isa('Bugzilla::Product')) {
        push @$columns, 'reviewer_required';
    }
    elsif ($class->isa('Bugzilla::User')) {
        push @$columns, qw(review_request_count feedback_request_count needinfo_request_count);
    }
}

sub object_update_columns {
    my ($self, $args) = @_;
    my ($object, $columns) = @$args{qw(object columns)};
    if ($object->isa('Bugzilla::Product')) {
        push @$columns, 'reviewer_required';
    }
    elsif ($object->isa('Bugzilla::User')) {
        push @$columns, qw(review_request_count feedback_request_count needinfo_request_count);
    }
}

sub _new_users_from_input {
    my ($field) = @_;
    my $input_params = Bugzilla->input_params;
    return unless exists $input_params->{$field};
    return [] unless $input_params->{$field};
    Bugzilla::User::match_field({ $field => {'type' => 'multi'} });;
    my $value = $input_params->{$field};
    return [
        map { Bugzilla::User->check({ name => $_, cache => 1 }) }
        ref($value) ? @$value : ($value)
    ];
}

#
# create/update
#

sub object_before_create {
    my ($self, $args) = @_;
    my ($class, $params) = @$args{qw(class params)};
    return unless $class->isa('Bugzilla::Product');

    $params->{reviewer_required} = Bugzilla->cgi->param('reviewer_required') ? 1 : 0;
}

sub object_end_of_set_all {
    my ($self, $args) = @_;
    my ($object, $params) = @$args{qw(object params)};
    return unless $object->isa('Bugzilla::Product');

    $object->set('reviewer_required', Bugzilla->cgi->param('reviewer_required') ? 1 : 0);
}

sub object_end_of_create {
    my ($self, $args) = @_;
    my ($object, $params) = @$args{qw(object params)};

    if ($object->isa('Bugzilla::Product')) {
        $self->_update_user_table({
            object      => $object,
            old_users   => [],
            new_users   => _new_users_from_input('reviewers'),
            table       => 'product_reviewers',
            id_field    => 'product_id',
            has_sortkey => 1,
        });
    }
    elsif ($object->isa('Bugzilla::Component')) {
        $self->_update_user_table({
            object      => $object,
            old_users   => [],
            new_users   => _new_users_from_input('reviewers'),
            table       => 'component_reviewers',
            id_field    => 'component_id',
            has_sortkey => 1,
        });
    }
    elsif (_is_countable_flag($object) && $object->requestee_id && $object->status eq '?') {
        _adjust_request_count($object, +1);
    }
    if (_is_countable_flag($object)) {
        $self->_log_flag_state_activity($object, $object->status);
    }
}

sub object_end_of_update {
    my ($self, $args) = @_;
    my ($object, $old_object, $changes) = @$args{qw(object old_object changes)};

    if ($object->isa('Bugzilla::Product')) {
        my $diff = $self->_update_user_table({
            object      => $object,
            old_users   => $old_object->reviewers_objs(1),
            new_users   => _new_users_from_input('reviewers'),
            table       => 'product_reviewers',
            id_field    => 'product_id',
            has_sortkey => 1,
            return      => 'old-new',
        });
        $changes->{reviewers} = $diff if $diff;
    }
    elsif ($object->isa('Bugzilla::Component')) {
        my $diff = $self->_update_user_table({
            object      => $object,
            old_users   => $old_object->reviewers_objs(1),
            new_users   => _new_users_from_input('reviewers'),
            table       => 'component_reviewers',
            id_field    => 'component_id',
            has_sortkey => 1,
            return      => 'old-new',
        });
        $changes->{reviewers} = $diff if $diff;
    }
    elsif ($object->isa('Bugzilla::Bug')) {
        my $diff = $self->_update_user_table({
            object      => $object,
            old_users   => $old_object->mentors,
            new_users   => $object->mentors,
            table       => 'bug_mentors',
            id_field    => 'bug_id',
            return      => 'diff',
        });
        $changes->{bug_mentor} = $diff if $diff;
    }
    elsif (_is_countable_flag($object)) {
        my ($old_status, $new_status) = ($old_object->status, $object->status);
        if ($old_status ne '?' && $new_status eq '?') {
            # setting flag to ?
            _adjust_request_count($object, +1);
        }
        elsif ($old_status eq '?' && $new_status ne '?') {
            # setting flag from ?
            _adjust_request_count($old_object, -1);
        }
        elsif ($old_object->requestee_id && !$object->requestee_id) {
            # removing requestee
            _adjust_request_count($old_object, -1);
        }
        elsif (!$old_object->requestee_id && $object->requestee_id) {
            # setting requestee
            _adjust_request_count($object, +1);
        }
        elsif ($old_object->requestee_id && $object->requestee_id
               && $old_object->requestee_id != $object->requestee_id)
        {
            # changing requestee
            _adjust_request_count($old_object, -1);
            _adjust_request_count($object, +1);
        }
    }
}

sub flag_updated {
    my ($self, $args) = @_;
    my $flag = $args->{flag};
    my $changes = $args->{changes};

    return unless scalar(keys %$changes);
    if (_is_countable_flag($flag)) {
        $self->_log_flag_state_activity( $flag, $flag->status );
    }
}

sub object_before_delete {
    my ($self, $args) = @_;
    my $object = $args->{object};

    if (_is_countable_flag($object) && $object->requestee_id && $object->status eq '?') {
        _adjust_request_count($object, -1);
    }

    if (_is_countable_flag($object)) {
        $self->_log_flag_state_activity($object, 'X');
    }
}

sub _is_countable_flag {
    my ($object) = @_;
    return unless $object->isa('Bugzilla::Flag');
    my $type_name = $object->type->name;
    return $type_name eq 'review' || $type_name eq 'feedback' || $type_name eq 'needinfo';
}

sub _log_flag_state_activity {
    my ($self, $flag, $status) = @_;

    Bugzilla::Extension::Review::FlagStateActivity->create({
        flag_when     => $flag->modification_date,
        type_id       => $flag->type_id,
        flag_id       => $flag->id,
        setter_id     => $flag->setter_id,
        requestee_id  => $flag->requestee_id,
        bug_id        => $flag->bug_id,
        attachment_id => $flag->attach_id,
        status        => $status,
    });
}

sub _adjust_request_count {
    my ($flag, $add) = @_;
    return unless my $requestee_id = $flag->requestee_id;
    my $field = $flag->type->name . '_request_count';

    # update the current user's object so things are display correctly on the
    # post-processing page
    my $user = Bugzilla->user;
    if ($requestee_id == $user->id) {
        $user->{$field} += $add;
    }

    # update database directly to avoid creating audit_log entries
    $add = $add == -1 ? ' - 1' : ' + 1';
    Bugzilla->dbh->do(
        "UPDATE profiles SET $field = $field $add WHERE userid = ?",
        undef,
        $requestee_id
    );
    Bugzilla->memcached->clear({ table => 'profiles', id => $requestee_id });
}

# bugzilla's handling of requestee matching when creating bugs is "if it's
# wrong, or matches too many, default to empty", which breaks mandatory
# reviewer requirements.  instead we just throw an error.
sub post_bug_attachment_flags {
    my ($self, $args) = @_;
    $self->_check_review_flag($args);
}

sub create_attachment_flags {
    my ($self, $args) = @_;
    $self->_check_review_flag($args);
}

sub _check_review_flag {
    my ($self, $args) = @_;
    my $bug = $args->{bug};
    my $cgi = Bugzilla->cgi;

    # extract the set flag-types
    my @flagtype_ids = map { /^flag_type-(\d+)$/ ? $1 : () } $cgi->param();
    @flagtype_ids = grep { $cgi->param("flag_type-$_") eq '?' } @flagtype_ids;
    return unless scalar(@flagtype_ids);

    # find valid review flagtypes
    my $flag_types = Bugzilla::FlagType::match({
        product_id   => $bug->product_id,
        component_id => $bug->component_id,
        is_active    => 1
    });
    foreach my $flag_type (@$flag_types) {
        next unless $flag_type->name eq 'review'
                    && $flag_type->target_type eq 'attachment';
        my $type_id = $flag_type->id;
        next unless scalar(grep { $_ == $type_id } @flagtype_ids);

        my $reviewers = clean_text($cgi->param("requestee_type-$type_id") || '');
        if ($reviewers eq '' && $bug->product_obj->reviewer_required) {
            ThrowUserError('reviewer_required');
        }

        foreach my $reviewer (split(/[,;]+/, $reviewers)) {
            # search on the reviewer
            my $users = Bugzilla::User::match($reviewer, 2, 1);

            # no matches
            if (scalar(@$users) == 0) {
                ThrowUserError('user_match_failed', { name => $reviewer });
            }

            # more than one match, throw error
            if (scalar(@$users) > 1) {
                ThrowUserError('user_match_too_many', { fields => [ 'review' ] });
            }
        }
    }
}

sub flag_end_of_update {
    my ($self, $args) = @_;
    my ($object, $new_flags) = @$args{qw(object new_flags)};
    my $bug = $object->isa('Bugzilla::Attachment') ? $object->bug : $object;
    return unless $bug->product_obj->reviewer_required;

    foreach my $orig_change (@$new_flags) {
        my $change = $orig_change; # work on a copy
        $change =~ s/^[^:]+://;
        my $reviewer = '';
        if ($change =~ s/\(([^\)]+)\)$//) {
            $reviewer = $1;
        }
        my ($name, $value) = $change =~ /^(.+)(.)$/;

        if ($name eq 'review' && $value eq '?' && $reviewer eq '') {
            ThrowUserError('reviewer_required');
        }
    }
}

#
# search
#

sub buglist_columns {
    my ($self, $args) = @_;
    my $dbh = Bugzilla->dbh;
    my $columns = $args->{columns};
    $columns->{bug_mentor} = { title => 'Mentor' };
    if (Bugzilla->user->id) {
        $columns->{bug_mentor}->{name}
            = $dbh->sql_group_concat('map_mentors_names.login_name');
    }
    else {
        $columns->{bug_mentor}->{name}
            = $dbh->sql_group_concat('map_mentors_names.realname');

    }
}

sub buglist_column_joins {
    my ($self, $args) = @_;
    my $column_joins = $args->{column_joins};
    $column_joins->{bug_mentor} = {
        as    => 'map_mentors',
        table => 'bug_mentors',
        then_to => {
            as    => 'map_mentors_names',
            table => 'profiles',
            from  => 'map_mentors.user_id',
            to    => 'userid',
        },
    },
}

sub search_operator_field_override {
    my ($self, $args) = @_;
    my $operators = $args->{operators};
    $operators->{bug_mentor} = {
        _non_changed => sub {
            Bugzilla::Search::_user_nonchanged(@_)
        }
    };
}

#
# web service / pages
#

sub webservice {
    my ($self,  $args) = @_;
    my $dispatch = $args->{dispatch};
    $dispatch->{Review} = "Bugzilla::Extension::Review::WebService";
}

sub page_before_template {
    my ($self, $args) = @_;

    if ($args->{page_id} eq 'review_suggestions.html') {
        $self->review_suggestions_report($args);
    }
    elsif ($args->{page_id} eq 'review_requests_rebuild.html') {
        $self->review_requests_rebuild($args);
    }
}

sub review_suggestions_report {
    my ($self, $args) = @_;

    my $user = Bugzilla->login(LOGIN_REQUIRED);
    my $products = [];
    my @products = sort { lc($a->name) cmp lc($b->name) }
                   @{ Bugzilla->user->get_accessible_products };
    foreach my $product_obj (@products) {
        my $has_reviewers = 0;
        my $product = {
            name       => $product_obj->name,
            components => [],
            reviewers  => $product_obj->reviewers_objs(1),
        };
        $has_reviewers = scalar @{ $product->{reviewers} };

        foreach my $component_obj (@{ $product_obj->components }) {
            my $component = {
                name       => $component_obj->name,
                reviewers  => $component_obj->reviewers_objs(1),
            };
            if (@{ $component->{reviewers} }) {
                push @{ $product->{components} }, $component;
                $has_reviewers = 1;
            }
        }

        if ($has_reviewers) {
            push @$products, $product;
        }
    }
    $args->{vars}->{products} = $products;
}

sub review_requests_rebuild {
    my ($self, $args) = @_;

    Bugzilla->user->in_group('admin')
        || ThrowUserError('auth_failure', { group  => 'admin',
                                            action => 'run',
                                            object => 'review_requests_rebuild' });
    if (Bugzilla->cgi->param('rebuild')) {
        my $processed_users = 0;
        rebuild_review_counters(sub {
            my ($count, $total) = @_;
            $processed_users = $total;
        });
        $args->{vars}->{rebuild} = 1;
        $args->{vars}->{total}   = $processed_users;
    }
}

#
# installation
#

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    $args->{'schema'}->{'product_reviewers'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            user_id => {
                TYPE    => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'profiles',
                    COLUMN => 'userid',
                    DELETE => 'CASCADE',
                }
            },
            display_name => {
                TYPE    => 'VARCHAR(64)',
            },
            product_id => {
                TYPE    => 'INT2',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'products',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                }
            },
            sortkey => {
                TYPE    => 'INT2',
                NOTNULL => 1,
                DEFAULT => 0,
            },
        ],
        INDEXES => [
            product_reviewers_idx => {
                FIELDS => [ 'user_id', 'product_id' ],
                TYPE => 'UNIQUE',
            },
        ],
    };
    $args->{'schema'}->{'component_reviewers'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            user_id => {
                TYPE    => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'profiles',
                    COLUMN => 'userid',
                    DELETE => 'CASCADE',
                }
            },
            display_name => {
                TYPE    => 'VARCHAR(64)',
            },
            component_id => {
                TYPE    => 'INT2',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'components',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                }
            },
            sortkey => {
                TYPE    => 'INT2',
                NOTNULL => 1,
                DEFAULT => 0,
            },
        ],
        INDEXES => [
            component_reviewers_idx => {
                FIELDS => [ 'user_id', 'component_id' ],
                TYPE => 'UNIQUE',
            },
        ],
    };

    $args->{'schema'}->{'flag_state_activity'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },

            flag_when => {
                TYPE    => 'DATETIME',
                NOTNULL => 1,
            },

            type_id => {
                TYPE       => 'INT2',
                NOTNULL    => 1,
                REFERENCES => {
                    TABLE  => 'flagtypes',
                    COLUMN => 'id',
                    DELETE => 'CASCADE'
                }
            },

            flag_id => {
                TYPE    => 'INT3',
                NOTNULL => 1,
            },

            setter_id => {
                TYPE       => 'INT3',
                NOTNULL    => 1,
                REFERENCES => {
                    TABLE  => 'profiles',
                    COLUMN => 'userid',
                },
            },

            requestee_id => {
                TYPE       => 'INT3',
                REFERENCES => {
                    TABLE  => 'profiles',
                    COLUMN => 'userid',
                },
            },

            bug_id => {
                TYPE       => 'INT3',
                NOTNULL    => 1,
                REFERENCES => {
                    TABLE  => 'bugs',
                    COLUMN => 'bug_id',
                    DELETE => 'CASCADE'
                }
            },

            attachment_id => {
                TYPE       => 'INT3',
                REFERENCES => {
                    TABLE  => 'attachments',
                    COLUMN => 'attach_id',
                    DELETE => 'CASCADE'
                }
            },

            status => {
                TYPE    => 'CHAR(1)',
                NOTNULL => 1,
            },
        ],
    };

    $args->{'schema'}->{'bug_mentors'} = {
        FIELDS => [
            bug_id => {
                TYPE       => 'INT3',
                NOTNULL    => 1,
                REFERENCES => {
                    TABLE  => 'bugs',
                    COLUMN => 'bug_id',
                    DELETE => 'CASCADE',
                },
            },
            user_id => {
                TYPE    => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'profiles',
                    COLUMN => 'userid',
                    DELETE => 'CASCADE',
                }
            },
        ],
        INDEXES => [
            bug_mentors_idx => {
                FIELDS => [ 'bug_id', 'user_id' ],
                TYPE => 'UNIQUE',
            },
            bug_mentors_bug_id_idx => [ 'bug_id' ],
        ],
    };

    $args->{'schema'}->{'bug_mentors'} = {
        FIELDS => [
            bug_id => {
                TYPE       => 'INT3',
                NOTNULL    => 1,
                REFERENCES => {
                    TABLE  => 'bugs',
                    COLUMN => 'bug_id',
                    DELETE => 'CASCADE',
                },
            },
            user_id => {
                TYPE    => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'profiles',
                    COLUMN => 'userid',
                    DELETE => 'CASCADE',
                }
            },
        ],
        INDEXES => [
            bug_mentors_idx => {
                FIELDS => [ 'bug_id', 'user_id' ],
                TYPE => 'UNIQUE',
            },
            bug_mentors_bug_id_idx => [ 'bug_id' ],
        ],
    };
}

sub install_update_db {
    my $dbh = Bugzilla->dbh;
    $dbh->bz_add_column(
        'products',
        'reviewer_required', { TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 'FALSE' }
    );
    $dbh->bz_add_column(
        'profiles',
        'review_request_count', { TYPE => 'INT2', NOTNULL => 1, DEFAULT => 0 }
    );
    $dbh->bz_add_column(
        'profiles',
        'feedback_request_count', { TYPE => 'INT2', NOTNULL => 1, DEFAULT => 0 }
    );
    $dbh->bz_add_column(
        'profiles',
        'needinfo_request_count', { TYPE => 'INT2', NOTNULL => 1, DEFAULT => 0 }
    );

    my $field = Bugzilla::Field->new({ name => 'bug_mentor' });
    if (!$field) {
        Bugzilla::Field->create({
            name => 'bug_mentor',
            description => 'Mentor'
        });
    }
}

sub install_filesystem {
    my ($self, $args) = @_;
    my $files = $args->{files};
    my $extensions_dir = bz_locations()->{extensionsdir};
    $files->{"$extensions_dir/Review/bin/review_requests_rebuild.pl"} = {
        perms => Bugzilla::Install::Filesystem::OWNER_EXECUTE
    };
}


__PACKAGE__->NAME;
