# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BugModal;

use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Extension::BugModal::ActivityStream;
use Bugzilla::Extension::BugModal::MonkeyPatches;
use Bugzilla::Constants;
use Bugzilla::User::Setting;
use Bugzilla::Util qw(trick_taint datetime_from html_quote);
use List::MoreUtils qw(any);
use Template::Stash;
use Time::Duration;

our $VERSION = '1';

# force skin to mozilla
sub setting_set_value {
    my ($self, $args) = @_;
    return unless $args->{setting} eq 'ui_experiments' && $args->{value} ne 'on';
    my $settings = Bugzilla->user->settings;
    return if $settings->{skin}->{value} =~ /^Mozilla/;
    $settings->{skin}->set('Mozilla');
}

sub show_bug_format {
    my ($self, $args) = @_;
    $args->{format} = _alternative_show_bug_format();
}

sub edit_bug_format {
    my ($self, $args) = @_;
    $args->{format} = _alternative_show_bug_format();
}

sub _alternative_show_bug_format {
    my $user = Bugzilla->user;
    if (my $format = Bugzilla->cgi->param('format')) {
        return ($format eq '__default__' || $format eq 'default') ? undef : $format;
    }
    return $user->setting('ui_experiments') eq 'on' ? 'modal' : undef;
}

sub template_after_create {
    my ($self, $args) = @_;
    my $context = $args->{template}->context;

    # wrapper around Time::Duration::ago()
    $context->define_filter(
        time_duration => sub {
            my ($context) = @_;
            return sub {
                my ($timestamp) = @_;
                my $datetime = datetime_from($timestamp)
                    // return $timestamp;
                return ago(time() - $datetime->epoch);
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
        if (_alternative_show_bug_format()) {
            $vars->{alt_ui_header} = 'bug_modal/header.html.tmpl';
            $vars->{alt_ui_show}   = 'bug/show-modal.html.tmpl';
            $vars->{alt_ui_edit}   = 'bug_modal/edit.html.tmpl';
        }
        return;
    }

    return unless $file =~ m#^bug/show-([^\.]+)\.html\.tmpl$#;
    my $format = $1;
    my $alt = _alternative_show_bug_format() // return;
    return unless $alt eq $format;

    return unless
        $vars->{bugs}
        && ref($vars->{bugs}) eq 'ARRAY'
        && scalar(@{ $vars->{bugs} }) == 1;
    my $bug = $vars->{bugs}->[0];

    # trigger loading of tracking flags
    Bugzilla::Extension::TrackingFlags->template_before_process({
        file => 'bug/edit.html.tmpl',
        vars => $vars,
    });

    # bug->choices loads a lot of data that we want to lazy-load
    # just load the status and resolutions and perform extra checks here
    # upstream does these checks in the bug/fields template
    my $perms = $bug->user;
    my @resolutions;
    foreach my $r (@{ Bugzilla::Field->new({ name => 'resolution', cache => 1 })->legal_values }) {
        my $resolution = $r->name;
        next unless $resolution;
        next unless $r->is_active || $resolution eq $bug->resolution;

        if ($perms->{canconfirm}
            && !($perms->{canedit} || $perms->{isreporter}))
        {
            next if
                $resolution ne 'WORKSFORME'
                && $resolution ne 'INCOMPLETE'
                && $resolution ne 'DUPLICATE';
        }
        if ($perms->{isreporter}
            && !($perms->{canconfirm} || $perms->{canedit}))
        {
            next if $resolution eq 'INCOMPLETE';
        }
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
}

sub webservice {
    my ($self,  $args) = @_;
    my $dispatch = $args->{dispatch};
    $dispatch->{bug_modal} = 'Bugzilla::Extension::BugModal::WebService';
}

sub install_before_final_checks {
    my ($self, $args) = @_;
    add_setting('ui_experiments', ['on', 'off'], 'off');
}

__PACKAGE__->NAME;
