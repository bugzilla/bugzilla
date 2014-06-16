# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BzAPI::Util;

use strict;
use warnings;

use Bugzilla;
use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Extension::BzAPI::Constants;
use Bugzilla::Token;
use Bugzilla::Util qw(correct_urlbase email_filter);
use Bugzilla::WebService::Util qw(filter_wants);

use MIME::Base64;

use base qw(Exporter);
our @EXPORT = qw(
    ref_urlbase
    fix_bug
    fix_user
    fix_flag
    fix_comment
    fix_changeset
    fix_attachment
    fix_group
    filter_wants_nocache
    filter
    fix_credentials
    filter_email
);

# Return an URL base appropriate for constructing a ref link
# normally required by REST API calls.
sub ref_urlbase {
    return correct_urlbase() . "bzapi";
}

# convert certain fields within a bug object
# from a simple scalar value to their respective objects
sub fix_bug {
    my ($data, $bug) = @_;
    my $dbh    = Bugzilla->dbh;
    my $params = Bugzilla->input_params;
    my $rpc    = Bugzilla->request_cache->{bzapi_rpc};
    my $method = Bugzilla->request_cache->{bzapi_rpc_method};

    $bug = ref $bug ? $bug : Bugzilla::Bug->check($bug || $data->{id});

    # Add REST API reference to the individual bug
    if (filter_wants_nocache($params, 'ref')) {
        $data->{'ref'} = ref_urlbase() . "/bug/" . $bug->id;
    }

    # User fields
    foreach my $field (USER_FIELDS) {
        next if !exists $data->{$field};
        if ($field eq 'cc') {
            my @new_cc;
            foreach my $cc (@{ $bug->cc_users }) {
                my $cc_data = { name => filter_email($cc->email) };
                push(@new_cc, fix_user($cc_data, $cc));
            }
            $data->{$field} = \@new_cc;
        }
        else {
            my $field_name = $field;
            if ($field eq 'creator') {
                $field_name = 'reporter';
            }
            $data->{$field}
              = fix_user($data->{"${field}_detail"}, $bug->$field_name);
            delete $data->{$field}->{id};
            delete $data->{$field}->{email};
            $data->{$field} = filter($params, $data->{$field}, undef, $field);
        }

        # Get rid of extra detail hash if exists since redundant
        delete $data->{"${field}_detail"} if exists $data->{"${field}_detail"};
    }

    # Groups
    if (filter_wants_nocache($params, 'groups')) {
        my @new_groups;
        foreach my $group (@{ $data->{groups} }) {
            push(@new_groups, fix_group($group));
        }
        $data->{groups} = \@new_groups;
    }

    # Flags
    if (exists $data->{flags}) {
        my @new_flags;
        foreach my $flag (@{ $data->{flags} }) {
            push(@new_flags, fix_flag($flag));
        }
        $data->{flags} = \@new_flags;
    }

    # Attachment metadata is included by default but not data
    if (filter_wants_nocache($params, 'attachments')) {
        my $attachment_params = { ids => $data->{id} };
        if (!filter_wants_nocache($params, 'data', 'extra', 'attachments')
            && !$params->{attachmentdata})
        {
            $attachment_params->{exclude_fields} = ['data'];
        }

        my $attachments = $rpc->attachments($attachment_params);

        my @fixed_attachments;
        foreach my $attachment (@{ $attachments->{bugs}->{$data->{id}} }) {
            my $fixed = fix_attachment($attachment);
            push(@fixed_attachments, filter($params, $fixed, undef, 'attachments'));
        }

        $data->{attachments} = \@fixed_attachments;
    }

    # Comments and history are not part of _default and have to be requested

    # Comments
    if (filter_wants_nocache($params, 'comments', 'extra', 'comments')) {
        my $comments = $rpc->comments({ ids => $data->{id} });
        $comments = $comments->{bugs}->{$data->{id}}->{comments};
        my @new_comments;
        foreach my $comment (@$comments) {
            $comment = fix_comment($comment);
            push(@new_comments, filter($params, $comment, 'extra', 'comments'));
        }
        $data->{comments} = \@new_comments;
    }

    # History
    if (filter_wants_nocache($params, 'history', 'extra', 'history')) {
        my $history = $rpc->history({ ids => [ $data->{id} ] });
        my @new_history;
        foreach my $changeset (@{ $history->{bugs}->[0]->{history} }) {
            push(@new_history, fix_changeset($changeset, $bug));
        }
        $data->{history} = \@new_history;
    }

    # Add in all custom fields even if not set or visible on this bug
    my $custom_fields = Bugzilla->fields({ custom => 1, obsolete => 0 });
    foreach my $field (@$custom_fields) {
        my $name = $field->name;
        next if !filter_wants_nocache($params, $name, ['default','custom']);
        if ($field->type == FIELD_TYPE_BUG_ID) {
            $data->{$name} = $rpc->type('int', $bug->$name);
        }
        elsif ($field->type == FIELD_TYPE_DATETIME
               || $field->type == FIELD_TYPE_DATE)
        {
            $data->{$name} = $rpc->type('dateTime', $bug->$name);
        }
        elsif ($field->type == FIELD_TYPE_MULTI_SELECT) {
            # Bug.search, when include_fields=_all, returns array, otherwise return as comma delimited string :(
            if ($method eq 'Bug.search' && !grep($_ eq '_all', @{ $params->{include_fields} })) {
                $data->{$name} = $rpc->type('string', join(', ', @{ $bug->$name }));
            }
            else {
                my @values = map { $rpc->type('string', $_) } @{ $bug->$name };
                $data->{$name} = \@values;
            }
        }
        else {
            $data->{$name} = $rpc->type('string', $bug->$name);
        }
    }

    foreach my $key (keys %$data) {
        # Remove empty values in some cases
        next if $key eq 'qa_contact'; # Return qa_contact even if null
        next if $method eq 'Bug.search' && $key eq 'keywords'; # Return keywords even if empty
        next if $method eq 'Bug.get' && grep($_ eq $key, TIMETRACKING_FIELDS);

        next if ($method eq 'Bug.search'
                 && $key =~ /^(resolution|cc_count|dupe_count)$/
                 && !grep($_ eq '_all', @{ $params->{include_fields} }));

        if (!ref $data->{$key}) {
            delete $data->{$key} if !$data->{$key};
        }
        else {
            if (ref $data->{$key} eq 'ARRAY' && !@{$data->{$key}}) {
                # Return empty string if blocks or depends_on is empty
                if ($key eq 'depends_on' || $key eq 'blocks') {
                    $data->{$key} = '';
                }
                else {
                    delete $data->{$key};
                }
            }
            elsif (ref $data->{$key} eq 'HASH' && !%{$data->{$key}}) {
                delete $data->{$key};
            }
        }
    }

    return $data;
}

# convert a user related field from being just login
# names to user objects
sub fix_user {
    my ($data, $object) = @_;
    my $user = Bugzilla->user;
    my $rpc  = Bugzilla->request_cache->{bzapi_rpc};

    return { name => undef } if !$data;

    if (!ref $data) {
        $data = {
            name => filter_email($object->login)
        };
        if ($user->id) {
            $data->{real_name} = $rpc->type('string', $object->name);
        }
    }
    else {
        $data->{name} = filter_email($data->{name});
    }

    if ($user->id) {
        $data->{ref} = $rpc->type('string', ref_urlbase . "/user/" . $object->login);
    }

    return $data;
}

# convert certain attributes of a comment to objects
# and also remove other unwanted key/values.
sub fix_comment {
    my ($data, $object) = @_;
    my $rpc = Bugzilla->request_cache->{bzapi_rpc};
    my $method = Bugzilla->request_cache->{bzapi_rpc_method};

    $object ||= Bugzilla::Comment->new({ id => $data->{id}, cache => 1 });

    if (exists $data->{creator}) {
        $data->{creator} = fix_user($data->{creator}, $object->author);
    }

    if ($data->{attachment_id} && $method ne 'Bug.search') {
        $data->{attachment_ref} = $rpc->type('string', ref_urlbase() .
                                             "/attachment/" . $data->{attachment_id});
    }
    else {
        delete $data->{attachment_id};
    }

    delete $data->{author};
    delete $data->{time};

    return $data;
}

# convert certain attributes of a changeset object from
# scalar values to related objects. Also remove other unwanted
# key/values.
sub fix_changeset {
    my ($data, $object) = @_;
    my $user = Bugzilla->user;
    my $rpc  = Bugzilla->request_cache->{bzapi_rpc};

    if ($data->{who}) {
        $data->{changer} = {
            name => filter_email($data->{who}),
            ref  => $rpc->type('string', ref_urlbase() . "/user/" . $data->{who})
        };
        delete $data->{who};
    }

    if ($data->{when}) {
        $data->{change_time} = $rpc->type('dateTime', $data->{when});
        delete $data->{when};
    }

    foreach my $change (@{ $data->{changes} }) {
        $change->{field_name} = 'flag' if $change->{field_name} eq 'flagtypes.name';
    }

    return $data;
}

# convert certain attributes of an attachment object from
# scalar values to related objects. Also add in additional
# key/values.
sub fix_attachment {
    my ($data, $object) = @_;
    my $rpc    = Bugzilla->request_cache->{bzapi_rpc};
    my $method = Bugzilla->request_cache->{bzapi_rpc_method};
    my $params = Bugzilla->input_params;
    my $user   = Bugzilla->user;

    $object ||= Bugzilla::Attachment->new({ id => $data->{id}, cache => 1 });

    if (exists $data->{attacher}) {
        $data->{attacher} = fix_user($data->{attacher}, $object->attacher);
        if ($method eq 'Bug.search') {
            delete $data->{attacher}->{real_name};
        }
        else {
            $data->{attacher}->{real_name} = $rpc->type('string', $object->attacher->name);
        }
    }

    if ($data->{data}) {
        $data->{encoding} = $rpc->type('string', 'base64');
    }

    if (exists $data->{bug_id}) {
        $data->{bug_ref} = $rpc->type('string', ref_urlbase() . "/bug/" . $data->{bug_id});
    }

    # Upstream API returns these as integers where bzapi returns as booleans
    if (exists $data->{is_patch}) {
        $data->{is_patch} = $rpc->type('boolean', $data->{is_patch});
    }
    if (exists $data->{is_obsolete}) {
        $data->{is_obsolete} = $rpc->type('boolean', $data->{is_obsolete});
    }
    if (exists $data->{is_private}) {
        $data->{is_private} = $rpc->type('boolean', $data->{is_private});
    }

    if (exists $data->{flags} && @{ $data->{flags} }) {
        my @new_flags;
        foreach my $flag (@{ $data->{flags} }) {
            push(@new_flags, fix_flag($flag));
        }
        $data->{flags} = \@new_flags;
    }
    else {
        delete $data->{flags};
    }

    $data->{ref} = $rpc->type('string', ref_urlbase() . "/attachment/" . $data->{id});

    # Add update token if we are getting an attachment outside of Bug.get and user is logged in
    if ($user->id && ($method eq 'Bug.attachments'|| $method eq 'Bug.search')) {
        $data->{update_token} = issue_hash_token([ $object->id, $object->modification_time ]);
    }

    delete $data->{creator};
    delete $data->{summary};

    return $data;
}

# convert certain attributes of a flag object from
# scalar values to related objects. Also remove other unwanted
# key/values.
sub fix_flag {
    my ($data, $object) = @_;
    my $rpc = Bugzilla->request_cache->{bzapi_rpc};

    $object ||= Bugzilla::Flag->new({ id => $data->{id}, cache => 1 });

    if (exists $data->{setter}) {
        $data->{setter} = fix_user($data->{setter}, $object->setter);
        delete $data->{setter}->{real_name};
    }

    if (exists $data->{requestee}) {
        $data->{requestee} = fix_user($data->{requestee}, $object->requestee);
        delete $data->{requestee}->{real_name};
    }

    return $data;
}

# convert certain attributes of a group object from scalar
# values to related objects
sub fix_group {
    my ($group, $object) = @_;
    my $rpc = Bugzilla->request_cache->{bzapi_rpc};

    $object ||= Bugzilla::Group->new({ name => $group });

    if ($object) {
        $group = {
            id   => $rpc->type('int', $object->id),
            name => $rpc->type('string', $object->name),
        };
    }

    return $group;
}

# Calls Bugzilla::WebService::Util::filter_wants but disables caching
# as we make several webservice calls in a single REST call and the
# caching can cause unexpected results.
sub filter_wants_nocache {
    my ($params, $field, $types, $prefix) = @_;
    delete Bugzilla->request_cache->{filter_wants};
    return filter_wants($params, $field, $types, $prefix);
}

sub filter {
    my ($params, $hash, $types, $prefix) = @_;
    my %newhash = %$hash;
    foreach my $key (keys %$hash) {
        delete $newhash{$key} if !filter_wants_nocache($params, $key, $types, $prefix);
    }
    return \%newhash;
}

sub fix_credentials {
    my ($params) = @_;
    # Allow user to pass in username=foo&password=bar to be compatible
    $params->{'Bugzilla_login'}    = delete $params->{'username'} if exists $params->{'username'};
    $params->{'Bugzilla_password'} = delete $params->{'password'} if exists $params->{'password'};

    # Allow user to pass userid=1&cookie=3iYGuKZdyz for compatibility with BzAPI
    if (exists $params->{'userid'} && exists $params->{'cookie'}) {
        my $userid = delete $params->{'userid'};
        my $cookie = delete $params->{'cookie'};
        $params->{'Bugzilla_token'} = "${userid}-${cookie}";
    }
}

# Filter email addresses by default ignoring the system
# webservice_email_filter setting
sub filter_email {
    my $rpc = Bugzilla->request_cache->{bzapi_rpc};
    return $rpc->type('string', email_filter($_[0]));
}

1;
