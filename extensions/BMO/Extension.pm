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

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Field;
use Bugzilla::Group;
use Bugzilla::Mailer;
use Bugzilla::Product;
use Bugzilla::Status;
use Bugzilla::Token;
use Bugzilla::Install::Filesystem;
use Bugzilla::User;
use Bugzilla::User::Setting;
use Bugzilla::Util;

use Date::Parse;
use DateTime;
use Encode qw(find_encoding encode_utf8);
use File::MimeInfo::Magic;
use List::MoreUtils qw(natatime);
use Scalar::Util qw(blessed);
use Sys::Syslog qw(:DEFAULT setlogsock);

use Bugzilla::Extension::BMO::Constants;
use Bugzilla::Extension::BMO::FakeBug;
use Bugzilla::Extension::BMO::Data;

our $VERSION = '0.1';

#
# Monkey-patched methods
#

BEGIN {
    *Bugzilla::Bug::last_closed_date = \&_last_closed_date;
    *Bugzilla::Product::default_security_group = \&_default_security_group;
    *Bugzilla::Product::default_security_group_obj = \&_default_security_group_obj;
    *Bugzilla::Product::group_always_settable = \&_group_always_settable;
    *Bugzilla::check_default_product_security_group = \&_check_default_product_security_group;
}

sub template_before_process {
    my ($self, $args) = @_;
    my $file = $args->{'file'};
    my $vars = $args->{'vars'};

    $vars->{'cf_hidden_in_product'} = \&cf_hidden_in_product;

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
        require Bugzilla::Extension::BMO::Reports::UserActivity;
        Bugzilla::Extension::BMO::Reports::UserActivity::report($vars);

    } elsif ($page eq 'triage_reports.html') {
        require Bugzilla::Extension::BMO::Reports::Triage;
        Bugzilla::Extension::BMO::Reports::Triage::report($vars);
    }
    elsif ($page eq 'group_admins.html') {
        require Bugzilla::Extension::BMO::Reports::Groups;
        Bugzilla::Extension::BMO::Reports::Groups::admins_report($vars);
    }
    elsif ($page eq 'group_membership.html' or $page eq 'group_membership.txt') {
        require Bugzilla::Extension::BMO::Reports::Groups;
        Bugzilla::Extension::BMO::Reports::Groups::membership_report($page, $vars);
    }
    elsif ($page eq 'group_members.html' or $page eq 'group_members.json') {
        require Bugzilla::Extension::BMO::Reports::Groups;
        Bugzilla::Extension::BMO::Reports::Groups::members_report($vars);
    }
    elsif ($page eq 'email_queue.html') {
        require Bugzilla::Extension::BMO::Reports::EmailQueue;
        Bugzilla::Extension::BMO::Reports::EmailQueue::report($vars);
    }
    elsif ($page eq 'release_tracking_report.html') {
        require Bugzilla::Extension::BMO::Reports::ReleaseTracking;
        Bugzilla::Extension::BMO::Reports::ReleaseTracking::report($vars);
    }
    elsif ($page eq 'product_security_report.html') {
        require Bugzilla::Extension::BMO::Reports::ProductSecurity;
        Bugzilla::Extension::BMO::Reports::ProductSecurity::report($vars);
    }
    elsif ($page eq 'fields.html') {
        # Recently global/field-descs.none.tmpl and bug/field-help.none.tmpl
        # were changed for better performance and are now only loaded once.
        # I have not found an easy way to allow our hook template to check if
        # it is called from pages/fields.html.tmpl. So we set a value in request_cache
        # that our hook template can see. 
        Bugzilla->request_cache->{'bmo_fields_page'} = 1;
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
        next if cf_hidden_in_product($field->name, $product_name, $component_name);
        push(@tmp_fields, $field);
    }
    $$fields = \@tmp_fields;
}

sub cf_hidden_in_product {
    my ($field_name, $product_name, $component_name) = @_;

    # If used in buglist.cgi, we pass in one_product which is a Bugzilla::Product
    # elsewhere, we just pass the name of the product.
    $product_name = blessed($product_name)
                    ? $product_name->name
                    : $product_name;

    # Also in buglist.cgi, we pass in a list of components instead 
    # of a single component name everywhere else.
    my $component_list = [];
    if ($component_name) {
        $component_list = ref $component_name
                          ? $component_name
                          : [ $component_name ];
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

    if ($field =~ /^cf/ && !@$priv_results && $new_value ne '---') {
        # "other" custom field setters restrictions
        if (exists $cf_setters->{$field}) {
            my $in_group = 0;
            foreach my $group (@{$cf_setters->{$field}}) {
                if ($user->in_group($group, $bug->product_id)) {
                    $in_group = 1;
                    last;
                }
            }
            if (!$in_group) {
                push (@$priv_results, PRIVILEGES_REQUIRED_EMPOWERED);
            }
        }
    }
    elsif ($field eq 'resolution' && $new_value eq 'EXPIRED') {
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

    # link to crash-stats
    # Only match if not already in an URL using the negative lookbehind (?<!\/)
    push (@$regexes, {
        match => qr/(?<!\/)\bbp-([a-f0-9]{8}\-[a-f0-9]{4}\-[a-f0-9]{4}\-
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
        match => qr/\b(Committing\s+to:\sbzr\+ssh:\/\/
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

    # link git.mozilla.org commit messages
    push (@$regexes, {
        match => qr#^(To\s(?:ssh://)?(?:[^\@]+\@)?git\.mozilla\.org[:/](.+?\.git)\n
                    \s+)([0-9a-z]+\.\.([0-9a-z]+)\s+\S+\s->\s\S+)#mx,
        replace => sub {
            my $args = shift;
            my $preamble = html_quote($args->{matches}->[0]);
            my $repo = html_quote($args->{matches}->[1]);
            my $text = $args->{matches}->[2];
            my $revision = $args->{matches}->[3];
            return qq#$preamble<a href="http://git.mozilla.org/?p=$repo;a=commitdiff;h=$revision">$text</a>#;
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

sub quicksearch_map {
    my ($self, $args) = @_;
    my $map = $args->{'map'};

    foreach my $name (keys %$map) {
        if ($name =~ /cf_crash_signature$/) {
            $map->{'sig'} = $name;
        }
    }
}

sub object_end_of_create {
    my ($self, $args) = @_;
    my $class = $args->{class};

    if ($class eq 'Bugzilla::User') {
        my $user = $args->{object};

        # Log real IP addresses for auditing
        _syslog(sprintf('[audit] <%s> created user %s', remote_ip(), $user->login));

        # Add default searches to new user's footer
        my $dbh = Bugzilla->dbh;

        my $sharer = Bugzilla::User->new({ name => 'nobody@mozilla.org' })
            or return;
        my $group = Bugzilla::Group->new({ name => 'everyone' })
            or return;

        foreach my $definition (@default_named_queries) {
            my ($namedquery_id) = _get_named_query($sharer->id, $group->id, $definition);
            $dbh->do(
                "INSERT INTO namedqueries_link_in_footer(namedquery_id,user_id) VALUES (?,?)",
                undef,
                $namedquery_id, $user->id
            );
        }

    } elsif ($class eq 'Bugzilla::Bug') {
        # Log real IP addresses for auditing
        _syslog(sprintf('[audit] %s <%s> created bug %s',
            Bugzilla->user->login, remote_ip(), $args->{object}->id));
    }
}

sub _get_named_query {
    my ($sharer_id, $group_id, $definition) = @_;
    my $dbh = Bugzilla->dbh;
    # find existing namedquery
    my ($namedquery_id) = $dbh->selectrow_array(
        "SELECT id FROM namedqueries WHERE userid=? AND name=?",
        undef,
        $sharer_id, $definition->{name}
    );
    return $namedquery_id if $namedquery_id;
    # create namedquery
    $dbh->do(
        "INSERT INTO namedqueries(userid,name,query) VALUES (?,?,?)",
        undef,
        $sharer_id, $definition->{name}, $definition->{query}
    );
    $namedquery_id = $dbh->bz_last_key();
    # and share it
    $dbh->do(
        "INSERT INTO namedquery_group_map(namedquery_id,group_id) VALUES (?,?)",
        undef,
        $namedquery_id, $group_id,
    );
    return $namedquery_id;
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

# detect github pull requests and reviewboard reviews, set the content-type
sub attachment_process_data {
    my ($self, $args) = @_;
    my $attributes = $args->{attributes};

    # must be a text attachment
    return unless $attributes->{mimetype} eq 'text/plain';

    # check the attachment size, and get attachment content if it isn't too large
    my $data = $attributes->{data};
    my $url;
    if (blessed($data) && blessed($data) eq 'Fh') {
        # filehandle
        my $size = -s $data;
        return if $size > 256;
        sysread($data, $url, $size);
        seek($data, 0, 0);
    } else {
        # string
        $url = $data;
    }

    if (my $content_type = _get_review_content_type($url)) {
        $attributes->{mimetype} = $content_type;
        $attributes->{ispatch}  = 0;
    }
}

sub _get_review_content_type {
    my ($url) = @_;

    # trim and check for the pull request url
    return unless defined $url;
    return if length($url) > 256;
    $url = trim($url);
    return if $url =~ /\s/;

    if ($url =~ m#^https://github\.com/[^/]+/[^/]+/pull/\d+/?$#i) {
        return GITHUB_PR_CONTENT_TYPE;
    }
    if ($url =~ m#^https?://reviewboard(?:-dev)?\.(?:allizom|mozilla)\.org/r/\d+/?#i) {
        return RB_REQUEST_CONTENT_TYPE;
    }
    return;
}

# redirect automatically to github urls
sub attachment_view {
    my ($self, $args) = @_;
    my $attachment = $args->{attachment};
    my $cgi = Bugzilla->cgi;

    # don't redirect if the content-type is specified explicitly
    return if defined $cgi->param('content_type');

    # must be our github/reviewboard content-type
    return unless
        $attachment->contenttype eq GITHUB_PR_CONTENT_TYPE
        or $attachment->contenttype eq RB_REQUEST_CONTENT_TYPE;

    # must still be a valid url
    return unless _get_review_content_type($attachment->data);

    # redirect
    print $cgi->redirect(trim($attachment->data));
    exit;
}

sub install_before_final_checks {
    my ($self, $args) = @_;

    # Add product chooser setting
    add_setting('product_chooser',
                ['pretty_product_chooser', 'full_product_chooser'],
                'pretty_product_chooser');

    # Add option to inject x-bugzilla headers into the message body to work
    # around gmail filtering limitations
    add_setting('headers_in_body', ['on', 'off'], 'off');

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

    # Create an IT bug so Mozilla's DBAs so they can update the grants for metrics

    if (Bugzilla->params->{'urlbase'} ne 'https://bugzilla.mozilla.org/'
        && Bugzilla->params->{'urlbase'} ne 'https://bugzilla.allizom.org/')
    {
        return;
    }

    my $name = $field->name;

    if (Bugzilla->usage_mode == USAGE_MODE_CMDLINE) {
        Bugzilla->set_user(Bugzilla::User->check({ name => 'nobody@mozilla.org' }));
        print "Creating IT permission grant bug for new field '$name'...";
    }

    my $bug_data = {
        short_desc   => "Custom field '$name' added to bugzilla.mozilla.org",
        product      => 'mozilla.org',
        component    => 'Server Operations: Database',
        bug_severity => 'normal',
        op_sys       => 'All',
        rep_platform => 'All',
        version      => 'other',
    };

    my $comment = <<COMMENT;
The custom field '$name' has been added to the BMO database.
Please run the following on bugzilla1.db.scl3.mozilla.com:
COMMENT

    if ($field->type == FIELD_TYPE_SINGLE_SELECT
        || $field->type == FIELD_TYPE_MULTI_SELECT) {
        $comment .= <<COMMENT;
  GRANT SELECT ON `bugs`.`$name` TO 'metrics'\@'10.22.70.20_';
  GRANT SELECT ON `bugs`.`$name` TO 'metrics'\@'10.22.70.21_';
COMMENT
    }
    if ($field->type == FIELD_TYPE_MULTI_SELECT) {
        $comment .= <<COMMENT;
  GRANT SELECT ON `bugs`.`bug_$name` TO 'metrics'\@'10.22.70.20_';
  GRANT SELECT ON `bugs`.`bug_$name` TO 'metrics'\@'10.22.70.21_';
COMMENT
    }
    if ($field->type != FIELD_TYPE_MULTI_SELECT) {
        $comment .= <<COMMENT;
  GRANT SELECT ($name) ON `bugs`.`bugs` TO 'metrics'\@'10.22.70.20_';
  GRANT SELECT ($name) ON `bugs`.`bugs` TO 'metrics'\@'10.22.70.21_';
COMMENT
    }

    $bug_data->{'comment'} = $comment;

    my $old_error_mode = Bugzilla->error_mode;
    Bugzilla->error_mode(ERROR_MODE_DIE);

    my $new_bug = eval { Bugzilla::Bug->create($bug_data) };

    my $error = $@;
    undef $@;
    Bugzilla->error_mode($old_error_mode);

    if ($error || !($new_bug && $new_bug->{'bug_id'})) {
        warn "Error creating IT bug for new field $name: $error";
        if (Bugzilla->usage_mode == USAGE_MODE_CMDLINE) {
            print "\nError: $error\n";
        }
    }
    else {
        Bugzilla::BugMail::Send($new_bug->id, { changer => Bugzilla->user });
        if (Bugzilla->usage_mode == USAGE_MODE_CMDLINE) {
            print "bug " . $new_bug->id . " created.\n";
        }
    }
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

    # $bug->mentors is added by the Review extension
    if (Bugzilla::Bug->can('mentors')) {
        _add_mentors_header($email);
    }

    # insert x-bugzilla headers into the body
    _inject_headers_into_body($email);
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
    $message_type ||= $type || '?';

    $subject =~ s/[\[\(]Bug \d+[\]\)]\s*//;

    _syslog("[bugmail] $recipient ($message_type) $bug_id $subject");
}

# Add X-Bugzilla-Mentors field to bugmail
sub _add_mentors_header {
    my $email = shift;
    return unless my $bug_id = $email->header('X-Bugzilla-ID');
    return unless my $bug = Bugzilla::Bug->new({ id => $bug_id, cache => 1 });
    return unless my $mentors = $bug->mentors;
    return unless @$mentors;
    $email->header_set('X-Bugzilla-Mentors', join(', ', map { $_->login } @$mentors));
}

sub _inject_headers_into_body {
    my $email = shift;
    my $replacement = '';

    my $recipient = Bugzilla::User->new({ name => $email->header('To'), cache => 1 });
    if ($recipient
        && $recipient->settings->{headers_in_body}->{value} eq 'on')
    {
        my @headers;
        my $it = natatime(2, $email->header_pairs);
        while (my ($name, $value) = $it->()) {
            next unless $name =~ /^X-Bugzilla-(.+)/;
            if ($name eq 'X-Bugzilla-Flags' || $name eq 'X-Bugzilla-Changed-Field-Names') {
                # these are multi-value fields, split on space
                foreach my $v (split(/\s+/, $value)) {
                    push @headers, "$name: $v";
                }
            }
            elsif ($name eq 'X-Bugzilla-Changed-Fields') {
                # cannot split on space for this field, because field names contain
                # spaces.  instead work from a list of field names.
                my @fields =
                    map { $_->description }
                    @{ Bugzilla->fields };
                # these aren't real fields, but exist in the headers
                push @fields, ('Comment Created', 'Attachment Created');
                @fields =
                    sort { length($b) <=> length($a) }
                    @fields;
                while ($value ne '') {
                    foreach my $field (@fields) {
                        if ($value eq $field) {
                            push @headers, "$name: $field";
                            $value = '';
                            last;
                        }
                        if (substr($value, 0, length($field) + 1) eq $field . ' ') {
                            push @headers, "$name: $field";
                            $value = substr($value, length($field) + 1);
                            last;
                        }
                    }
                }
            }
            else {
                push @headers, "$name: $value";
            }
        }
        $replacement = join("\n", @headers);
    }

    # update the message body
    if (scalar($email->parts) > 1) {
        $email->walk_parts(sub {
            my ($part) = @_;

            # skip top-level
            return if $part->parts > 1;

            # do not filter attachments such as patches, etc.
            return if
                $part->header('Content-Disposition')
                && $part->header('Content-Disposition') =~ /attachment/;

            # text/plain|html only
            return unless $part->content_type =~ /^text\/(?:html|plain)/;

            # hide in html content
            if ($replacement && $part->content_type =~ /^text\/html/) {
                $replacement = '<pre style="font-size: 0pt; color: #fff">' . $replacement . '</pre>';
            }

            # and inject
            _replace_placeholder_in_part($part, $replacement);
        });

        # force Email::MIME to re-create all the parts.  without this
        # as_string() doesn't return the updated body for multi-part sub-parts.
        $email->parts_set([ $email->subparts ]);
    }
    else {
        # text-only email
        _replace_placeholder_in_part($email, $replacement);
    }
}

sub _replace_placeholder_in_part {
    my ($part, $replacement) = @_;

    # fix encoding
    my $body = $part->body;
    if (Bugzilla->params->{'utf8'}) {
        $part->charset_set('UTF-8');
        my $raw = $part->body_raw;
        if (utf8::is_utf8($raw)) {
            utf8::encode($raw);
            $part->body_set($raw);
        }
    }
    $part->encoding_set('quoted-printable') if !is_7bit_clean($body);

    # replace
    my $placeholder = quotemeta('@@body-headers@@');
    $body = $part->body_str;
    $body =~ s/$placeholder/$replacement/;
    $part->body_str_set($body);
}

sub _syslog {
    my $message = shift;
    openlog('apache', 'cons,pid', 'local4');
    syslog('notice', encode_utf8($message));
    closelog();
}

sub post_bug_after_creation {
    my ($self, $args) = @_;
    return unless my $format = Bugzilla->input_params->{format};
    my $bug = $args->{vars}->{bug};

    if ($format eq 'employee-incident'
        && $bug->component eq 'Server Operations: Desktop Issues')
    {
        $self->_post_employee_incident_bug($args);
    }
    elsif ($format eq 'swag') {
        $self->_post_gear_bug($args);
    }
    elsif ($format eq 'mozpr') {
        $self->_post_mozpr_bug($args);
    }
}

sub _post_employee_incident_bug {
    my ($self, $args) = @_;
    my $vars = $args->{vars};
    my $bug = $vars->{bug};

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
            cc                => [ 'jstevensen@mozilla.com' ],
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

sub _post_gear_bug {
    my ($self, $args) = @_;
    my $vars = $args->{vars};
    my $bug = $vars->{bug};
    my $input = Bugzilla->input_params;

    my ($team, $code) = $input->{teamcode} =~ /^(.+?) \((\d+)\)$/;
    my @request = (
        "Date Required: $input->{date_required}",
        "$input->{firstname} $input->{lastname}",
        $input->{email},
        $input->{mozspace},
        $team,
        $code,
        $input->{purpose},
    );
    my @recipient = (
        "$input->{shiptofirstname} $input->{shiptolastname}",
        $input->{shiptoemail},
        $input->{shiptoaddress1},
        $input->{shiptoaddress2},
        $input->{shiptocity},
        $input->{shiptostate},
        $input->{shiptopostcode},
        $input->{shiptocountry},
        "Phone: $input->{shiptophone}",
        $input->{shiptoidrut},
    );

    # the csv has 14 item fields
    my @items = map { trim($_) } split(/\n/, $input->{items});
    my @csv;
    while (@items) {
        my @batch;
        if (scalar(@items) > 14) {
            @batch = splice(@items, 0, 14);
        }
        else {
            @batch = @items;
            push @batch, '' for scalar(@items)..13;
            @items = ();
        }
        push @csv, [ @request, @batch, @recipient ];
    }

    # csv quoting and concat
    foreach my $line (@csv) {
        foreach my $field (@$line) {
            if ($field =~ s/"/""/g || $field =~ /,/) {
                $field = qq#"$field"#;
            }
        }
        $line = join(',', @$line);
    }

    $self->_add_attachment($args, {
        data        => join("\n", @csv),
        description => "Items (CSV)",
        filename    => "gear_" . $bug->id . ".csv",
        mimetype    => "text/csv",
    });
    $bug->update($bug->creation_ts);
}

sub _post_mozpr_bug {
    my ($self, $args) = @_;
    my $vars = $args->{vars};
    my $bug = $vars->{bug};
    my $input = Bugzilla->input_params;

    if ($input->{proj_mat_file}) {
        $self->_add_attachment($args, {
            data        => $input->{proj_mat_file_attach},
            description => $input->{proj_mat_file_desc},
            filename    => scalar $input->{proj_mat_file_attach},
        });
    }
    if ($input->{pr_mat_file}) {
        $self->_add_attachment($args, {
            data        => $input->{pr_mat_file_attach},
            description => $input->{pr_mat_file_desc},
            filename    => scalar $input->{pr_mat_file_attach},
        });
    }
    $bug->update($bug->creation_ts);
}

sub _add_attachment {
    my ($self, $args, $attachment_args) = @_;

    my $bug = $args->{vars}->{bug};
    $attachment_args->{bug}         = $bug;
    $attachment_args->{creation_ts} = $bug->creation_ts;
    $attachment_args->{ispatch}     = 0 unless exists $attachment_args->{ispatch};
    $attachment_args->{isprivate}   = 0 unless exists $attachment_args->{isprivate};
    $attachment_args->{mimetype}    ||= $self->_detect_content_type($attachment_args->{data});

    # If the attachment cannot be successfully added to the bug,
    # we notify the user, but we don't interrupt the bug creation process.
    my $old_error_mode = Bugzilla->error_mode;
    Bugzilla->error_mode(ERROR_MODE_DIE);
    my $attachment;
    eval {
        $attachment = Bugzilla::Attachment->create($attachment_args);
    };
    warn "$@" if $@;
    Bugzilla->error_mode($old_error_mode);

    if ($attachment) {
        # Insert comment for attachment
        $bug->add_comment('', { isprivate  => 0,
                                type       => CMT_ATTACHMENT_CREATED,
                                extra_data => $attachment->id });
        delete $bug->{attachments};
    }
    else {
        $args->{vars}->{'message'} = 'attachment_creation_failed';
    }

    # Note: you must call $bug->update($bug->creation_ts) after adding all attachments
}

# bugzilla's content_type detection makes assumptions about form fields, which
# means we can't use it here.  this code is lifted from
# Bugzilla::Attachment::get_content_type and the TypeSniffer extension.
sub _detect_content_type {
    my ($self, $data) = @_;
    my $cgi = Bugzilla->cgi;

    # browser provided content-type
    my $content_type = $cgi->uploadInfo($data)->{'Content-Type'};
    $content_type = 'image/png' if $content_type eq 'image/x-png';

    if ($content_type eq 'application/octet-stream') {
        # detect from filename
        my $filename = scalar($data);
        if (my $from_filename = mimetype($filename)) {
            return $from_filename;
        }
    }

    return $content_type || 'application/octet-stream';
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

sub enter_bug_start {
    my ($self, $args) = @_;
    # if configured with create_bug_formats, force users into a custom bug
    # format (can be overridden with a __standard__ format)
    my $cgi = Bugzilla->cgi;
    if ($cgi->param('format') && $cgi->param('format') eq '__standard__') {
        $cgi->delete('format');
    } elsif (my $format = forced_format($cgi->param('product'))) {
        $cgi->param('format', $format);
    }

    # If product eq 'mozilla.org' and format eq 'itrequest', then
    # switch to the new 'Infrastructure & Operations' product.
    if ($cgi->param('product') && $cgi->param('product') eq 'mozilla.org'
        && $cgi->param('format') && $cgi->param('format') eq 'itrequest')
    {
        $cgi->param('product', 'Infrastructure & Operations');
    }

    # map renamed groups
    $cgi->param('groups', _map_groups($cgi->param('groups')));
}

sub bug_before_create {
    my ($self, $args) = @_;
    my $params = $args->{params};
    if (exists $params->{groups}) {
        # map renamed groups
        $params->{groups} = [ _map_groups($params->{groups}) ];
    }
}

sub _map_groups {
    my (@groups) = @_;
    return unless @groups;
    @groups = @{ $groups[0] } if ref($groups[0]);
    return map {
        # map mozilla-corporation-confidential => mozilla-employee-confidential
        $_ eq 'mozilla-corporation-confidential'
        ? 'mozilla-employee-confidential'
        : $_
    } @groups;
}

sub forced_format {
    # note: this is also called from the guided bug entry extension
    my ($product) = @_;
    return undef unless defined $product;

    # always work on the correct product name
    $product = Bugzilla::Product->new({ name => $product, cache => 1 })
        unless blessed($product);
    return undef unless $product;

    # check for a forced-format entry
    my $forced = $create_bug_formats{$product->name}
        || return;

    # should this user be included?
    my $user = Bugzilla->user;
    my $include = ref($forced->{include}) ? $forced->{include} : [ $forced->{include} ];
    foreach my $inc (@$include) {
        return $forced->{format} if $user->in_group($inc);
    }

    return undef;
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
        _syslog(sprintf("[db_query] %s %s", $user->login, $query));

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

# you can always file bugs into a product's default security group, as well as
# into any of the groups in @always_fileable_groups
sub _group_always_settable {
    my ($self, $group) = @_;
    return
        $group->name eq $self->default_security_group
        || ((grep { $_ eq $group->name } @always_fileable_groups) ? 1 : 0);
}

sub _default_security_group {
    my ($self) = @_;
    return exists $product_sec_groups{$self->name}
        ? $product_sec_groups{$self->name}
        : $product_sec_groups{_default};
}

sub _default_security_group_obj {
    my ($self) = @_;
    return unless my $group_name = $self->default_security_group;
    return Bugzilla::Group->new({ name => $group_name, cache => 1 })
}

# called from the verify version, component, and group page.
# if we're making a group invalid, stuff the default group into the cgi param
# to make it checked by default.
sub _check_default_product_security_group {
    my ($self, $product, $invalid_groups, $optional_group_controls) = @_;
    return unless my $group = $product->default_security_group_obj;
    if (@$invalid_groups) {
        my $cgi = Bugzilla->cgi;
        my @groups = $cgi->param('groups');
        push @groups, $group->name unless grep { $_ eq $group->name } @groups;
        $cgi->param('groups', @groups);
    }
}

sub install_filesystem {
    my ($self, $args) = @_;
    my $files = $args->{files};
    my $extensions_dir = bz_locations()->{extensionsdir};
    $files->{"$extensions_dir/BMO/bin/migrate-github-pull-requests.pl"} = {
        perms => Bugzilla::Install::Filesystem::OWNER_EXECUTE
    };
}

# "deleted" comment tag

sub config_modify_panels {
    my ($self, $args) = @_;
    push @{ $args->{panels}->{groupsecurity}->{params} }, {
        name    => 'delete_comments_group',
        type    => 's',
        choices => \&Bugzilla::Config::GroupSecurity::_get_all_group_names,
        default => 'admin',
        checker => \&check_group
    };
}

sub comment_after_add_tag {
    my ($self, $args) = @_;
    my $tag = $args->{tag};
    return unless lc($tag) eq 'deleted';

    my $group_name = Bugzilla->params->{delete_comments_group};
    if (!$group_name || !Bugzilla->user->in_group($group_name)) {
        ThrowUserError('auth_failure', { group  => $group_name,
                                         action => 'delete',
                                         object => 'comments' });
    }
}

sub comment_after_remove_tag {
    my ($self, $args) = @_;
    my $tag = $args->{tag};
    return unless lc($tag) eq 'deleted';

    my $group_name = Bugzilla->params->{delete_comments_group};
    if (!$group_name || !Bugzilla->user->in_group($group_name)) {
        ThrowUserError('auth_failure', { group  => $group_name,
                                         action => 'delete',
                                         object => 'comments' });
    }
}

BEGIN {
    *Bugzilla::Comment::has_tag = \&_comment_has_tag;
}

sub _comment_has_tag {
    my ($self, $test_tag) = @_;
    $test_tag = lc($test_tag);
    foreach my $tag (@{ $self->tags }) {
        return 1 if lc($tag) eq $test_tag;
    }
    return 0;
}

sub bug_comments {
    my ($self, $args) = @_;
    my $can_delete = Bugzilla->user->in_group(Bugzilla->params->{delete_comments_group});
    my $comments = $args->{comments};
    my @deleted = grep { $_->has_tag('deleted') } @$comments;
    while (my $comment = pop @deleted) {
        for (my $i = scalar(@$comments) - 1; $i >= 0; $i--) {
            if ($comment == $comments->[$i]) {
                if ($can_delete) {
                    # don't remove comment from users who can "delete" them
                    # just collapse it instead
                    $comment->{collapsed} = 1;
                }
                else {
                    # otherwise, remove it from the array
                    splice(@$comments, $i, 1);
                }
                last;
            }
        }
    }
}

__PACKAGE__->NAME;
