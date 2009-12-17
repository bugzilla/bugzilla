# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# Contributor(s): Tiago R. Mello <timello@async.com.br>
#                 Frédéric Buclin <LpSolit@gmail.com>

use strict;

package Bugzilla::Product;

use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::Group;
use Bugzilla::Version;
use Bugzilla::Milestone;
use Bugzilla::Field;
use Bugzilla::Status;
use Bugzilla::Install::Requirements;
use Bugzilla::Mailer;
use Bugzilla::Series;
use Bugzilla::Hook;

# Currently, we only implement enough of the Bugzilla::Field::Choice
# interface to control the visibility of other fields.
use base qw(Bugzilla::Field::Choice);

use constant DEFAULT_CLASSIFICATION_ID => 1;

###############################
####    Initialization     ####
###############################

use constant DB_TABLE => 'products';
# Reset these back to the Bugzilla::Object defaults, instead of the
# Bugzilla::Field::Choice defaults.
use constant NAME_FIELD => 'name';
use constant LIST_ORDER => 'name';

use constant DB_COLUMNS => qw(
   id
   name
   classification_id
   description
   isactive
   votesperuser
   maxvotesperbug
   votestoconfirm
   defaultmilestone
   allows_unconfirmed
);

use constant REQUIRED_CREATE_FIELDS => qw(
    name
    description
    version
);

use constant UPDATE_COLUMNS => qw(
    name
    description
    defaultmilestone
    isactive
    votesperuser
    maxvotesperbug
    votestoconfirm
    allows_unconfirmed
);

use constant VALIDATORS => {
    allows_unconfirmed => \&Bugzilla::Object::check_boolean,
    classification   => \&_check_classification,
    name             => \&_check_name,
    description      => \&_check_description,
    version          => \&_check_version,
    defaultmilestone => \&_check_default_milestone,
    isactive         => \&Bugzilla::Object::check_boolean,
    votesperuser     => \&_check_votes_per_user,
    maxvotesperbug   => \&_check_votes_per_bug,
    votestoconfirm   => \&_check_votes_to_confirm,
    create_series    => \&Bugzilla::Object::check_boolean
};

###############################
####     Constructors     #####
###############################

sub create {
    my $class = shift;
    my $dbh = Bugzilla->dbh;

    $dbh->bz_start_transaction();

    $class->check_required_create_fields(@_);

    my $params = $class->run_create_validators(@_);
    # Some fields do not exist in the DB as is.
    if (defined $params->{classification}) {
        $params->{classification_id} = delete $params->{classification}; 
    }
    my $version = delete $params->{version};
    my $create_series = delete $params->{create_series};

    my $product = $class->insert_create_data($params);
    Bugzilla->user->clear_product_cache();

    # Add the new version and milestone into the DB as valid values.
    Bugzilla::Version->create({name => $version, product => $product});
    Bugzilla::Milestone->create({ name => $product->default_milestone, 
                                  product => $product });

    # Create groups and series for the new product, if requested.
    $product->_create_bug_group() if Bugzilla->params->{'makeproductgroups'};
    $product->_create_series() if $create_series;

    Bugzilla::Hook::process('product_end_of_create', { product => $product });

    $dbh->bz_commit_transaction();
    return $product;
}

# This is considerably faster than calling new_from_list three times
# for each product in the list, particularly with hundreds or thousands
# of products.
sub preload {
    my ($products) = @_;
    my %prods = map { $_->id => $_ } @$products;
    my @prod_ids = keys %prods;
    return unless @prod_ids;

    my $dbh = Bugzilla->dbh;
    foreach my $field (qw(component version milestone)) {
        my $classname = "Bugzilla::" . ucfirst($field);
        my $objects = $classname->match({ product_id => \@prod_ids });

        # Now populate the products with this set of objects.
        foreach my $obj (@$objects) {
            my $product_id = $obj->product_id;
            $prods{$product_id}->{"${field}s"} ||= [];
            push(@{$prods{$product_id}->{"${field}s"}}, $obj);
        }
    }
}

sub update {
    my $self = shift;
    my $dbh = Bugzilla->dbh;

    # Don't update the DB if something goes wrong below -> transaction.
    $dbh->bz_start_transaction();
    my ($changes, $old_self) = $self->SUPER::update(@_);

    # We also have to fix votes.
    my @msgs; # Will store emails to send to voters.
    if ($changes->{maxvotesperbug} || $changes->{votesperuser} || $changes->{votestoconfirm}) {
        # We cannot |use| these modules, due to dependency loops.
        require Bugzilla::Bug;
        import Bugzilla::Bug qw(RemoveVotes CheckIfVotedConfirmed);
        require Bugzilla::User;
        import Bugzilla::User qw(user_id_to_login);

        # 1. too many votes for a single user on a single bug.
        my @toomanyvotes_list = ();
        if ($self->max_votes_per_bug < $self->votes_per_user) {
            my $votes = $dbh->selectall_arrayref(
                        'SELECT votes.who, votes.bug_id
                           FROM votes
                                INNER JOIN bugs
                                ON bugs.bug_id = votes.bug_id
                          WHERE bugs.product_id = ?
                                AND votes.vote_count > ?',
                         undef, ($self->id, $self->max_votes_per_bug));

            foreach my $vote (@$votes) {
                my ($who, $id) = (@$vote);
                # If some votes are removed, RemoveVotes() returns a list
                # of messages to send to voters.
                push(@msgs, RemoveVotes($id, $who, 'votes_too_many_per_bug'));
                my $name = user_id_to_login($who);

                push(@toomanyvotes_list, {id => $id, name => $name});
            }
        }
        $changes->{'too_many_votes'} = \@toomanyvotes_list;

        # 2. too many total votes for a single user.
        # This part doesn't work in the general case because RemoveVotes
        # doesn't enforce votesperuser (except per-bug when it's less
        # than maxvotesperbug).  See Bugzilla::Bug::RemoveVotes().

        my $votes = $dbh->selectall_arrayref(
                    'SELECT votes.who, votes.vote_count
                       FROM votes
                            INNER JOIN bugs
                            ON bugs.bug_id = votes.bug_id
                      WHERE bugs.product_id = ?',
                     undef, $self->id);

        my %counts;
        foreach my $vote (@$votes) {
            my ($who, $count) = @$vote;
            if (!defined $counts{$who}) {
                $counts{$who} = $count;
            } else {
                $counts{$who} += $count;
            }
        }
        my @toomanytotalvotes_list = ();
        foreach my $who (keys(%counts)) {
            if ($counts{$who} > $self->votes_per_user) {
                my $bug_ids = $dbh->selectcol_arrayref(
                              'SELECT votes.bug_id
                                 FROM votes
                                      INNER JOIN bugs
                                      ON bugs.bug_id = votes.bug_id
                                WHERE bugs.product_id = ?
                                      AND votes.who = ?',
                               undef, ($self->id, $who));

                foreach my $bug_id (@$bug_ids) {
                    # RemoveVotes() returns a list of messages to send
                    # in case some voters had too many votes.
                    push(@msgs, RemoveVotes($bug_id, $who, 'votes_too_many_per_user'));
                    my $name = user_id_to_login($who);

                    push(@toomanytotalvotes_list, {id => $bug_id, name => $name});
                }
            }
        }
        $changes->{'too_many_total_votes'} = \@toomanytotalvotes_list;

        # 3. enough votes to confirm
        my $bug_list =
          $dbh->selectcol_arrayref('SELECT bug_id FROM bugs WHERE product_id = ?
                                    AND bug_status = ? AND votes >= ?',
                      undef, ($self->id, 'UNCONFIRMED', $self->votes_to_confirm));

        my @updated_bugs = ();
        foreach my $bug_id (@$bug_list) {
            my $confirmed = CheckIfVotedConfirmed($bug_id);
            push (@updated_bugs, $bug_id) if $confirmed;
        }
        $changes->{'confirmed_bugs'} = \@updated_bugs;
    }

    # Also update group settings.
    if ($self->{check_group_controls}) {
        require Bugzilla::Bug;
        import Bugzilla::Bug qw(LogActivityEntry);

        my $old_settings = $old_self->group_controls;
        my $new_settings = $self->group_controls;
        my $timestamp = $dbh->selectrow_array('SELECT NOW()');

        foreach my $gid (keys %$new_settings) {
            my $old_setting = $old_settings->{$gid} || {};
            my $new_setting = $new_settings->{$gid};
            # If all new settings are 0 for a given group, we delete the entry
            # from group_control_map, so we have to track it here.
            my $all_zero = 1;
            my @fields;
            my @values;

            foreach my $field ('entry', 'membercontrol', 'othercontrol', 'canedit',
                               'editcomponents', 'editbugs', 'canconfirm')
            {
                my $old_value = $old_setting->{$field};
                my $new_value = $new_setting->{$field};
                $all_zero = 0 if $new_value;
                next if (defined $old_value && $old_value == $new_value);
                push(@fields, $field);
                # The value has already been validated.
                detaint_natural($new_value);
                push(@values, $new_value);
            }
            # Is there anything to update?
            next unless scalar @fields;

            if ($all_zero) {
                $dbh->do('DELETE FROM group_control_map
                          WHERE product_id = ? AND group_id = ?',
                          undef, $self->id, $gid);
            }
            else {
                if (exists $old_setting->{group}) {
                    # There is already an entry in the DB.
                    my $set_fields = join(', ', map {"$_ = ?"} @fields);
                    $dbh->do("UPDATE group_control_map SET $set_fields
                              WHERE product_id = ? AND group_id = ?",
                              undef, (@values, $self->id, $gid));
                }
                else {
                    # No entry yet.
                    my $fields = join(', ', @fields);
                    # +2 because of the product and group IDs.
                    my $qmarks = join(',', ('?') x (scalar @fields + 2));
                    $dbh->do("INSERT INTO group_control_map (product_id, group_id, $fields)
                              VALUES ($qmarks)", undef, ($self->id, $gid, @values));
                }
            }

            # If the group is mandatory, restrict all bugs to it.
            if ($new_setting->{membercontrol} == CONTROLMAPMANDATORY) {
                my $bug_ids =
                  $dbh->selectcol_arrayref('SELECT bugs.bug_id
                                              FROM bugs
                                                   LEFT JOIN bug_group_map
                                                   ON bug_group_map.bug_id = bugs.bug_id
                                                   AND group_id = ?
                                             WHERE product_id = ?
                                                   AND bug_group_map.bug_id IS NULL',
                                             undef, $gid, $self->id);

                if (scalar @$bug_ids) {
                    my $sth = $dbh->prepare('INSERT INTO bug_group_map (bug_id, group_id)
                                             VALUES (?, ?)');

                    foreach my $bug_id (@$bug_ids) {
                        $sth->execute($bug_id, $gid);
                        # Add this change to the bug history.
                        LogActivityEntry($bug_id, 'bug_group', '',
                                         $new_setting->{group}->name,
                                         Bugzilla->user->id, $timestamp);
                    }
                    push(@{$changes->{'group_controls'}->{'now_mandatory'}},
                         {name      => $new_setting->{group}->name,
                          bug_count => scalar @$bug_ids});
                }
            }
            # If the group can no longer be used to restrict bugs, remove them.
            elsif ($new_setting->{membercontrol} == CONTROLMAPNA) {
                my $bug_ids =
                  $dbh->selectcol_arrayref('SELECT bugs.bug_id
                                              FROM bugs
                                                   INNER JOIN bug_group_map
                                                   ON bug_group_map.bug_id = bugs.bug_id
                                             WHERE product_id = ? AND group_id = ?',
                                             undef, $self->id, $gid);

                if (scalar @$bug_ids) {
                    $dbh->do('DELETE FROM bug_group_map WHERE group_id = ? AND ' .
                              $dbh->sql_in('bug_id', $bug_ids), undef, $gid);

                    # Add this change to the bug history.
                    foreach my $bug_id (@$bug_ids) {
                        LogActivityEntry($bug_id, 'bug_group',
                                         $old_setting->{group}->name, '',
                                         Bugzilla->user->id, $timestamp);
                    }
                    push(@{$changes->{'group_controls'}->{'now_na'}},
                         {name => $old_setting->{group}->name,
                          bug_count => scalar @$bug_ids});
                }
            }
        }
    }
    $dbh->bz_commit_transaction();
    # Changes have been committed.
    delete $self->{check_group_controls};
    Bugzilla->user->clear_product_cache();

    # Now that changes have been committed, we can send emails to voters.
    foreach my $msg (@msgs) {
        MessageToMTA($msg);
    }

    return $changes;
}

sub remove_from_db {
    my ($self, $params) = @_;
    my $user = Bugzilla->user;
    my $dbh = Bugzilla->dbh;

    $dbh->bz_start_transaction();

    $self->_check_if_controller();

    if ($self->bug_count) {
        if (Bugzilla->params->{'allowbugdeletion'}) {
            require Bugzilla::Bug;
            foreach my $bug_id (@{$self->bug_ids}) {
                # Note that we allow the user to delete bugs he can't see,
                # which is okay, because he's deleting the whole Product.
                my $bug = new Bugzilla::Bug($bug_id);
                $bug->remove_from_db();
            }
        }
        else {
            ThrowUserError('product_has_bugs', { nb => $self->bug_count });
        }
    }

    if ($params->{delete_series}) {
        my $series_ids =
          $dbh->selectcol_arrayref('SELECT series_id
                                      FROM series
                                INNER JOIN series_categories
                                        ON series_categories.id = series.category
                                     WHERE series_categories.name = ?',
                                    undef, $self->name);

        $dbh->do('DELETE FROM series WHERE ' . $dbh->sql_in('series_id', $series_ids));

        # If no subcategory uses this product name, completely purge it.
        my $in_use =
          $dbh->selectrow_array('SELECT 1
                                   FROM series
                             INNER JOIN series_categories
                                     ON series_categories.id = series.subcategory
                                  WHERE series_categories.name = ? ' .
                                   $dbh->sql_limit(1),
                                  undef, $self->name);
        if (!$in_use) {
            $dbh->do('DELETE FROM series_categories WHERE name = ?', undef, $self->name);
        }
    }

    $dbh->do("DELETE FROM products WHERE id = ?", undef, $self->id);

    $dbh->bz_commit_transaction();

    # We have to delete these internal variables, else we get
    # the old lists of products and classifications again.
    delete $user->{selectable_products};
    delete $user->{selectable_classifications};

}

###############################
####      Validators       ####
###############################

sub _check_classification {
    my ($invocant, $classification_name) = @_;

    my $classification_id = 1;
    if (Bugzilla->params->{'useclassification'}) {
        my $classification = Bugzilla::Classification->check($classification_name);
        $classification_id = $classification->id;
    }
    return $classification_id;
}

sub _check_name {
    my ($invocant, $name) = @_;

    $name = trim($name);
    $name || ThrowUserError('product_blank_name');

    if (length($name) > MAX_PRODUCT_SIZE) {
        ThrowUserError('product_name_too_long', {'name' => $name});
    }

    my $product = new Bugzilla::Product({name => $name});
    if ($product && (!ref $invocant || $product->id != $invocant->id)) {
        # Check for exact case sensitive match:
        if ($product->name eq $name) {
            ThrowUserError('product_name_already_in_use', {'product' => $product->name});
        }
        else {
            ThrowUserError('product_name_diff_in_case', {'product'          => $name,
                                                         'existing_product' => $product->name});
        }
    }
    return $name;
}

sub _check_description {
    my ($invocant, $description) = @_;

    $description  = trim($description);
    $description || ThrowUserError('product_must_have_description');
    return $description;
}

sub _check_version {
    my ($invocant, $version) = @_;

    $version = trim($version);
    $version || ThrowUserError('product_must_have_version');
    # We will check the version length when Bugzilla::Version->create will do it.
    return $version;
}

sub _check_default_milestone {
    my ($invocant, $milestone) = @_;

    # Do nothing if target milestones are not in use.
    unless (Bugzilla->params->{'usetargetmilestone'}) {
        return (ref $invocant) ? $invocant->default_milestone : '---';
    }

    $milestone = trim($milestone);

    if (ref $invocant) {
        # The default milestone must be one of the existing milestones.
        my $mil_obj = new Bugzilla::Milestone({name => $milestone, product => $invocant});

        $mil_obj || ThrowUserError('product_must_define_defaultmilestone',
                                   {product   => $invocant->name,
                                    milestone => $milestone});
    }
    else {
        $milestone ||= '---';
    }
    return $milestone;
}

sub _check_milestone_url {
    my ($invocant, $url) = @_;

    # Do nothing if target milestones are not in use.
    unless (Bugzilla->params->{'usetargetmilestone'}) {
        return (ref $invocant) ? $invocant->milestone_url : '';
    }

    $url = trim($url || '');
    return $url;
}

sub _check_votes_per_user {
    return _check_votes(@_, 0);
}

sub _check_votes_per_bug {
    return _check_votes(@_, 10000);
}

sub _check_votes_to_confirm {
    return _check_votes(@_, 0);
}

# This subroutine is only used internally by other _check_votes_* validators.
sub _check_votes {
    my ($invocant, $votes, $field, $default) = @_;

    detaint_natural($votes);
    # On product creation, if the number of votes is not a valid integer,
    # we silently fall back to the given default value.
    # If the product already exists and the change is illegal, we complain.
    if (!defined $votes) {
        if (ref $invocant) {
            ThrowUserError('product_illegal_votes', {field => $field, votes => $_[1]});
        }
        else {
            $votes = $default;
        }
    }
    return $votes;
}

#####################################
# Implement Bugzilla::Field::Choice #
#####################################

sub field {
    my $invocant = shift;
    my $class = ref $invocant || $invocant;
    my $cache = Bugzilla->request_cache;
    $cache->{"field_$class"} ||= new Bugzilla::Field({ name => 'product' });
    return $cache->{"field_$class"};
}

use constant is_default => 0;

###############################
####       Methods         ####
###############################

sub _create_bug_group {
    my $self = shift;
    my $dbh = Bugzilla->dbh;

    my $group_name = $self->name;
    while (new Bugzilla::Group({name => $group_name})) {
        $group_name .= '_';
    }
    my $group_description = get_text('bug_group_description', {product => $self});

    my $group = Bugzilla::Group->create({name        => $group_name,
                                         description => $group_description,
                                         isbuggroup  => 1});

    # Associate the new group and new product.
    $dbh->do('INSERT INTO group_control_map
              (group_id, product_id, membercontrol, othercontrol)
              VALUES (?, ?, ?, ?)',
              undef, ($group->id, $self->id, CONTROLMAPDEFAULT, CONTROLMAPNA));
}

sub _create_series {
    my $self = shift;

    my @series;
    # We do every status, every resolution, and an "opened" one as well.
    foreach my $bug_status (@{get_legal_field_values('bug_status')}) {
        push(@series, [$bug_status, "bug_status=" . url_quote($bug_status)]);
    }

    foreach my $resolution (@{get_legal_field_values('resolution')}) {
        next if !$resolution;
        push(@series, [$resolution, "resolution=" . url_quote($resolution)]);
    }

    my @openedstatuses = BUG_STATE_OPEN;
    my $query = join("&", map { "bug_status=" . url_quote($_) } @openedstatuses);
    push(@series, [get_text('series_all_open'), $query]);

    foreach my $sdata (@series) {
        my $series = new Bugzilla::Series(undef, $self->name,
                        get_text('series_subcategory'),
                        $sdata->[0], Bugzilla->user->id, 1,
                        $sdata->[1] . "&product=" . url_quote($self->name), 1);
        $series->writeToDatabase();
    }
}

sub set_name { $_[0]->set('name', $_[1]); }
sub set_description { $_[0]->set('description', $_[1]); }
sub set_default_milestone { $_[0]->set('defaultmilestone', $_[1]); }
sub set_is_active { $_[0]->set('isactive', $_[1]); }
sub set_votes_per_user { $_[0]->set('votesperuser', $_[1]); }
sub set_votes_per_bug { $_[0]->set('maxvotesperbug', $_[1]); }
sub set_votes_to_confirm { $_[0]->set('votestoconfirm', $_[1]); }
sub set_allows_unconfirmed { $_[0]->set('allows_unconfirmed', $_[1]); }

sub set_group_controls {
    my ($self, $group, $settings) = @_;

    $group->is_active_bug_group
      || ThrowUserError('product_illegal_group', {group => $group});

    scalar(keys %$settings)
      || ThrowCodeError('product_empty_group_controls', {group => $group});

    # We store current settings for this group.
    my $gs = $self->group_controls->{$group->id};
    # If there is no entry for this group yet, create a default hash.
    unless (defined $gs) {
        $gs = { entry          => 0,
                membercontrol  => CONTROLMAPNA,
                othercontrol   => CONTROLMAPNA,
                canedit        => 0,
                editcomponents => 0,
                editbugs       => 0,
                canconfirm     => 0,
                group          => $group };
    }

    # Both settings must be defined, or none of them can be updated.
    if (defined $settings->{membercontrol} && defined $settings->{othercontrol}) {
        #  Legality of control combination is a function of
        #  membercontrol\othercontrol
        #                 NA SH DE MA
        #              NA  +  -  -  -
        #              SH  +  +  +  +
        #              DE  +  -  +  +
        #              MA  -  -  -  +
        foreach my $field ('membercontrol', 'othercontrol') {
            my ($is_legal) = grep { $settings->{$field} == $_ }
              (CONTROLMAPNA, CONTROLMAPSHOWN, CONTROLMAPDEFAULT, CONTROLMAPMANDATORY);
            defined $is_legal || ThrowCodeError('product_illegal_group_control',
                                   { field => $field, value => $settings->{$field} });
        }
        unless ($settings->{membercontrol} == $settings->{othercontrol}
                || $settings->{membercontrol} == CONTROLMAPSHOWN
                || ($settings->{membercontrol} == CONTROLMAPDEFAULT
                    && $settings->{othercontrol} != CONTROLMAPSHOWN))
        {
            ThrowUserError('illegal_group_control_combination', {groupname => $group->name});
        }
        $gs->{membercontrol} = $settings->{membercontrol};
        $gs->{othercontrol} = $settings->{othercontrol};
    }

    foreach my $field ('entry', 'canedit', 'editcomponents', 'editbugs', 'canconfirm') {
        next unless defined $settings->{$field};
        $gs->{$field} = $settings->{$field} ? 1 : 0;
    }
    $self->{group_controls}->{$group->id} = $gs;
    $self->{check_group_controls} = 1;
}

sub components {
    my $self = shift;
    my $dbh = Bugzilla->dbh;

    if (!defined $self->{components}) {
        my $ids = $dbh->selectcol_arrayref(q{
            SELECT id FROM components
            WHERE product_id = ?
            ORDER BY name}, undef, $self->id);

        require Bugzilla::Component;
        $self->{components} = Bugzilla::Component->new_from_list($ids);
    }
    return $self->{components};
}

sub group_controls {
    my ($self, $full_data) = @_;
    my $dbh = Bugzilla->dbh;

    # By default, we don't return groups which are not listed in
    # group_control_map. If $full_data is true, then we also
    # return groups whose settings could be set for the product.
    my $where_or_and = 'WHERE';
    my $and_or_where = 'AND';
    if ($full_data) {
        $where_or_and = 'AND';
        $and_or_where = 'WHERE';
    }

    # If $full_data is true, we collect all the data in all cases,
    # even if the cache is already populated.
    # $full_data is never used except in the very special case where
    # all configurable bug groups are displayed to administrators,
    # so we don't care about collecting all the data again in this case.
    if (!defined $self->{group_controls} || $full_data) {
        # Include name to the list, to allow us sorting data more easily.
        my $query = qq{SELECT id, name, entry, membercontrol, othercontrol,
                              canedit, editcomponents, editbugs, canconfirm
                         FROM groups
                              LEFT JOIN group_control_map
                              ON id = group_id 
                $where_or_and product_id = ?
                $and_or_where isbuggroup = 1};
        $self->{group_controls} = 
            $dbh->selectall_hashref($query, 'id', undef, $self->id);

        # For each group ID listed above, create and store its group object.
        my @gids = keys %{$self->{group_controls}};
        my $groups = Bugzilla::Group->new_from_list(\@gids);
        $self->{group_controls}->{$_->id}->{group} = $_ foreach @$groups;
    }

    # We never cache bug counts, for the same reason as above.
    if ($full_data) {
        my $counts =
          $dbh->selectall_arrayref('SELECT group_id, COUNT(bugs.bug_id) AS bug_count
                                      FROM bug_group_map
                                INNER JOIN bugs
                                        ON bugs.bug_id = bug_group_map.bug_id
                                     WHERE bugs.product_id = ? ' .
                                     $dbh->sql_group_by('group_id'),
                          {'Slice' => {}}, $self->id);
        foreach my $data (@$counts) {
            $self->{group_controls}->{$data->{group_id}}->{bug_count} = $data->{bug_count};
        }
    }
    return $self->{group_controls};
}

sub groups_mandatory_for {
    my ($self, $user) = @_;
    my $groups = $user->groups_as_string;
    my $mandatory = CONTROLMAPMANDATORY;
    # For membercontrol we don't check group_id IN, because if membercontrol
    # is Mandatory, the group is Mandatory for everybody, regardless of their
    # group membership.
    my $ids = Bugzilla->dbh->selectcol_arrayref(
        "SELECT group_id FROM group_control_map
          WHERE product_id = ?
                AND (membercontrol = $mandatory
                     OR (othercontrol = $mandatory
                         AND group_id NOT IN ($groups)))",
        undef, $self->id);
    return Bugzilla::Group->new_from_list($ids);
}

sub groups_valid {
    my ($self) = @_;
    return $self->{groups_valid} if defined $self->{groups_valid};
    
    # Note that we don't check OtherControl below, because there is no
    # valid NA/* combination.
    my $ids = Bugzilla->dbh->selectcol_arrayref(
        "SELECT DISTINCT group_id
          FROM group_control_map AS gcm
               INNER JOIN groups ON gcm.group_id = groups.id
         WHERE product_id = ? AND isbuggroup = 1
               AND membercontrol != " . CONTROLMAPNA,  undef, $self->id);
    $self->{groups_valid} = Bugzilla::Group->new_from_list($ids);
    return $self->{groups_valid};
}

sub versions {
    my $self = shift;
    my $dbh = Bugzilla->dbh;

    if (!defined $self->{versions}) {
        my $ids = $dbh->selectcol_arrayref(q{
            SELECT id FROM versions
            WHERE product_id = ?}, undef, $self->id);

        $self->{versions} = Bugzilla::Version->new_from_list($ids);
    }
    return $self->{versions};
}

sub milestones {
    my $self = shift;
    my $dbh = Bugzilla->dbh;

    if (!defined $self->{milestones}) {
        my $ids = $dbh->selectcol_arrayref(q{
            SELECT id FROM milestones
             WHERE product_id = ?}, undef, $self->id);
 
        $self->{milestones} = Bugzilla::Milestone->new_from_list($ids);
    }
    return $self->{milestones};
}

sub bug_count {
    my $self = shift;
    my $dbh = Bugzilla->dbh;

    if (!defined $self->{'bug_count'}) {
        $self->{'bug_count'} = $dbh->selectrow_array(qq{
            SELECT COUNT(bug_id) FROM bugs
            WHERE product_id = ?}, undef, $self->id);

    }
    return $self->{'bug_count'};
}

sub bug_ids {
    my $self = shift;
    my $dbh = Bugzilla->dbh;

    if (!defined $self->{'bug_ids'}) {
        $self->{'bug_ids'} = 
            $dbh->selectcol_arrayref(q{SELECT bug_id FROM bugs
                                       WHERE product_id = ?},
                                     undef, $self->id);
    }
    return $self->{'bug_ids'};
}

sub user_has_access {
    my ($self, $user) = @_;

    return Bugzilla->dbh->selectrow_array(
        'SELECT CASE WHEN group_id IS NULL THEN 1 ELSE 0 END
           FROM products LEFT JOIN group_control_map
                ON group_control_map.product_id = products.id
                   AND group_control_map.entry != 0
                   AND group_id NOT IN (' . $user->groups_as_string . ')
          WHERE products.id = ? ' . Bugzilla->dbh->sql_limit(1),
          undef, $self->id);
}

sub flag_types {
    my $self = shift;

    if (!defined $self->{'flag_types'}) {
        $self->{'flag_types'} = {};
        foreach my $type ('bug', 'attachment') {
            my %flagtypes;
            foreach my $component (@{$self->components}) {
                foreach my $flagtype (@{$component->flag_types->{$type}}) {
                    $flagtypes{$flagtype->{'id'}} ||= $flagtype;
                }
            }
            $self->{'flag_types'}->{$type} = [sort { $a->{'sortkey'} <=> $b->{'sortkey'}
                                                    || $a->{'name'} cmp $b->{'name'} } values %flagtypes];
        }
    }
    return $self->{'flag_types'};
}

###############################
####      Accessors      ######
###############################

sub allows_unconfirmed { return $_[0]->{'allows_unconfirmed'}; }
sub description       { return $_[0]->{'description'};       }
sub is_active         { return $_[0]->{'isactive'};       }
sub votes_per_user    { return $_[0]->{'votesperuser'};      }
sub max_votes_per_bug { return $_[0]->{'maxvotesperbug'};    }
sub votes_to_confirm  { return $_[0]->{'votestoconfirm'};    }
sub default_milestone { return $_[0]->{'defaultmilestone'};  }
sub classification_id { return $_[0]->{'classification_id'}; }

###############################
####      Subroutines    ######
###############################

sub check_product {
    my ($product_name) = @_;

    unless ($product_name) {
        ThrowUserError('product_not_specified');
    }
    my $product = new Bugzilla::Product({name => $product_name});
    unless ($product) {
        ThrowUserError('product_doesnt_exist',
                       {'product' => $product_name});
    }
    return $product;
}

1;

__END__

=head1 NAME

Bugzilla::Product - Bugzilla product class.

=head1 SYNOPSIS

    use Bugzilla::Product;

    my $product = new Bugzilla::Product(1);
    my $product = new Bugzilla::Product({ name => 'AcmeProduct' });

    my @components      = $product->components();
    my $groups_controls = $product->group_controls();
    my @milestones      = $product->milestones();
    my @versions        = $product->versions();
    my $bugcount        = $product->bug_count();
    my $bug_ids         = $product->bug_ids();
    my $has_access      = $product->user_has_access($user);
    my $flag_types      = $product->flag_types();

    my $id               = $product->id;
    my $name             = $product->name;
    my $description      = $product->description;
    my isactive          = $product->is_active;
    my votesperuser      = $product->votes_per_user;
    my maxvotesperbug    = $product->max_votes_per_bug;
    my votestoconfirm    = $product->votes_to_confirm;
    my $defaultmilestone = $product->default_milestone;
    my $classificationid = $product->classification_id;
    my $allows_unconfirmed = $product->allows_unconfirmed;

=head1 DESCRIPTION

Product.pm represents a product object. It is an implementation
of L<Bugzilla::Object>, and thus provides all methods that
L<Bugzilla::Object> provides.

The methods that are specific to C<Bugzilla::Product> are listed 
below.

=head1 METHODS

=over

=item C<components>

 Description: Returns an array of component objects belonging to
              the product.

 Params:      none.

 Returns:     An array of Bugzilla::Component object.

=item C<group_controls()>

 Description: Returns a hash (group id as key) with all product
              group controls.

 Params:      $full_data (optional, false by default) - when true,
              the number of bugs per group applicable to the product
              is also returned. Moreover, bug groups which have no
              special settings for the product are also returned.

 Returns:     A hash with group id as key and hash containing 
              a Bugzilla::Group object and the properties of group
              relative to the product.

=item C<groups_mandatory_for>

=over

=item B<Description>

Tells you what groups are mandatory for bugs in this product.

=item B<Params>

C<$user> - The user who you want to check.

=item B<Returns> An arrayref of C<Bugzilla::Group> objects.

=back

=item C<groups_valid>

=over

=item B<Description>

Returns an arrayref of L<Bugzilla::Group> objects, representing groups
that bugs could validly be restricted to within this product. Used mostly
by L<Bugzilla::Bug> to assure that you're adding valid groups to a bug.

B<Note>: This doesn't check whether or not the current user can add/remove
bugs to/from these groups. It just tells you that bugs I<could be in> these
groups, in this product.

=item B<Params> (none)

=item B<Returns> An arrayref of L<Bugzilla::Group> objects.

=back

=item C<versions>

 Description: Returns all valid versions for that product.

 Params:      none.

 Returns:     An array of Bugzilla::Version objects.

=item C<milestones>

 Description: Returns all valid milestones for that product.

 Params:      none.

 Returns:     An array of Bugzilla::Milestone objects.

=item C<bug_count()>

 Description: Returns the total of bugs that belong to the product.

 Params:      none.

 Returns:     Integer with the number of bugs.

=item C<bug_ids()>

 Description: Returns the IDs of bugs that belong to the product.

 Params:      none.

 Returns:     An array of integer.

=item C<user_has_access()>

 Description: Tells you whether or not the user is allowed to enter
              bugs into this product, based on the C<entry> group
              control. To see whether or not a user can actually
              enter a bug into a product, use C<$user-&gt;can_enter_product>.

 Params:      C<$user> - A Bugzilla::User object.

 Returns      C<1> If this user's groups allow him C<entry> access to
              this Product, C<0> otherwise.

=item C<flag_types()>

 Description: Returns flag types available for at least one of
              its components.

 Params:      none.

 Returns:     Two references to an array of flagtype objects.

=back

=head1 SUBROUTINES

=over

=item C<preload>

When passed an arrayref of C<Bugzilla::Product> objects, preloads their
L</milestones>, L</components>, and L</versions>, which is much faster
than calling those accessors on every item in the array individually.

This function is not exported, so must be called like 
C<Bugzilla::Product::preload($products)>.

=item C<check_product($product_name)>

 Description: Checks if the product name was passed in and if is a valid
              product.

 Params:      $product_name - String with a product name.

 Returns:     Bugzilla::Product object.

=back

=head1 SEE ALSO

L<Bugzilla::Object>

=cut
