# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BzAPI::Resources::Bug;

use 5.10.1;
use strict;

use Bugzilla::Bug;
use Bugzilla::Error;
use Bugzilla::Token qw(issue_hash_token);
use Bugzilla::Util qw(trick_taint diff_arrays);
use Bugzilla::WebService::Constants;

use Bugzilla::Extension::BzAPI::Util;
use Bugzilla::Extension::BzAPI::Constants;

use List::MoreUtils qw(uniq);
use List::Util qw(max);

#################
# REST Handlers #
#################

BEGIN {
    require Bugzilla::WebService::Bug;
    *Bugzilla::WebService::Bug::get_bug_count = \&get_bug_count_resource;
}

sub rest_handlers {
    my $rest_handlers = [
        qr{^/bug$}, {
            GET  => {
                request  => \&search_bugs_request,
                response => \&search_bugs_response
            },
            POST => {
                request  => \&create_bug_request,
                response => \&create_bug_response
            }
        },
        qr{^/bug/([^/]+)$}, {
            GET => {
                response => \&get_bug_response
            },
            PUT => {
                request  => \&update_bug_request,
                response => \&update_bug_response
            }
        },
        qr{^/bug/([^/]+)/comment$}, {
            GET  => {
                response => \&get_comments_response
            },
            POST => {
                request  => \&add_comment_request,
                response => \&add_comment_response
            }
        },
        qr{^/bug/([^/]+)/history$}, {
            GET => {
                response => \&get_history_response
            }
        },
        qr{^/bug/([^/]+)/attachment$}, {
            GET  => {
                response => \&get_attachments_response
            },
            POST => {
                request  => \&add_attachment_request,
                response => \&add_attachment_response
            }
        },
        qr{^/bug/attachment/([^/]+)$}, {
            GET => {
                response => \&get_attachment_response
            },
            PUT => {
                request  => \&update_attachment_request,
                response => \&update_attachment_response
            }
        },
        qr{^/attachment/([^/]+)$}, {
            GET => {
                response => \&get_attachment_response
            },
            PUT => {
                request  => \&update_attachment_request,
                response => \&update_attachment_response
            }
        },
        qr{^/bug/([^/]+)/flag$}, {
            GET => {
                resource => {
                    method => 'get',
                    params => sub {
                        return { ids => [ $_[0] ],
                                 include_fields => ['flags'] };
                    }
                },
                response => \&get_bug_flags_response,
            }
        },
        qr{^/count$}, {
            GET => {
                resource => {
                    method => 'get_bug_count'
                }
            }
        },
        qr{^/attachment/([^/]+)$}, {
            GET => {
                resource => {
                    method => 'attachments',
                    params => sub {
                        return { attachment_ids => [ $_[0] ] };
                    }
                }
            },
            PUT => {
                resource => {
                    method => 'update_attachment',
                    params => sub {
                        return { ids => [ $_[0] ] };
                    }
                }
            }
        }
    ];
    return $rest_handlers;
}

#########################
# REST Resource Methods #
#########################

# Return bug counts based on row/col/table fields
# FIXME Borrowed a lot of code from report.cgi, eventually
# this should be broken into it's own module so that report.cgi
# and here can share the same code.
sub get_bug_count_resource {
    my ($self, $params) = @_;

    Bugzilla->switch_to_shadow_db();

    my $col_field = $params->{x_axis_field} || '';
    my $row_field = $params->{y_axis_field} || '';
    my $tbl_field = $params->{z_axis_field} || '';

    my $dimensions = $col_field ?
                     $row_field ?
                     $tbl_field ? 3 : 2 : 1 : 0;

    if ($dimensions == 0) {
        $col_field = "bug_status";
        $params->{x_axis_field} = "bug_status";
    }

    # Valid bug fields that can be reported on.
    my $valid_columns = Bugzilla::Search::REPORT_COLUMNS;

    # Convert external names to internal if necessary
    $params = Bugzilla::Bug::map_fields($params);
    $row_field = Bugzilla::Bug::FIELD_MAP->{$row_field} || $row_field;
    $col_field = Bugzilla::Bug::FIELD_MAP->{$col_field} || $col_field;
    $tbl_field = Bugzilla::Bug::FIELD_MAP->{$tbl_field} || $tbl_field;

    # Validate the values in the axis fields or throw an error.
    !$row_field
        || ($valid_columns->{$row_field} && trick_taint($row_field))
        || ThrowCodeError("report_axis_invalid", { fld => "x", val => $row_field });
    !$col_field
        || ($valid_columns->{$col_field} && trick_taint($col_field))
        || ThrowCodeError("report_axis_invalid", { fld => "y", val => $col_field });
    !$tbl_field
        || ($valid_columns->{$tbl_field} && trick_taint($tbl_field))
        || ThrowCodeError("report_axis_invalid", { fld => "z", val => $tbl_field });

    my @axis_fields = grep { $_ } ($row_field, $col_field, $tbl_field);

    my $search = new Bugzilla::Search(
        fields => \@axis_fields,
        params => $params,
        allow_unlimited => 1,
    );

    my ($results, $extra_data) = $search->data;

    # We have a hash of hashes for the data itself, and a hash to hold the
    # row/col/table names.
    my %data;
    my %names;

    # Read the bug data and count the bugs for each possible value of row, column
    # and table.
    #
    # We detect a numerical field, and sort appropriately, if all the values are
    # numeric.
    my $col_isnumeric = 1;
    my $row_isnumeric = 1;
    my $tbl_isnumeric = 1;

    foreach my $result (@$results) {
        # handle empty dimension member names
        my $row = check_value($row_field, $result);
        my $col = check_value($col_field, $result);
        my $tbl = check_value($tbl_field, $result);

        $data{$tbl}{$col}{$row}++;
        $names{"col"}{$col}++;
        $names{"row"}{$row}++;
        $names{"tbl"}{$tbl}++;

        $col_isnumeric &&= ($col =~ /^-?\d+(\.\d+)?$/o);
        $row_isnumeric &&= ($row =~ /^-?\d+(\.\d+)?$/o);
        $tbl_isnumeric &&= ($tbl =~ /^-?\d+(\.\d+)?$/o);
    }

    my @col_names = get_names($names{"col"}, $col_isnumeric, $col_field);
    my @row_names = get_names($names{"row"}, $row_isnumeric, $row_field);
    my @tbl_names = get_names($names{"tbl"}, $tbl_isnumeric, $tbl_field);

    push(@tbl_names, "-total-") if (scalar(@tbl_names) > 1);

    my @data;
    foreach my $tbl (@tbl_names) {
        my @tbl_data;
        foreach my $row (@row_names) {
            my @col_data;
            foreach my $col (@col_names) {
                $data{$tbl}{$col}{$row} = $data{$tbl}{$col}{$row} || 0;
                push(@col_data, $data{$tbl}{$col}{$row});
                if ($tbl ne "-total-") {
                    # This is a bit sneaky. We spend every loop except the last
                    # building up the -total- data, and then last time round,
                    # we process it as another tbl, and push() the total values
                    # into the image_data array.
                    $data{"-total-"}{$col}{$row} += $data{$tbl}{$col}{$row};
                }
            }
            push(@tbl_data, \@col_data);
        }
        push(@data, \@tbl_data);
    }

    my $result = {};
    if ($dimensions == 0) {
        my $sum = 0;

        # If the search returns no results, we just get an 0-byte file back
        # and so there is no data at all.
        if (@data) {
            foreach my $value (@{ $data[0][0] }) {
                $sum += $value;
            }
        }

        $result = {
            'data' => $sum
        };
    }
    elsif ($dimensions == 1) {
        $result = {
            'x_labels' => \@col_names,
            'data'     => $data[0][0] || []
        };
    }
    elsif ($dimensions == 2) {
        $result = {
            'x_labels' => \@col_names,
            'y_labels' => \@row_names,
            'data'     => $data[0] || [[]]
        };
    }
    elsif ($dimensions == 3) {
        if (@data > 1 && $tbl_names[-1] eq "-total-") {
            # Last table is a total, which we discard
            pop(@data);
            pop(@tbl_names);
        }

        $result = {
            'x_labels' => \@col_names,
            'y_labels' => \@row_names,
            'z_labels' => \@tbl_names,
            'data'     => @data ? \@data : [[[]]]
        };
    }

    return $result;
}

sub get_names {
    my ($names, $isnumeric, $field_name) = @_;
    my ($field, @sorted);
    # XXX - This is a hack to handle the actual_time/work_time field,
    # because it's named 'actual_time' in Search.pm but 'work_time' in Field.pm.
    $_[2] = $field_name = 'work_time' if $field_name eq 'actual_time';

    # _realname fields aren't real Bugzilla::Field objects, but they are a
    # valid axis, so we don't vailidate them as Bugzilla::Field objects.
    $field = Bugzilla::Field->check($field_name)
        if ($field_name && $field_name !~ /_realname$/);

    if ($field && $field->is_select) {
        foreach my $value (@{$field->legal_values}) {
            push(@sorted, $value->name) if $names->{$value->name};
        }
        unshift(@sorted, '---') if $field_name eq 'resolution';
        @sorted = uniq @sorted;
    }
    elsif ($isnumeric) {
        # It's not a field we are preserving the order of, so sort it
        # numerically...
        @sorted = sort { $a <=> $b } keys %$names;
    }
    else {
        # ...or alphabetically, as appropriate.
        @sorted = sort keys %$names;
    }

    return @sorted;
}

sub check_value {
    my ($field, $result) = @_;

    my $value;
    if (!defined $field) {
        $value = '';
    }
    elsif ($field eq '') {
        $value = ' ';
    }
    else {
        $value = shift @$result;
        $value = ' ' if (!defined $value || $value eq '');
        $value = '---' if ($field eq 'resolution' && $value eq ' ');
    }
    return $value;
}

########################
# REST Request Methods #
########################

sub search_bugs_request {
    my ($params) = @_;

    if (defined $params->{changed_field}
        && $params->{changed_field} eq "creation_time")
    {
        $params->{changed_field} = "[Bug creation]";
    }

    my $FIELD_NEW_TO_OLD = { reverse %{ BUG_FIELD_MAP() } };

    # Update values of various forms.
    foreach my $key (keys %$params) {
        # First, search types. These are found in the value of any field ending
        # _type, and the value of any field matching type\d-\d-\d.
        if ($key =~ /^type(\d+)-(\d+)-(\d+)$|_type$/) {
            $params->{$key}
                = BOOLEAN_TYPE_MAP->{$params->{$key}} || $params->{$key};
        }

        # Field names hiding in values instead of keys: changed_field, boolean
        # charts and axis names.
        if ($key =~ /^(field\d+-\d+-\d+|
                    changed_field|
                    (x|y|z)_axis_field)$
                    /x) {
            $params->{$key}
                = $FIELD_NEW_TO_OLD->{$params->{$key}} || $params->{$key};
        }
    }

    # Update field names
    foreach my $field (keys %$FIELD_NEW_TO_OLD) {
        if (defined $params->{$field}) {
            $params->{$FIELD_NEW_TO_OLD->{$field}} = delete $params->{$field};
        }
    }

    if (exists $params->{bug_id_type}) {
        $params->{bug_id_type}
            = BOOLEAN_TYPE_MAP->{$params->{bug_id_type}} || $params->{bug_id_type};
    }

    # Time field names are screwy, and got reused. We can't put this mapping
    # in NEW2OLD as everything will go haywire. actual_time has to be queried
    # as work_time even though work_time is the submit-only field for _adding_
    # to actual_time, which can't be arbitrarily manipulated.
    if (defined $params->{work_time}) {
        $params->{actual_time} = delete $params->{work_time};
    }

    # Other convenience search ariables used by BzAPI
    my @field_ids = grep(/^f(\d+)$/, keys %$params);
    my $last_field_id = @field_ids ? max @field_ids + 1 : 1;
    foreach my $field (qw(setters.login_name requestees.login_name)) {
        if (my $value = delete $params->{$field}) {
            $params->{"f${last_field_id}"} = $FIELD_NEW_TO_OLD->{$field} || $field;
            $params->{"o${last_field_id}"} = 'equals';
            $params->{"v${last_field_id}"} = $value;
            $last_field_id++;
        }
    }
}

sub create_bug_request {
    my ($params) = @_;

    # User roles such as assigned_to and qa_contact should be just the
    # email (login) of the user you want to set to.
    foreach my $field (qw(assigned_to qa_contact)) {
        if (exists $params->{$field}) {
            $params->{$field} = $params->{$field}->{name};
        }
    }

    # CC should just be a list of bugzilla logins
    if (exists $params->{cc}) {
        $params->{cc} = [ map { $_->{name} } @{ $params->{cc} } ];
    }

    # Comment
    if (exists $params->{comments}) {
        $params->{comment_is_private} = $params->{comments}->[0]->{is_private};
        $params->{description} = $params->{comments}->[0]->{text};
        delete $params->{comments};
    }

    # Some fields are not supported by Bugzilla::Bug->create but are supported
    # by Bugzilla::Bug->update :(
    my $cache = Bugzilla->request_cache->{bzapi_bug_create_extra} ||= {};
    foreach my $field (qw(remaining_time)) {
        next if !exists $params->{$field};
        $cache->{$field} = delete $params->{$field};
    }

    # remove username/password
    delete $params->{username};
    delete $params->{password};
}

sub update_bug_request {
    my ($params) = @_;

    my $bug_id = ref $params->{ids} ? $params->{ids}->[0] : $params->{ids};
    my $bug = Bugzilla::Bug->check($bug_id);

    # Convert groups to proper add/remove lists
    if (exists $params->{groups}) {
        my @new_groups = map { $_->{name} } @{ $params->{groups} };
        my @old_groups = map { $_->name } @{ $bug->groups_in };
        my ($removed, $added) = diff_arrays(\@old_groups, \@new_groups);
        if (@$added || @$removed) {
            my $groups_data = {};
            $groups_data->{add} = $added if @$added;
            $groups_data->{remove} = $removed if @$removed;
            $params->{groups} = $groups_data;
        }
        else {
            delete $params->{groups};
        }
    }

    # Other fields such as keywords, blocks depends_on
    # support 'set' which will make the list exactly what
    # the user passes in.
    foreach my $field (qw(blocks depends_on dependson keywords)) {
        if (exists $params->{$field}) {
            $params->{$field} = { set => $params->{$field} };
        }
    }

    # User roles such as assigned_to and qa_contact should be just the
    # email (login) of the user you want to change to. Also if defined
    # but set to NULL then we reset them to default
    foreach my $field (qw(assigned_to qa_contact)) {
        if (exists $params->{$field}) {
            if (!$params->{$field}) {
                $params->{"reset_$field"} = 1;
                delete $params->{$field};
            }
            else {
                $params->{$field} = $params->{$field}->{name};
            }
        }
    }

    # CC is treated like groups in that we need 'add' and 'remove' keys
    if (exists $params->{cc}) {
        my $new_cc = [ map { $_->{name} } @{ $params->{cc} } ];
        my ($removed, $added) = diff_arrays($bug->cc, $new_cc);
        if (@$added || @$removed) {
            my $cc_data = {};
            $cc_data->{add} = $added if @$added;
            $cc_data->{remove} = $removed if @$removed;
            $params->{cc} = $cc_data;
        }
        else {
            delete $params->{cc};
        }
    }

    # see_also is treated like groups in that we need 'add' and 'remove' keys
    if (exists $params->{see_also}) {
        my $old_see_also = [ map { $_->name } @{ $bug->see_also } ];
        my ($removed, $added) = diff_arrays($old_see_also, $params->{see_also});
        if (@$added || @$removed) {
            my $data = {};
            $data->{add} = $added if @$added;
            $data->{remove} = $removed if @$removed;
            $params->{see_also} = $data;
        }
        else {
            delete $params->{see_also};
        }
    }

    # BzAPI allows for adding comments by appending to the list of current
    # comments and passing the whole list back.
    # 1. If a comment id is specified, the user can update the comment privacy
    # 2. If no id is specified it is considered a new comment but only the last
    #    one will be accepted.
    my %comment_is_private;
    foreach my $comment (@{ $params->{'comments'} }) {
        if (my $id = $comment->{'id'}) {
            # Existing comment; tweak privacy flags if necessary
            $comment_is_private{$id}
                = ($comment->{'is_private'} && $comment->{'is_private'} eq "true") ? 1 : 0;
        }
        else {
            # New comment to be added
            # If multiple new comments are specified, only the last one will be
            # added.
            $params->{comment} = {
                body       => $comment->{text},
                is_private => ($comment->{'is_private'} &&
                               $comment->{'is_private'} eq "true") ? 1 : 0
            };
        }
    }
    $params->{comment_is_private} = \%comment_is_private if %comment_is_private;

    # Remove setter and convert requestee to just name
    if (exists $params->{flags}) {
        foreach my $flag (@{ $params->{flags} }) {
            delete $flag->{setter}; # Always use logged in user
            if (exists $flag->{requestee} && ref $flag->{requestee}) {
                $flag->{requestee} = $flag->{requestee}->{name};
            }
            # If no flag id provided, assume it is new
            if (!exists $flag->{id}) {
                $flag->{new} = 1;
            }
        }
    }
}

sub add_comment_request {
    my ($params) = @_;
    $params->{comment} = delete $params->{text} if $params->{text};
}

sub add_attachment_request {
    my ($params) = @_;

    # Bug.add_attachment uses 'summary' for description.
    if ($params->{description}) {
        $params->{summary} = $params->{description};
        delete $params->{description};
    }

    # Remove setter and convert requestee to just name
    if (exists $params->{flags}) {
        foreach my $flag (@{ $params->{flags} }) {
            delete $flag->{setter}; # Always use logged in user
            if (exists $flag->{requestee} && ref $flag->{requestee}) {
                $flag->{requestee} = $flag->{requestee}->{name};
            }
        }
    }

    # Add comment if one is provided
    if (exists $params->{comments} && scalar @{ $params->{comments} }) {
        $params->{comment} = $params->{comments}->[0]->{text};
        delete $params->{comments};
    }
}

sub update_attachment_request {
    my ($params) = @_;

    # Stash away for midair checking later
    if ($params->{last_change_time}) {
        my $stash = Bugzilla->request_cache->{bzapi_stash} ||= {};
        $stash->{last_change_time} = delete $params->{last_change_time};
    }

    # Immutable values
    foreach my $key (qw(attacher bug_id bug_ref creation_time
                        encoding id ref size update_token)) {
        delete $params->{$key};
    }

    # Convert setter and requestee to standard values
    if (exists $params->{flags}) {
        foreach my $flag (@{ $params->{flags} }) {
            delete $flag->{setter}; # Always use logged in user
            if (exists $flag->{requestee} && ref $flag->{requestee}) {
                $flag->{requestee} = $flag->{requestee}->{name};
            }
        }
    }

    # Add comment if one is provided
    if (exists $params->{comments} && scalar @{ $params->{comments} }) {
        $params->{comment} = $params->{comments}->[0]->{text};
        delete $params->{comments};
    }
}

#########################
# REST Response Methods #
#########################

sub search_bugs_response {
    my ($result, $response) = @_;
    my $cache  = Bugzilla->request_cache;
    my $params = Bugzilla->input_params;

    return if !exists $$result->{bugs};

    my $bug_objs = $cache->{bzapi_search_bugs};

    my @fixed_bugs;
    foreach my $bug_data (@{$$result->{bugs}}) {
        my $bug_obj = shift @$bug_objs;
        my $fixed = fix_bug($bug_data, $bug_obj);

        # CC count and Dupe count
        if (filter_wants_nocache($params, 'cc_count')) {
            $fixed->{cc_count} = scalar @{ $bug_obj->cc }
              if $bug_obj->cc;
        }
        if (filter_wants_nocache($params, 'dupe_count')) {
            $fixed->{dupe_count} = scalar @{ $bug_obj->duplicate_ids }
              if $bug_obj->duplicate_ids;
        }

        push(@fixed_bugs, $fixed);
    }

    $$result->{bugs} = \@fixed_bugs;
}

sub create_bug_response {
    my ($result, $response) = @_;
    my $rpc = Bugzilla->request_cache->{bzapi_rpc};

    return if !exists $$result->{id};
    my $bug_id = $$result->{id};

    $$result = { ref => $rpc->type('string', ref_urlbase() . "/bug/$bug_id") };
    $response->code(STATUS_CREATED);
}

sub get_bug_response {
    my ($result) = @_;
    my $rpc = Bugzilla->request_cache->{bzapi_rpc};

    return if !exists $$result->{bugs};
    my $bug_data = $$result->{bugs}->[0];

    my $bug_id = $rpc->bz_rest_params->{ids}->[0];
    my $bug_obj = Bugzilla::Bug->check($bug_id);
    my $fixed = fix_bug($bug_data, $bug_obj);

    $$result = $fixed;
}

sub update_bug_response {
    my ($result) = @_;
    return if !exists $$result->{bugs}
              || !scalar @{$$result->{bugs}};
    $$result = { ok => 1 };
}

# Get all comments for a bug
sub get_comments_response {
    my ($result) = @_;
    my $rpc    = Bugzilla->request_cache->{bzapi_rpc};
    my $params = Bugzilla->input_params;

    return if !exists $$result->{bugs};

    my $bug_id = $rpc->bz_rest_params->{ids}->[0];
    my $bug = Bugzilla::Bug->check($bug_id);

    my $comment_objs = $bug->comments({ order => 'oldest_to_newest',
                                        after => $params->{new_since} });
    my @filtered_comment_objs;
    foreach my $comment (@$comment_objs) {
        next if $comment->is_private && !Bugzilla->user->is_insider;
        push(@filtered_comment_objs, $comment);
    }

    my $comments_data = $$result->{bugs}->{$bug_id}->{comments};

    my @fixed_comments;
    foreach my $comment_data (@$comments_data) {
        my $comment_obj = shift @filtered_comment_objs;
        my $fixed = fix_comment($comment_data, $comment_obj);

        if (exists $fixed->{creator}) {
            # /bug/<ID>/comment returns full login for creator but not for /bug/<ID>?include_fields=comments :(
            $fixed->{creator}->{name} = $rpc->type('string', $comment_obj->author->login);
            # /bug/<ID>/comment does not return real_name for creator but returns ref
            $fixed->{creator}->{'ref'} = $rpc->type('string', ref_urlbase() . "/user/" . $comment_obj->author->login);
            delete $fixed->{creator}->{real_name};
        }

        push(@fixed_comments, filter($params, $fixed));
    }

    $$result = { comments => \@fixed_comments };
}

# Format the return response on successful comment creation
sub add_comment_response {
    my ($result, $response) = @_;
    my $rpc = Bugzilla->request_cache->{bzapi_rpc};

    return if !exists $$result->{id};
    my $bug_id = $rpc->bz_rest_params->{id};

    $$result = { ref => $rpc->type('string', ref_urlbase() . "/bug/$bug_id/comment") };
    $response->code(STATUS_CREATED);
}

# Get the history for a bug
sub get_history_response {
    my ($result) = @_;
    my $params = Bugzilla->input_params;

    return if !exists $$result->{bugs};
    my $history = $$result->{bugs}->[0]->{history};

    my @new_history;
    foreach my $changeset (@$history) {
        $changeset = fix_changeset($changeset);
        push(@new_history, filter($params, $changeset));
    }

    $$result = { history => \@new_history };
}

# Get all attachments for a bug
sub get_attachments_response {
    my ($result) = @_;
    my $rpc    = Bugzilla->request_cache->{bzapi_rpc};
    my $params = Bugzilla->input_params;

    return if !exists $$result->{bugs};
    my $bug_id = $rpc->bz_rest_params->{ids}->[0];
    my $bug = Bugzilla::Bug->check($bug_id);
    my $attachment_objs = $bug->attachments;

    my $attachments_data = $$result->{bugs}->{$bug_id};

    my @fixed_attachments;
    foreach my $attachment (@$attachments_data) {
        my $attachment_obj = shift @$attachment_objs;
        my $fixed = fix_attachment($attachment, $attachment_obj);

        if ((filter_wants_nocache($params, 'data', 'extra')
            || filter_wants_nocache($params, 'encoding', 'extra')
            || $params->{attachmentdata}))
        {
            if (!$fixed->{data}) {
                $fixed->{data} = $rpc->type('base64', $attachment_obj->data);
                $fixed->{encoding} = $rpc->type('string', 'base64');
            }
        }
        else {
            delete $fixed->{data};
            delete $fixed->{encoding};
        }

        push(@fixed_attachments, filter($params, $fixed));
    }

    $$result = { attachments => \@fixed_attachments };
}

# Format the return response on successful attachment creation
sub add_attachment_response {
    my ($result, $response) = @_;
    my $rpc = Bugzilla->request_cache->{bzapi_rpc};

    my ($attach_id) = keys %{ $$result->{attachments} };

    $$result = { ref => $rpc->type('string', ref_urlbase() . "/attachment/$attach_id"), id => $attach_id };
    $response->code(STATUS_CREATED);
}

# Update an attachment's metadata
sub update_attachment_response {
    my ($result) = @_;
    $$result = { ok => 1 };
}

# Get a single attachment by attachment_id
sub get_attachment_response {
    my ($result) = @_;
    my $rpc    = Bugzilla->request_cache->{bzapi_rpc};
    my $params = Bugzilla->input_params;

    return if !exists $$result->{attachments};
    my $attach_id = $rpc->bz_rest_params->{attachment_ids}->[0];
    my $attachment_data = $$result->{attachments}->{$attach_id};
    my $attachment_obj = Bugzilla::Attachment->new($attach_id);
    my $fixed = fix_attachment($attachment_data, $attachment_obj);

    if ((filter_wants_nocache($params, 'data', 'extra')
        || filter_wants_nocache($params, 'encoding', 'extra')
        || $params->{attachmentdata}))
    {
        if (!$fixed->{data}) {
            $fixed->{data} = $rpc->type('base64', $attachment_obj->data);
            $fixed->{encoding} = $rpc->type('string', 'base64');
        }
    }
    else {
        delete $fixed->{data};
        delete $fixed->{encoding};
    }

    $fixed = filter($params, $fixed);

    $$result = $fixed;
}

# Get a list of flags for a bug
sub get_bug_flags_response {
    my ($result) = @_;
    my $params = Bugzilla->input_params;

    return if !exists $$result->{bugs};
    my $flags = $$result->{bugs}->[0]->{flags};

    my @new_flags;
    foreach my $flag (@$flags) {
        push(@new_flags, fix_flag($flag));
    }

    $$result = { flags => \@new_flags };
}

1;
