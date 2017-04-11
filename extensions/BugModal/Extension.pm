# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BugModal;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Extension::BugModal::ActivityStream;
use Bugzilla::Extension::BugModal::MonkeyPatches;
use Bugzilla::Extension::BugModal::Util qw(date_str_to_time);
use Bugzilla::Constants;
use Bugzilla::User::Setting;
use Bugzilla::Util qw(trick_taint datetime_from html_quote time_ago);
use List::MoreUtils qw(any);
use Template::Stash;
use JSON::XS qw(encode_json);

our $VERSION = '1';

use constant READABLE_BUG_STATUS_PRODUCTS => (
    'Core',
    'Toolkit',
    'Firefox',
    'Firefox for Android',
    'Firefox for iOS',
    'Bugzilla',
    'bugzilla.mozilla.org'
);

sub show_bug_format {
    my ($self, $args) = @_;
    $args->{format} = _alternative_show_bug_format();
}

sub edit_bug_format {
    my ($self, $args) = @_;
    $args->{format} = _alternative_show_bug_format();
}

sub _alternative_show_bug_format {
    my $cgi = Bugzilla->cgi;
    my $user = Bugzilla->user;
    if (my $ctype = $cgi->param('ctype')) {
        return '' if $ctype ne 'html';
    }
    if (my $format = $cgi->param('format')) {
        return ($format eq '__default__' || $format eq 'default') ? '' : $format;
    }
    return $user->setting('ui_experiments') eq 'on' ? 'modal' : '';
}

sub template_after_create {
    my ($self, $args) = @_;
    my $context = $args->{template}->context;

    # wrapper around time_ago()
    $context->define_filter(
        time_duration => sub {
            my ($context) = @_;
            return sub {
                my ($timestamp) = @_;
                my $datetime = datetime_from($timestamp)
                    // return $timestamp;
                return time_ago($datetime);
            };
        }, 1
    );

    # morph a string into one which is suitable to use as an element's id
    $context->define_filter(
        id => sub {
            my ($context) = @_;
            return sub {
                my ($id) = @_;
                $id //= '';
                $id = lc($id);
                while ($id ne '' && $id !~ /^[a-z]/) {
                    $id = substr($id, 1);
                }
                $id =~ tr/ /-/;
                $id =~ s/[^a-z\d\-_:\.]/_/g;
                return $id;
            };
        }, 1
    );

    # parse date string and output epoch
    $context->define_filter(
        epoch => sub {
            my ($context) = @_;
            return sub {
                my ($date_str) = @_;
                return date_str_to_time($date_str);
            };
        }, 1
    );

    # flatten a list of hashrefs to a list of values
    # eg.  logins = users.pluck("login")
    $context->define_vmethod(
        list => pluck => sub {
            my ($list, $field) = @_;
            return [ map { $_->$field } @$list ];
        }
    );

    # returns array where the value in $field does not equal $value
    # opposite of "only"
    # eg.  not_byron = users.skip("name", "Byron")
    $context->define_vmethod(
        list => skip => sub {
            my ($list, $field, $value) = @_;
            return [ grep { $_->$field ne $value } @$list ];
        }
    );

    # returns array where the value in $field equals $value
    # opposite of "skip"
    # eg.  byrons_only = users.only("name", "Byron")
    $context->define_vmethod(
        list => only => sub {
            my ($list, $field, $value) = @_;
            return [ grep { $_->$field eq $value } @$list ];
        }
    );

    # returns boolean indicating if the value exists in the list
    # eg.  has_byron = user_names.exists("byron")
    $context->define_vmethod(
        list => exists => sub {
            my ($list, $value) = @_;
            return any { $_ eq $value } @$list;
        }
    );

    # ucfirst is only available in new template::toolkit versions
    $context->define_vmethod(
        item => ucfirst => sub {
            my ($text) = @_;
            return ucfirst($text);
        }
    );
}

sub template_before_process {
    my ($self, $args) = @_;
    my $file = $args->{file};
    my $vars = $args->{vars};

    if ($file eq 'bug/process/header.html.tmpl'
        || $file eq 'bug/create/created.html.tmpl'
        || $file eq 'attachment/created.html.tmpl'
        || $file eq 'attachment/updated.html.tmpl')
    {
        if (_alternative_show_bug_format() eq 'modal') {
            $vars->{alt_ui_header} = 'bug_modal/header.html.tmpl';
            $vars->{alt_ui_show}   = 'bug/show-modal.html.tmpl';
            $vars->{alt_ui_edit}   = 'bug_modal/edit.html.tmpl';
        }
        return;
    }

    if ($file =~ m#^bug/show-([^\.]+)\.html\.tmpl$#) {
        my $format = $1;
        return unless _alternative_show_bug_format() eq $format;
    }
    elsif ($file ne 'bug_modal/edit.html.tmpl') {
        return;
    }

    if ($vars->{bug} && !$vars->{bugs}) {
        $vars->{bugs} = [$vars->{bug}];
    }

    return unless
        $vars->{bugs}
        && ref($vars->{bugs}) eq 'ARRAY'
        && scalar(@{ $vars->{bugs} }) == 1;
    my $bug = $vars->{bugs}->[0];
    return if exists $bug->{error};

    # trigger loading of tracking flags
    Bugzilla::Extension::TrackingFlags->template_before_process({
        file => 'bug/edit.html.tmpl',
        vars => $vars,
    });

    if (any { $bug->product eq $_ } READABLE_BUG_STATUS_PRODUCTS) {
        my @flags = map { { name => $_->name, status => $_->status } } @{$bug->flags};
        $vars->{readable_bug_status_json} = encode_json({
            dupe_of    => $bug->dup_id,
            id         => $bug->id,
            keywords   => [ map { $_->name } @{$bug->keyword_objects} ],
            priority   => $bug->priority,
            resolution => $bug->resolution,
            status     => $bug->bug_status,
            flags      => \@flags,
            target_milestone => $bug->target_milestone,
            map { $_->name => $_->bug_flag($bug->id)->value } @{$vars->{tracking_flags}},
        });
        # HTML4 attributes cannot be longer than this, so just skip it in this case.
        if (length($vars->{readable_bug_status_json}) > 65536) {
            delete $vars->{readable_bug_status_json};
        }
    }

    # bug->choices loads a lot of data that we want to lazy-load
    # just load the status and resolutions and perform extra checks here
    # upstream does these checks in the bug/fields template
    my $perms = $bug->user;
    my @resolutions;
    foreach my $r (@{ Bugzilla::Field->new({ name => 'resolution', cache => 1 })->legal_values }) {
        my $resolution = $r->name;
        next unless $resolution;

        # always allow the current value
        if ($resolution eq $bug->resolution) {
            push @resolutions, $r;
            next;
        }

        # never allow inactive values
        next unless $r->is_active;

        # ensure the user has basic rights to change this field
        next unless $bug->check_can_change_field('resolution', '---', $resolution);

        # canconfirm users can only set the resolution to WFM, INCOMPLETE or DUPE
        if ($perms->{canconfirm}
            && !($perms->{canedit} || $perms->{isreporter}))
        {
            next if
                $resolution ne 'WORKSFORME'
                && $resolution ne 'INCOMPLETE'
                && $resolution ne 'DUPLICATE';
        }

        # reporters can set it to anything, except INCOMPLETE
        if ($perms->{isreporter}
            && !($perms->{canconfirm} || $perms->{canedit}))
        {
            next if $resolution eq 'INCOMPLETE';
        }

        # expired has, uh, expired
        next if $resolution eq 'EXPIRED';

        push @resolutions, $r;
    }
    $bug->{choices} = {
        bug_status => [
            grep { $_->is_active || $_->name eq $bug->bug_status }
            @{ $bug->statuses_available }
        ],
        resolution => \@resolutions,
    };

    # group tracking flags by version to allow for a better tabular output
    my @tracking_table;
    my $tracking_flags = $vars->{tracking_flags};
    foreach my $flag (@$tracking_flags) {
        my $flag_type = $flag->flag_type;
        my $type = 'status';
        my $name = $flag->description;
        if ($flag_type eq 'tracking' && $name =~ /^(tracking|status)-(.+)/) {
            ($type, $name) = ($1, $2);
        }

        my ($existing) = grep { $_->{type} eq $flag_type && $_->{name} eq $name } @tracking_table;
        if ($existing) {
            $existing->{$type} = $flag;
        }
        else {
            push @tracking_table, {
                $type   => $flag,
                name    => $name,
                type    => $flag_type,
            };
        }
    }
    $vars->{tracking_flags_table} = \@tracking_table;

    # for the "view -> hide treeherder comments" menu item
    my $treeherder_id = Bugzilla->treeherder_user->id;
    foreach my $change_set (@{ $bug->activity_stream }) {
        if ($change_set->{comment} && $change_set->{comment}->author->id == $treeherder_id) {
            $vars->{treeherder} = Bugzilla->treeherder_user;
            last;
        }
    }
}

sub bug_start_of_set_all {
    my ($self, $args) = @_;
    my $bug = $args->{bug};
    my $params = $args->{params};

    # reset to the component defaults if not supplied
    if (exists $params->{assigned_to} && (!defined $params->{assigned_to} || $params->{assigned_to} eq '')) {
        $params->{assigned_to} = $bug->component_obj->default_assignee->login;
    }
    if (exists $params->{qa_contact} && (!defined $params->{qa_contact} || $params->{qa_contact} eq '')
        && $bug->component_obj->default_qa_contact->id)
    {
        $params->{qa_contact} = $bug->component_obj->default_qa_contact->login;
    }
}

sub webservice {
    my ($self,  $args) = @_;
    my $dispatch = $args->{dispatch};
    $dispatch->{bug_modal} = 'Bugzilla::Extension::BugModal::WebService';
}

sub install_before_final_checks {
    my ($self, $args) = @_;
    add_setting({
        name     => 'ui_experiments',
        options  => ['on', 'off'],
        default  => 'off',
        category => 'User Interface'
    });
    add_setting({
        name     => 'ui_remember_collapsed',
        options  => ['on', 'off'],
        default  => 'off',
        category => 'User Interface'
    });
    add_setting({
        name     => 'ui_use_absolute_time',
        options  => ['on', 'off'],
        default  => 'off',
        category => 'User Interface',
    });
}

__PACKAGE__->NAME;
