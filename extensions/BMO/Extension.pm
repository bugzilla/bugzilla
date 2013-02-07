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
# The Original Code is the BMO Bugzilla Extension.
#
# The Initial Developer of the Original Code is Gervase Markham.
# Portions created by the Initial Developer are Copyright (C) 2010 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Gervase Markham <gerv@gerv.net>
#   David Lawrence <dkl@mozilla.com>
#   Byron Jones <glob@mozilla.com>

package Bugzilla::Extension::BMO;
use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::Field;
use Bugzilla::Constants;
use Bugzilla::Status;
use Bugzilla::Product;
use Bugzilla::User;
use Bugzilla::User::Setting;
use Bugzilla::Util qw(html_quote trick_taint trim datetime_from detaint_natural);
use Bugzilla::Token;
use Bugzilla::Error;
use Bugzilla::Mailer;
use Bugzilla::Util;

use Scalar::Util qw(blessed);
use Date::Parse;
use DateTime;
use Encode qw(find_encoding decode_utf8);
use Sys::Syslog qw(:DEFAULT setlogsock);

use Bugzilla::Extension::BMO::Constants;
use Bugzilla::Extension::BMO::FakeBug;
use Bugzilla::Extension::BMO::Data qw($cf_visible_in_products
                                      $cf_flags
                                      $cf_project_flags
                                      $cf_disabled_flags
                                      %group_change_notification
                                      $blocking_trusted_setters
                                      $blocking_trusted_requesters
                                      $status_trusted_wanters
                                      $status_trusted_setters
                                      $other_setters
                                      %always_fileable_group
                                      %group_auto_cc
                                      %product_sec_groups);
use Bugzilla::Extension::BMO::Reports qw(user_activity_report
                                         triage_reports
                                         group_admins_report
                                         email_queue_report
                                         release_tracking_report
                                         group_membership_report
                                         group_members_report);

our $VERSION = '0.1';

#
# Monkey-patched methods
#

BEGIN {
    *Bugzilla::Bug::last_closed_date = \&_last_closed_date;
}

sub template_before_process {
    my ($self, $args) = @_;
    my $file = $args->{'file'};
    my $vars = $args->{'vars'};
    
    $vars->{'cf_hidden_in_product'} = \&cf_hidden_in_product;
    $vars->{'cf_is_project_flag'}   = \&cf_is_project_flag;
    $vars->{'cf_flag_disabled'}     = \&cf_flag_disabled;
    
    if ($file =~ /^list\/list/) {
        # Purpose: enable correct sorting of list table
        # Matched to changes in list/table.html.tmpl
        my %db_order_column_name_map = (
            'map_components.name' => 'component',
            'map_products.name' => 'product',
            'map_reporter.login_name' => 'reporter',
            'map_assigned_to.login_name' => 'assigned_to',
            'delta_ts' => 'opendate',
            'creation_ts' => 'changeddate',
        );

        my @orderstrings = split(/,\s*/, $vars->{'order'});
        
        # contains field names of the columns being used to sort the table.
        my @order_columns;
        foreach my $o (@orderstrings) {
            $o =~ s/bugs.//;
            $o = $db_order_column_name_map{$o} if 
                               grep($_ eq $o, keys(%db_order_column_name_map));
            next if (grep($_ eq $o, @order_columns));
            push(@order_columns, $o);
        }

        $vars->{'order_columns'} = \@order_columns;
        
        # fields that have a custom sortkey. (So they are correctly sorted 
        # when using js)
        my @sortkey_fields = qw(bug_status resolution bug_severity priority
                                rep_platform op_sys);

        my %columns_sortkey;
        foreach my $field (@sortkey_fields) {
            $columns_sortkey{$field} = _get_field_values_sort_key($field);
        }
        $columns_sortkey{'target_milestone'} = _get_field_values_sort_key('milestones');

        $vars->{'columns_sortkey'} = \%columns_sortkey;
    }
    elsif ($file =~ /^bug\/create\/create[\.-](.*)/) {
        my $format = $1;
        if (!$vars->{'cloned_bug_id'}) {
            # Allow status whiteboard values to be bookmarked
            $vars->{'status_whiteboard'} = 
                               Bugzilla->cgi->param('status_whiteboard') || "";
        }

        # Purpose: for pretty product chooser
        $vars->{'format'} = Bugzilla->cgi->param('format');

        # Data needed for "this is a security bug" checkbox
        $vars->{'sec_groups'} = \%product_sec_groups;

        if ($format eq 'doc.html.tmpl') {
            my $versions = Bugzilla::Product->new({ name => 'Core' })->versions;
            $vars->{'versions'} = [ reverse @$versions ];
        }
    }


    if ($file =~ /^list\/list/ || $file =~ /^bug\/create\/create[\.-]/) {
        # hack to allow the bug entry templates to use check_can_change_field 
        # to see if various field values should be available to the current user.
        $vars->{'default'} = Bugzilla::Extension::BMO::FakeBug->new($vars->{'default'} || {});
    }

    if ($file =~ /^attachment\/diff-header\./) {
        my $attachid = $vars->{attachid} ? $vars->{attachid} : $vars->{newid};
        $vars->{attachment} = Bugzilla::Attachment->new({ id => $attachid, cache => 1 })
            if $attachid;
    }
}

sub page_before_template {
    my ($self, $args) = @_;
    my $page = $args->{'page_id'};
    my $vars = $args->{'vars'};

    if ($page eq 'user_activity.html') {
        user_activity_report($vars);

    } elsif ($page eq 'triage_reports.html') {
        triage_reports($vars);

    } elsif ($page eq 'upgrade-3.6.html') {
        $vars->{'bzr_history'} = sub { 
            return `cd /data/www/bugzilla.mozilla.org; /usr/bin/bzr log -n0 -rlast:10..`;
        };
    }
    elsif ($page eq 'fields.html') {
        # Recently global/field-descs.none.tmpl and bug/field-help.none.tmpl 
        # were changed for better performance and are now only loaded once.
        # I have not found an easy way to allow our hook template to check if
        # it is called from pages/fields.html.tmpl. So we set a value in request_cache
        # that our hook template can see. 
        Bugzilla->request_cache->{'bmo_fields_page'} = 1;
    }
    elsif ($page eq 'group_admins.html') {
        group_admins_report($vars);
    }
    elsif ($page eq 'group_membership.html' or $page eq 'group_membership.txt') {
        group_membership_report($page, $vars);
    }
    elsif ($page eq 'group_members.html' or $page eq 'group_members.json') {
        group_members_report($vars);
    }
    elsif ($page eq 'email_queue.html') {
        email_queue_report($vars);
    }
    elsif ($page eq 'release_tracking_report.html') {
        release_tracking_report($vars);
    }
    elsif ($page eq 'query_database.html') {
        query_database($vars);
    }
}

sub _get_field_values_sort_key {
    my ($field) = @_;
    my $dbh = Bugzilla->dbh;
    my $fields = $dbh->selectall_arrayref(
         "SELECT value, sortkey FROM $field
        ORDER BY sortkey, value");

    my %field_values;
    foreach my $field (@$fields) {
        my ($value, $sortkey) = @$field;
        $field_values{$value} = $sortkey;
    }
    return \%field_values;
}

sub active_custom_fields {
    my ($self, $args) = @_;
    my $fields    = $args->{'fields'};
    my $params    = $args->{'params'};
    my $product   = $params->{'product'};
    my $component = $params->{'component'};

    return if !$product;

    my $product_name   = blessed $product ? $product->name : $product;
    my $component_name = blessed $component ? $component->name : $component;

    my @tmp_fields;
    foreach my $field (@$$fields) { 
        next if cf_hidden_in_product($field->name, $product_name, $component_name, $params->{'type'}); 
        push(@tmp_fields, $field);
    }
    $$fields = \@tmp_fields;
}

sub cf_is_project_flag {
    my ($field_name) = @_;
    foreach my $flag_re (@$cf_project_flags) {
        return 1 if $field_name =~ $flag_re;
    }
    return 0;
}

sub cf_hidden_in_product {
    my ($field_name, $product_name, $component_name, $custom_flag_mode) = @_;

    # If used in buglist.cgi, we pass in one_product which is a Bugzilla::Product
    # elsewhere, we just pass the name of the product.
    $product_name = blessed($product_name) ? $product_name->name
                                           : $product_name;
   
    # Also in buglist.cgi, we pass in a list of components instead 
    # of a single component name everywhere else.
    my $component_list = [];
    if ($component_name) {
        $component_list = ref $component_name ? $component_name 
                                              : [ $component_name ];
    }

    if ($custom_flag_mode) {
        if ($custom_flag_mode == 1) {
            # skip custom flags
            foreach my $flag_re (@$cf_flags) {
                return 1 if $field_name =~ $flag_re;
            }
        } elsif ($custom_flag_mode == 2) {
            # custom flags only
            my $found = 0;
            foreach my $flag_re (@$cf_flags) {
                if ($field_name =~ $flag_re) {
                    $found = 1;
                    last;
                }
            }
            return 1 unless $found;
        }
    }

    foreach my $field_re (keys %$cf_visible_in_products) {
        if ($field_name =~ $field_re) {
            # If no product given, for example more than one product
            # in buglist.cgi, then hide field by default
            return 1 if !$product_name;

            my $products = $cf_visible_in_products->{$field_re};
            foreach my $product (keys %$products) {
                my $components = $products->{$product};

                my $found_component = 0;
                if (@$components) {
                    foreach my $component (@$components) {
                        if (ref($component) eq 'Regexp') {
                            if (grep($_ =~ $component, @$component_list)) {
                                $found_component = 1;
                                last;
                            }
                        } else {
                            if (grep($_ eq $component, @$component_list)) {
                                $found_component = 1;
                                last;
                            }
                        }
                    }
                }
        
                # If product matches and at at least one component matches
                # from component_list (if a matching component was required), 
                # we allow the field to be seen
                if ($product eq $product_name && (!@$components || $found_component)) {
                    return 0;
                }
            }

            return 1;
        }
    }
    
    return 0;
}

sub cf_flag_disabled {
    my ($field_name, $bug) = @_;
    return 0 unless grep { $field_name eq $_ } @$cf_disabled_flags;
    my $value = $bug->{$field_name};
    return $value eq '---' || $value eq '';
}

# Purpose: CC certain email addresses on bugmail when a bug is added or 
# removed from a particular group.
sub bugmail_recipients {
    my ($self, $args) = @_;
    my $bug = $args->{'bug'};
    my $recipients = $args->{'recipients'};
    my $diffs = $args->{'diffs'};

    if (@$diffs) {
        # Changed bug
        foreach my $ref (@$diffs) {
            my $old = $ref->{old};
            my $new = $ref->{new};
            my $fieldname = $ref->{field_name};

            if ($fieldname eq "bug_group") {
                _cc_if_special_group($old, $recipients);
                _cc_if_special_group($new, $recipients);
            }
        }
    } else {
        # Determine if it's a new bug, or a comment without a field change
        my $comment_count = scalar @{$bug->comments};
        if ($comment_count == 1) {
            # New bug
            foreach my $group (@{ $bug->groups_in }) {
                _cc_if_special_group($group->{'name'}, $recipients);
            }
        }
    }
}

sub _cc_if_special_group {
    my ($group, $recipients) = @_;
    
    return if !$group;
    
    if (exists $group_change_notification{$group}) {
        foreach my $login (@{ $group_change_notification{$group} }) {
            my $id = login_to_id($login);
            $recipients->{$id}->{+REL_CC} = Bugzilla::BugMail::BIT_DIRECT();
        }
    }
}

sub _check_trusted {
    my ($field, $trusted, $priv_results) = @_;
    
    my $needed_group = $trusted->{'_default'} || "";
    foreach my $dfield (keys %$trusted) {
        if ($field =~ $dfield) {
            $needed_group = $trusted->{$dfield};
        }
    }
    if ($needed_group && !Bugzilla->user->in_group($needed_group)) {
        push (@$priv_results, PRIVILEGES_REQUIRED_EMPOWERED);
    }              
}

sub _is_field_set {
    my $value = shift;
    return $value ne '---' && $value !~ /\?$/;
}

sub bug_check_can_change_field {
    my ($self, $args) = @_;
    my $bug = $args->{'bug'};
    my $field = $args->{'field'};
    my $new_value = $args->{'new_value'};
    my $old_value = $args->{'old_value'};
    my $priv_results = $args->{'priv_results'};
    my $user = Bugzilla->user;

    # Only users in the appropriate drivers group can change the 
    # cf_blocking_* fields or cf_tracking_* fields

    if ($field =~ /^cf_(?:blocking|tracking)_/) {
        # 0 -> 1 is used by show_bug, always allow so we skip this whole part
        if (!($old_value eq '0' && $new_value eq '1')) {
            # require privileged access to set a flag
            if (_is_field_set($new_value)) {
                _check_trusted($field, $blocking_trusted_setters, $priv_results);
            }

            # require editbugs to clear or re-nominate a set flag
            elsif (_is_field_set($old_value) 
                && !$user->in_group('editbugs', $bug->{'product_id'}))
            {
                push (@$priv_results, PRIVILEGES_REQUIRED_EMPOWERED);
            }
        }

        if ($new_value =~ /\?$/) {
            _check_trusted($field, $blocking_trusted_requesters, $priv_results);
        }
        if ($user->id) {
            push (@$priv_results, PRIVILEGES_REQUIRED_NONE);
        }

    } elsif ($field =~ /^cf_status_/) {
        # Only drivers can set wanted.
        if ($new_value eq 'wanted') {
            _check_trusted($field, $status_trusted_wanters, $priv_results);
        } elsif (_is_field_set($new_value)) {
            _check_trusted($field, $status_trusted_setters, $priv_results);
        }
        if ($user->id) {
            push (@$priv_results, PRIVILEGES_REQUIRED_NONE);
        }

    } elsif ($field =~ /^cf/ && !@$priv_results && $new_value ne '---') {
        # "other" custom field setters restrictions
        if (exists $other_setters->{$field}) {
            my $in_group = 0;
            foreach my $group (@{$other_setters->{$field}}) {
                if ($user->in_group($group, $bug->product_id)) {
                    $in_group = 1;
                    last;
                }
            }
            if (!$in_group) {
                push (@$priv_results, PRIVILEGES_REQUIRED_EMPOWERED);
            }
        }

    } elsif ($field eq 'resolution' && $new_value eq 'EXPIRED') {
        # The EXPIRED resolution should only be settable by gerv.
        if ($user->login ne 'gerv@mozilla.org') {
            push (@$priv_results, PRIVILEGES_REQUIRED_EMPOWERED);
        }

    } elsif ($field eq 'resolution' && $new_value eq 'FIXED') {
        # You need at least canconfirm to mark a bug as FIXED
        if (!$user->in_group('canconfirm', $bug->{'product_id'})) {
            push (@$priv_results, PRIVILEGES_REQUIRED_EMPOWERED);
        }

    } elsif (
        ($field eq 'bug_status' && $old_value eq 'VERIFIED')
        || ($field eq 'dup_id' && $bug->status->name eq 'VERIFIED')
        || ($field eq 'resolution' && $bug->status->name eq 'VERIFIED')
    ) {
        # You need at least editbugs to reopen a resolved/verified bug
        if (!$user->in_group('editbugs', $bug->{'product_id'})) {
            push (@$priv_results, PRIVILEGES_REQUIRED_EMPOWERED);
        }

    } elsif ($user->in_group('canconfirm', $bug->{'product_id'})) {
        # Canconfirm is really "cantriage"; users with canconfirm can also mark 
        # bugs as DUPLICATE, WORKSFORME, and INCOMPLETE.
        if ($field eq 'bug_status'
            && is_open_state($old_value)
            && !is_open_state($new_value))
        {
            push (@$priv_results, PRIVILEGES_REQUIRED_NONE);
        }
        elsif ($field eq 'resolution' && 
               ($new_value eq 'DUPLICATE' ||
                $new_value eq 'WORKSFORME' ||
                $new_value eq 'INCOMPLETE'))
        {
            push (@$priv_results, PRIVILEGES_REQUIRED_NONE);
        }

    } elsif ($field eq 'bug_status') {
        # Disallow reopening of bugs which have been resolved for > 1 year
        if (is_open_state($new_value) 
            && !is_open_state($old_value)
            && $bug->resolution eq 'FIXED') 
        {
            my $days_ago = DateTime->now(time_zone => Bugzilla->local_timezone);
            $days_ago->subtract(days => 365);
            my $last_closed = datetime_from($bug->last_closed_date);
            if ($last_closed lt $days_ago) {
                push (@$priv_results, PRIVILEGES_REQUIRED_EMPOWERED);
            }
        }
    }
}

# link up various Mozilla-specific strings
sub bug_format_comment {
    my ($self, $args) = @_;
    my $regexes = $args->{'regexes'};

    # link UUIDs to crash-stats
    # Only match if not already in an URL using the negative lookbehind (?<!\/)
    push (@$regexes, {
        match => qr/(?<!\/)\b(?:UUID\s+|bp\-)([a-f0-9]{8}\-[a-f0-9]{4}\-[a-f0-9]{4}\-
                                       [a-f0-9]{4}\-[a-f0-9]{12})\b/x,
        replace => sub {
            my $args = shift;
            my $match = html_quote($args->{matches}->[0]);
            return qq{<a href="https://crash-stats.mozilla.com/report/index/$match">bp-$match</a>};
        }
    });

    # link to CVE/CAN security releases
    push (@$regexes, {
        match => qr/(?<!\/|=)\b((?:CVE|CAN)-\d{4}-\d{4})\b/,
        replace => sub {
            my $args = shift;
            my $match = html_quote($args->{matches}->[0]);
            return qq{<a href="http://cve.mitre.org/cgi-bin/cvename.cgi?name=$match">$match</a>};
        }
    });

    # link to svn.m.o
    push (@$regexes, {
        match => qr/\br(\d{4,})\b/,
        replace => sub {
            my $args = shift;
            my $match = html_quote($args->{matches}->[0]);
            return qq{<a href="http://viewvc.svn.mozilla.org/vc?view=rev&amp;revision=$match">r$match</a>};
        }
    });

    # link bzr commit messages
    push (@$regexes, {
        match => qr/\b(Committing\sto:\sbzr\+ssh:\/\/
                    (?:[^\@]+\@)?(bzr\.mozilla\.org[^\n]+)\n.*?\bCommitted\s)
                    (revision\s(\d+))/sx,
        replace => sub {
            my $args = shift;
            my $preamble = html_quote($args->{matches}->[0]);
            my $url = html_quote($args->{matches}->[1]);
            my $text = html_quote($args->{matches}->[2]);
            my $id = html_quote($args->{matches}->[3]);
            $url =~ s/\s+$//;
            $url =~ s/\/$//;
            return qq{$preamble<a href="http://$url/revision/$id">$text</a>};
        }
    });

    # link to hg.m.o
    # Note: for grouping in this regexp, always use non-capturing parentheses.
    my $hgrepos = join('|', qw!(?:releases/)?comm-[\w.]+ 
                               (?:releases/)?mozilla-[\w.]+
                               (?:releases/)?mobile-[\w.]+
                               tracemonkey
                               tamarin-[\w.]+
                               camino!);

    push (@$regexes, {
        match => qr/\b(($hgrepos)\s+changeset:?\s+(?:\d+:)?([0-9a-fA-F]{12}))\b/,
        replace => sub {
            my $args = shift;
            my $text = html_quote($args->{matches}->[0]);
            my $repo = html_quote($args->{matches}->[1]);
            my $id   = html_quote($args->{matches}->[2]);
            $repo = 'integration/mozilla-inbound' if $repo eq 'mozilla-inbound';
            return qq{<a href="https://hg.mozilla.org/$repo/rev/$id">$text</a>};
        }
    });
}

# Purpose: make it always possible to file bugs in certain groups.
sub bug_check_groups {
    my ($self, $args) = @_;
    my $group_names = $args->{'group_names'};
    my $add_groups = $args->{'add_groups'};

    return unless $group_names;
    $group_names = ref $group_names 
                   ? $group_names 
                   : [ map { trim($_) } split(',', $group_names) ];

    foreach my $name (@$group_names) {
        if (exists $always_fileable_group{$name}) {
            my $group = new Bugzilla::Group({ name => $name }) or next;
            $add_groups->{$group->id} = $group;
        }
    }
}

# Purpose: generically handle generating pretty blocking/status "flags" from
# custom field names.
sub quicksearch_map {
    my ($self, $args) = @_;
    my $map = $args->{'map'};
    
    foreach my $name (keys %$map) {
        if ($name =~ /^cf_(blocking|tracking|status)_([a-z]+)?(\d+)?$/) {
            my $type = $1;
            my $product = $2;
            my $version = $3;

            if ($version) {
                $version = join('.', split(//, $version));
            }

            my $pretty_name = $type;
            if ($product) {              
                $pretty_name .= "-" . $product;
            }
            if ($version) {
                $pretty_name .= $version;
            }

            $map->{$pretty_name} = $name;
        }
        elsif ($name =~ /cf_crash_signature$/) {
            $map->{'sig'} = $name;
        }
    }
}

# Restrict content types attachable by non-privileged people
my @mimetype_whitelist = ('^image\/', 'application\/pdf');

sub object_end_of_create_validators {
    my ($self, $args) = @_;
    my $class = $args->{'class'};
    
    if ($class->isa('Bugzilla::Attachment')) {
        my $params = $args->{'params'};
        my $bug = $params->{'bug'};
        if (!Bugzilla->user->in_group('editbugs', $bug->product_id)) {
            my $mimetype = $params->{'mimetype'};
            if (!grep { $mimetype =~ /$_/ } @mimetype_whitelist ) {
                # Need to neuter MIME type to something non-executable
                if ($mimetype =~ /^text\//) {
                    $params->{'mimetype'} = "text/plain";
                }
                else {
                    $params->{'mimetype'} = "application/octet-stream";
                }
            }
        }
    }
}

# Automatically CC users to bugs based on group & product
sub bug_end_of_create {
    my ($self, $args) = @_;
    my $bug = $args->{'bug'};

    foreach my $group_name (keys %group_auto_cc) {
        my $group_obj = Bugzilla::Group->new({ name => $group_name });
        if ($group_obj && $bug->in_group($group_obj)) {
            my $ra_logins = exists $group_auto_cc{$group_name}->{$bug->product}
                            ? $group_auto_cc{$group_name}->{$bug->product}
                            : $group_auto_cc{$group_name}->{'_default'};
            foreach my $login (@$ra_logins) {
                $bug->add_cc($login);
            }
        }
    }
}

sub install_before_final_checks {
    my ($self, $args) = @_;
    
    # Add product chooser setting (although it was added long ago, so add_setting
    # will just return every time).
    add_setting('product_chooser', 
                ['pretty_product_chooser', 'full_product_chooser'],
                'pretty_product_chooser');

    # Migrate from 'gmail_threading' setting to 'bugmail_new_prefix'
    my $dbh = Bugzilla->dbh;
    if ($dbh->selectrow_array("SELECT 1 FROM setting WHERE name='gmail_threading'")) {
        $dbh->bz_start_transaction();
        $dbh->do("UPDATE profile_setting
                     SET setting_value='on-temp'
                   WHERE setting_name='gmail_threading' AND setting_value='Off'");
        $dbh->do("UPDATE profile_setting
                     SET setting_value='off'
                   WHERE setting_name='gmail_threading' AND setting_value='On'");
        $dbh->do("UPDATE profile_setting
                     SET setting_value='on'
                   WHERE setting_name='gmail_threading' AND setting_value='on-temp'");
        $dbh->do("UPDATE profile_setting
                     SET setting_name='bugmail_new_prefix'
                   WHERE setting_name='gmail_threading'");
        $dbh->do("DELETE FROM setting WHERE name='gmail_threading'");
        $dbh->bz_commit_transaction();
    }
}

# Migrate old is_active stuff to new patch (is in core in 4.2), The old column
# name was 'is_active', the new one is 'isactive' (no underscore).
sub install_update_db {
    my $dbh = Bugzilla->dbh;
    
    if ($dbh->bz_column_info('milestones', 'is_active')) {
        $dbh->do("UPDATE milestones SET isactive = 0 WHERE is_active = 0;");
        $dbh->bz_drop_column('milestones', 'is_active');
        $dbh->bz_drop_column('milestones', 'is_searchable');
    }
}

sub _last_closed_date {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;

    return $self->{'last_closed_date'} if defined $self->{'last_closed_date'};

    my $closed_statuses = "'" . join("','", map { $_->name } closed_bug_statuses()) . "'";
    my $status_field_id = get_field_id('bug_status');

    $self->{'last_closed_date'} = $dbh->selectrow_array("
        SELECT bugs_activity.bug_when
          FROM bugs_activity
         WHERE bugs_activity.fieldid = ?
               AND bugs_activity.added IN ($closed_statuses)
               AND bugs_activity.bug_id = ?
      ORDER BY bugs_activity.bug_when DESC " . $dbh->sql_limit(1),
        undef, $status_field_id, $self->id
    );

    return $self->{'last_closed_date'};
}

sub field_end_of_create {
    my ($self, $args) = @_;
    my $field = $args->{'field'};

    # email mozilla's DBAs so they can update the grants for metrics
    # this really should create a bug in mozilla.org/Server Operations: Database

    if (Bugzilla->params->{'urlbase'} ne 'https://bugzilla.mozilla.org/') {
        return;
    }

    if (Bugzilla->usage_mode == USAGE_MODE_CMDLINE) {
        print "Emailing notification to infra-dbnotices\@mozilla.com\n";
    }

    my $name = $field->name;
    my @message;
    push @message, 'To: infra-dbnotices@mozilla.com';
    push @message, "Subject: custom field '$name' added to bugzilla.mozilla.org";
    push @message, 'From: ' . Bugzilla->params->{mailfrom};
    push @message, '';
    push @message, "The custom field '$name' has been added to the BMO database.";
    push @message, '';
    push @message, 'Please run the following on tp-bugs01-master01:';
    push @message, "  GRANT SELECT ON `bugs`.`$name` TO 'metrics'\@'10.8.70.20_';";
    push @message, "  GRANT SELECT ($name) ON `bugs`.`bugs` TO 'metrics'\@'10.8.70.20_';";
    push @message, "  GRANT SELECT ON `bugs`.`$name` TO 'metrics'\@'10.8.70.21_';";
    push @message, "  GRANT SELECT ($name) ON `bugs`.`bugs` TO 'metrics'\@'10.8.70.21_';";
    push @message, '';
    MessageToMTA(join("\n", @message));
}

sub webservice {
    my ($self,  $args) = @_;

    my $dispatch = $args->{dispatch};
    $dispatch->{BMO} = "Bugzilla::Extension::BMO::WebService";
}

our $search_content_matches;
BEGIN {
    $search_content_matches = \&Bugzilla::Search::_content_matches;
}

sub search_operator_field_override {
    my ($self, $args) = @_;
    my $search = $args->{'search'};
    my $operators = $args->{'operators'};

    my $cgi = Bugzilla->cgi;
    my @comments = $cgi->param('comments');
    my $exclude_comments = scalar(@comments) && !grep { $_ eq '1' } @comments;

    if ($cgi->param('query_format')
        && $cgi->param('query_format') eq 'specific'
        && $exclude_comments
    ) {
        # use the non-comment operator
        $operators->{'content'}->{matches} = \&_short_desc_matches;
        $operators->{'content'}->{notmatches} = \&_short_desc_matches;

    } else {
        # restore default content operator
        $operators->{'content'}->{matches} = $search_content_matches;
        $operators->{'content'}->{notmatches} = $search_content_matches;
    }
}

sub _short_desc_matches {
    # copy of Bugzilla::Search::_content_matches with comment searching removed

    my ($self, $args) = @_;
    my ($chart_id, $joins, $fields, $operator, $value) =
        @$args{qw(chart_id joins fields operator value)};
    my $dbh = Bugzilla->dbh;

    # Add the fulltext table to the query so we can search on it.
    my $table = "bugs_fulltext_$chart_id";
    push(@$joins, { table => 'bugs_fulltext', as => $table });

    # Create search terms to add to the SELECT and WHERE clauses.
    my ($term, $rterm) =
        $dbh->sql_fulltext_search("$table.short_desc", $value, 2);
    $rterm = $term if !$rterm;

    # The term to use in the WHERE clause.
    if ($operator =~ /not/i) {
        $term = "NOT($term)";
    }
    $args->{term} = $term;

    my $current = $self->COLUMNS->{'relevance'}->{name};
    $current = $current ? "$current + " : '';
    # For NOT searches, we just add 0 to the relevance.
    my $select_term = $operator =~ /not/ ? 0 : "($current$rterm)";
    $self->COLUMNS->{'relevance'}->{name} = $select_term;
}

sub mailer_before_send {
    my ($self, $args) = @_;
    my $email = $args->{email};

    _log_sent_email($email);

    # Add X-Bugzilla-Tracking header
    if ($email->header('X-Bugzilla-ID')) {
        my $bug_id = $email->header('X-Bugzilla-ID');

        # return if we cannot successfully load the bug object
        my $bug = new Bugzilla::Bug($bug_id);
        return if !$bug;

        # The BMO hook in active_custom_fields will filter 
        # the fields for us based on product and component
        my @fields = Bugzilla->active_custom_fields({
            product   => $bug->product_obj, 
            component => $bug->component_obj,
            type      => 2,  
        });

        my @set_values = ();
        foreach my $field (@fields) {
            my $field_name = $field->name;
            next if cf_flag_disabled($field_name, $bug);
            next if !$bug->$field_name || $bug->$field_name eq '---';
            push(@set_values, $field->description . ":" . $bug->$field_name);
        }

        if (@set_values) {
            $email->header_set('X-Bugzilla-Tracking' => join(' ', @set_values));
        } 
    }

    # attachments disabled, see bug 714488
    return;

    # If email is a request for a review, add the attachment itself
    # to the email as an attachment. Attachment must be content type
    # text/plain and below a certain size. Otherwise the email already 
    # contain a link to the attachment. 
    if ($email
        && $email->header('X-Bugzilla-Type') eq 'request'
        && ($email->header('X-Bugzilla-Flag-Requestee') 
            && $email->header('X-Bugzilla-Flag-Requestee') eq $email->header('to'))) 
    {
        my $body = $email->body;

        if (my ($attach_id) = $body =~ /Attachment\s+(\d+)\s*:/) {
            my $attachment = Bugzilla::Attachment->new($attach_id);
            if ($attachment 
                && $attachment->ispatch 
                && $attachment->contenttype eq 'text/plain'
                && $attachment->linecount 
                && $attachment->linecount < REQUEST_MAX_ATTACH_LINES) 
            {
                # Don't send a charset header with attachments, as they might 
                # not be UTF-8, unless we can properly detect it.
                my $charset;
                if (Bugzilla->feature('detect_charset')) {
                    my $encoding = detect_encoding($attachment->data);
                    if ($encoding) {
                        $charset = find_encoding($encoding)->mime_name;
                    }
                }

                my $attachment_part = Email::MIME->create(
                    attributes => {
                        content_type => $attachment->contenttype,
                        filename     => $attachment->filename,
                        disposition  => "attachment",
                    },
                    body => $attachment->data,
                );
                $attachment_part->charset_set($charset) if $charset;

                $email->parts_add([ $attachment_part ]);
            }
        }       
    }
}

# Log a summary of bugmail sent to the syslog, for auditing and monitoring
sub _log_sent_email {
    my $email = shift;

    my $recipient = $email->header('to');
    return unless $recipient;

    my $subject = $email->header('Subject');

    my $bug_id = $email->header('X-Bugzilla-ID');
    if (!$bug_id && $subject =~ /[\[\(]Bug (\d+)/i) {
        $bug_id = $1;
    }
    $bug_id = $bug_id ? "bug-$bug_id" : '-';

    my $message_type;
    my $type = $email->header('X-Bugzilla-Type');
    my $reason = $email->header('X-Bugzilla-Reason');
    if ($type eq 'whine' || $type eq 'request' || $type eq 'admin') {
        $message_type = $type;
    } elsif ($reason && $reason ne 'None') {
        $message_type = $reason;
    } else {
        $message_type = $email->header('X-Bugzilla-Watch-Reason');
    }
    $message_type ||= '?';

    $subject =~ s/[\[\(]Bug \d+[\]\)]\s*//;

    openlog('apache', 'cons,pid', 'local4');
    syslog('notice', decode_utf8("[bugmail] $recipient ($message_type) $bug_id $subject"));
    closelog();
}

sub post_bug_after_creation {
    my ($self, $args) = @_;
    my $vars = $args->{vars};
    my $bug = $vars->{bug};

    if (Bugzilla->input_params->{format}
        && Bugzilla->input_params->{format} eq 'employee-incident'
        && $bug->component eq 'Server Operations: Desktop Issues')
    {
        my $error_mode_cache = Bugzilla->error_mode;
        Bugzilla->error_mode(ERROR_MODE_DIE);

        my $template = Bugzilla->template;
        my $cgi = Bugzilla->cgi;

        my ($investigate_bug, $ssh_key_bug);
        my $old_user = Bugzilla->user;
        eval {
            Bugzilla->set_user(Bugzilla::User->new({ name => 'nobody@mozilla.org' }));
            my $new_user = Bugzilla->user;

            # HACK: User needs to be in the editbugs and primary bug's group to allow
            # setting of dependencies.
            $new_user->{'groups'} = [ Bugzilla::Group->new({ name => 'editbugs' }), 
                                      Bugzilla::Group->new({ name => 'infra' }), 
                                      Bugzilla::Group->new({ name => 'infrasec' }) ];

            my $recipients = { changer => $new_user };
            $vars->{original_reporter} = $old_user;

            my $comment;
            $cgi->param('display_action', '');
            $template->process('bug/create/comment-employee-incident.txt.tmpl', $vars, \$comment)
                || ThrowTemplateError($template->error());

            $investigate_bug = Bugzilla::Bug->create({ 
                short_desc        => 'Investigate Lost Device',
                product           => 'mozilla.org',
                component         => 'Security Assurance: Incident',
                status_whiteboard => '[infrasec:incident]',
                bug_severity      => 'critical',
                cc                => [ 'mcoates@mozilla.com', 'jstevensen@mozilla.com' ],
                groups            => [ 'infrasec' ], 
                comment           => $comment,
                op_sys            => 'All', 
                rep_platform      => 'All',
                version           => 'other',
                dependson         => $bug->bug_id, 
            });
            $bug->set_all({ blocked => { add => [ $investigate_bug->bug_id ] }});
            Bugzilla::BugMail::Send($investigate_bug->id, $recipients);

            Bugzilla->set_user($old_user);
            $vars->{original_reporter} = '';
            $comment = '';
            $cgi->param('display_action', 'ssh');
            $template->process('bug/create/comment-employee-incident.txt.tmpl', $vars, \$comment)
                || ThrowTemplateError($template->error());

            $ssh_key_bug = Bugzilla::Bug->create({ 
                short_desc        => 'Disable/Regenerate SSH Key',
                product           => $bug->product,
                component         => $bug->component,
                bug_severity      => 'critical',
                cc                => $bug->cc,
                groups            => [ map { $_->{name} } @{ $bug->groups } ],
                comment           => $comment,
                op_sys            => 'All', 
                rep_platform      => 'All',
                version           => 'other',
                dependson         => $bug->bug_id, 
            });
            $bug->set_all({ blocked => { add => [ $ssh_key_bug->bug_id ] }});
            Bugzilla::BugMail::Send($ssh_key_bug->id, $recipients);
        };
        my $error = $@;

        Bugzilla->set_user($old_user);
        Bugzilla->error_mode($error_mode_cache);

        if ($error || !$investigate_bug || !$ssh_key_bug) {
            warn "Failed to create additional employee-incident bug: $error" if $error;
            $vars->{'message'} = 'employee_incident_creation_failed';
        }
    }
}

sub buglist_columns {
    my ($self, $args) = @_;
    my $columns = $args->{columns};
    $columns->{'cc_count'} = {
        name => '(SELECT COUNT(*) FROM cc WHERE cc.bug_id = bugs.bug_id)',
        title => 'CC Count',
    };
    $columns->{'dupe_count'} = {
        name => '(SELECT COUNT(*) FROM duplicates WHERE duplicates.dupe_of = bugs.bug_id)',
        title => 'Duplicate Count',
    };
}

sub query_database {
    my ($vars) = @_;

    # validate group membership
    my $user = Bugzilla->user;
    $user->in_group('query_database')
        || ThrowUserError('auth_failure', { group  => 'query_database',
                                            action => 'access',
                                            object => 'query_database' });

    # read query
    my $input = Bugzilla->input_params;
    my $query = $input->{query};
    $vars->{query} = $query;

    if ($query) {
        trick_taint($query);
        $vars->{executed} = 1;

        # add limit if missing
        if ($query !~ /\sLIMIT\s+\d+\s*$/si) {
            $query .= ' LIMIT 1000';
            $vars->{query} = $query;
        }

        # log query
        setlogsock('unix');
        openlog('apache', 'cons', 'pid', 'local4');
        syslog('notice', sprintf("[db_query] %s %s", $user->login, $query));
        closelog();

        # connect to database and execute
        # switching to the shadow db gives us a read-only connection
        my $dbh = Bugzilla->switch_to_shadow_db();
        my $sth;
        eval {
            $sth = $dbh->prepare($query);
            $sth->execute();
        };
        if ($@) {
            $vars->{sql_error} = $@;
            return;
        }

        # build result
        my $columns = $sth->{NAME};
        my $rows;
        while (my @row = $sth->fetchrow_array) {
            push @$rows, \@row;
        }

        # return results
        $vars->{columns} = $columns;
        $vars->{rows} = $rows;
    }
}

__PACKAGE__->NAME;
