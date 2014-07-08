# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BugmailFilter;
use strict;
use warnings;

use base qw(Bugzilla::Extension);
our $VERSION = '1';

use Bugzilla::BugMail;
use Bugzilla::Component;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Extension::BugmailFilter::Constants;
use Bugzilla::Extension::BugmailFilter::FakeField;
use Bugzilla::Extension::BugmailFilter::Filter;
use Bugzilla::Field;
use Bugzilla::Product;
use Bugzilla::User;
use Encode;
use Sys::Syslog qw(:DEFAULT);

#
# preferences
#

sub user_preferences {
    my ($self, $args) = @_;
    return unless $args->{current_tab} eq 'bugmail_filter';

    if ($args->{save_changes}) {
        my $input = Bugzilla->input_params;

        if ($input->{add_filter}) {

            # add a new filter

            my $params = {
                user_id => Bugzilla->user->id,
            };
            $params->{field_name} = $input->{field} || IS_NULL;
            $params->{relationship} = $input->{relationship} || IS_NULL;
            if (my $product_name = $input->{product}) {
                my $product = Bugzilla::Product->check({
                    name => $product_name, cache => 1
                });
                $params->{product_id} = $product->id;

                if (my $component_name = $input->{component}) {
                    $params->{component_id} = Bugzilla::Component->check({
                        name => $component_name, product => $product,
                        cache => 1
                    })->id;
                }
                else {
                    $params->{component_id} = IS_NULL;
                }
            }
            else {
                $params->{product_id} = IS_NULL;
                $params->{component_id} = IS_NULL;
            }

            if (@{ Bugzilla::Extension::BugmailFilter::Filter->match($params) }) {
                ThrowUserError('bugmail_filter_exists');
            }
            $params->{action} = $input->{action} eq 'Exclude' ? 1 : 0;
            foreach my $name (keys %$params) {
                $params->{$name} = undef
                    if $params->{$name} eq IS_NULL;
            }
            Bugzilla::Extension::BugmailFilter::Filter->create($params);
        }

        elsif ($input->{remove_filter}) {

            # remove filter(s)

            my $ids = ref($input->{remove}) ? $input->{remove} : [ $input->{remove} ];
            my $dbh = Bugzilla->dbh;
            $dbh->bz_start_transaction;
            foreach my $id (@$ids) {
                if (my $filter = Bugzilla::Extension::BugmailFilter::Filter->new($id)) {
                    $filter->remove_from_db();
                }
            }
            $dbh->bz_commit_transaction;
        }
    }

    my $vars = $args->{vars};

    my @fields = @{ Bugzilla->fields({ obsolete => 0 }) };

    # remove time trackinger fields
    if (!Bugzilla->user->is_timetracker) {
        foreach my $tt_field (TIMETRACKING_FIELDS) {
            @fields = grep { $_->name ne $tt_field } @fields;
        }
    }

    # remove fields which don't make any sense to filter on
    foreach my $ignore_field (IGNORE_FIELDS) {
        @fields = grep { $_->name ne $ignore_field } @fields;
    }

    # remove all tracking flag fields.  these change too frequently to be of
    # value, so they only add noise to the list.
    foreach my $name (@{ Bugzilla->tracking_flag_names }) {
        @fields = grep { $_->name ne $name } @fields;
    }

    # add tracking flag types instead
    foreach my $field (
        @{ Bugzilla::Extension::BugmailFilter::FakeField->tracking_flag_fields() }
    ) {
        push @fields, $field;
    }

    # adjust the description for selected fields. as we shouldn't touch the
    # real Field objects, we remove the object and insert a FakeField object
    foreach my $override_field (keys %{ FIELD_DESCRIPTION_OVERRIDE() }) {
        @fields = grep { $_->name ne $override_field } @fields;
        push @fields, Bugzilla::Extension::BugmailFilter::FakeField->new({
            name        => $override_field,
            description => FIELD_DESCRIPTION_OVERRIDE->{$override_field},
        });
    }

    # some fields are present in the changed-fields x-header but are not real
    # bugzilla fields
    foreach my $field (
        @{ Bugzilla::Extension::BugmailFilter::FakeField->fake_fields() }
    ) {
        push @fields, $field;
    }

    @fields = sort { lc($a->description) cmp lc($b->description) } @fields;
    $vars->{fields} = \@fields;

    $vars->{relationships} = FILTER_RELATIONSHIPS();

    $vars->{filters} = [
        sort {
            $a->product_name cmp $b->product_name
            || $a->component_name cmp $b->component_name
            || $a->field_name cmp $b->field_name
        }
        @{ Bugzilla::Extension::BugmailFilter::Filter->match({
            user_id => Bugzilla->user->id,
        }) }
    ];

    ${ $args->{handled} } = 1;
}

#
# hooks
#

sub user_wants_mail {
    my ($self, $args) = @_;

    my ($user, $wants_mail, $diffs, $comments)
        = @$args{qw( user wants_mail fieldDiffs comments )};

    return unless $$wants_mail;

    my $cache = Bugzilla->request_cache->{bugmail_filters} //= {};
    my $filters = $cache->{$user->id} //=
        Bugzilla::Extension::BugmailFilter::Filter->match({
        user_id => $user->id
    });
    return unless @$filters;

    my $fields = [ map { $_->{field_name} } @$diffs ];

    # insert fake fields for new attachments and comments
    if (@$comments) {
        if (grep { $_->type == CMT_ATTACHMENT_CREATED } @$comments) {
            push @$fields, 'attachment.created';
        }
        if (grep { $_->type != CMT_ATTACHMENT_CREATED } @$comments) {
            push @$fields, 'comment.created';
        }
    }

    # replace tracking flag fields with fake tracking flag types
    require Bugzilla::Extension::TrackingFlags::Flag;
    my %count;
    my @tracking_flags;
    foreach my $field (@$fields, @{ Bugzilla->tracking_flag_names }) {
        $count{$field}++;
    }
    foreach my $field (keys %count) {
        push @tracking_flags, $field
            if $count{$field} > 1;
    }
    my %tracking_types =
        map { $_->flag_type => 1 }
        @{ Bugzilla::Extension::TrackingFlags::Flag->match({
            name => \@tracking_flags
        })};
    foreach my $type (keys %tracking_types) {
        push @$fields, 'tracking.' . $type;
    }
    foreach my $field (@{ Bugzilla->tracking_flag_names }) {
        $fields = [ grep { $_ ne $field } @$fields ];
    }

    if (_should_drop($fields, $filters, $args)) {
        $$wants_mail = 0;
        openlog('apache', 'cons,pid', 'local4');
        syslog('notice', encode_utf8(sprintf(
            '[bugmail] %s (filtered) bug-%s %s',
            $args->{user}->login,
            $args->{bug}->id,
            $args->{bug}->short_desc,
        )));
        closelog();
    }
}

sub _should_drop {
    my ($fields, $filters, $args) = @_;

    # calculate relationships

    my ($user, $bug, $relationship) = @$args{qw( user bug relationship )};
    my ($user_id, $login) = ($user->id, $user->login);
    my $bit_direct    = Bugzilla::BugMail::BIT_DIRECT;
    my $bit_watching  = Bugzilla::BugMail::BIT_WATCHING;
    my $bit_compwatch = 15; # from Bugzilla::Extension::ComponentWatching

    # the index of $rel_map corresponds to the values in FILTER_RELATIONSHIPS
    my @rel_map;
    $rel_map[1] = $bug->assigned_to->id == $user_id;
    $rel_map[2] = !$rel_map[1];
    $rel_map[3] = $bug->reporter->id == $user_id;
    $rel_map[4] = !$rel_map[3];
    if ($bug->qa_contact) {
        $rel_map[5] = $bug->qa_contact->id == $user_id;
        $rel_map[6] = !$rel_map[6];
    }
    $rel_map[7] = $bug->cc
                  ? grep { $_ eq $login } @{ $bug->cc }
                  : 0;
    $rel_map[8] = !$rel_map[8];
    $rel_map[9] = (
                    $relationship & $bit_watching
                    or $relationship & $bit_compwatch
                  );
    $rel_map[10] = !$rel_map[9];
    $rel_map[11] = $bug->is_mentor($user);
    $rel_map[12] = !$rel_map[11];
    foreach my $bool (@rel_map) {
        $bool = $bool ? 1 : 0;
    }

    # exclusions
    # drop email where we are excluding all changed fields

    my %exclude = map { $_ => 0 } @$fields;
    my $params = {
        product_id   => $bug->product_id,
        component_id => $bug->component_id,
        rel_map      => \@rel_map,
    };

    foreach my $field_name (@$fields) {
        $params->{field_name} = $field_name;
        foreach my $filter (grep { $_->is_exclude } @$filters) {
            if ($filter->matches($params)) {
                $exclude{$field_name} = 1;
                last;
            }
        }
    }

    # no need to process includes if nothing was excluded
    if (!grep { $exclude{$_} } @$fields) {
        return 0;
    }

    # inclusions
    # flip the bit for fields that should be included

    foreach my $field_name (@$fields) {
        $params->{field_name} = $field_name;
        foreach my $filter (grep { $_->is_include } @$filters) {
            if ($filter->matches($params)) {
                $exclude{$field_name} = 0;
                last;
            }
        }
    }

    # drop if all fields are still excluded
    return !(grep { !$exclude{$_} } keys %exclude);
}

# catch when fields are renamed, and update the field_name entires
sub object_end_of_update {
    my ($self, $args) = @_;
    my $object = $args->{object};

    return unless $object->isa('Bugzilla::Field')
        || $object->isa('Bugzilla::Extension::TrackingFlags::Flag');

    return unless exists $args->{changes}->{name};

    my $old_name = $args->{changes}->{name}->[0];
    my $new_name = $args->{changes}->{name}->[1];

    Bugzilla->dbh->do(
        "UPDATE bugmail_filters SET field_name=? WHERE field_name=?",
        undef,
        $new_name, $old_name);
}

sub reorg_move_component {
    my ($self, $args) = @_;
    my $new_product = $args->{new_product};
    my $component   = $args->{component};

    Bugzilla->dbh->do(
        "UPDATE bugmail_filters SET product_id=? WHERE component_id=?",
        undef,
        $new_product->id, $component->id,
    );
}

#
# schema / install
#

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    $args->{schema}->{bugmail_filters} = {
        FIELDS => [
            id => {
                TYPE       => 'INTSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            user_id => {
                TYPE       => 'INT3',
                NOTNULL    => 1,
                REFERENCES => {
                    TABLE  => 'profiles',
                    COLUMN => 'userid',
                    DELETE => 'CASCADE'
                },
            },
            field_name => {
                # due to fake fields, this can't be field_id
                TYPE       => 'VARCHAR(64)',
                NOTNULL    => 0,
            },
            product_id => {
                TYPE       => 'INT2',
                NOTNULL    => 0,
                REFERENCES => {
                    TABLE  => 'products',
                    COLUMN => 'id',
                    DELETE => 'CASCADE'
                },
            },
            component_id => {
                TYPE       => 'INT2',
                NOTNULL    => 0,
                REFERENCES => {
                    TABLE  => 'components',
                    COLUMN => 'id',
                    DELETE => 'CASCADE'
                },
            },
            relationship => {
                TYPE       => 'INT2',
                NOTNULL    => 0,
            },
            action => {
                TYPE       => 'INT1',
                NOTNULL    => 1,
            },
        ],
        INDEXES => [
            bugmail_filters_unique_idx => {
                FIELDS  => [ qw( user_id field_name product_id component_id
                                 relationship ) ],
                TYPE    => 'UNIQUE',
            },
            bugmail_filters_user_idx => [
                'user_id',
            ],
        ],
    };
}

__PACKAGE__->NAME;
