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

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Bug;
use Bugzilla::BugMail;
use Bugzilla::Config::Common qw(check_group get_all_group_names);
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Field;
use Bugzilla::Field::Choice;
use Bugzilla::Group;
use Bugzilla::Install::Filesystem;
use Bugzilla::Mailer;
use Bugzilla::Product;
use Bugzilla::Status;
use Bugzilla::Token;
use Bugzilla::User;
use Bugzilla::UserAgent qw(detect_platform detect_op_sys);
use Bugzilla::User::Setting;
use Bugzilla::Util;

use Date::Parse;
use DateTime;
use Email::MIME::ContentType qw(parse_content_type);
use Encode qw(find_encoding encode_utf8);
use File::MimeInfo::Magic;
use List::MoreUtils qw(natatime any last_value);
use List::Util qw(first);
use Scalar::Util qw(blessed);
use Sys::Syslog qw(:DEFAULT);
use Text::Balanced qw( extract_bracketed extract_multiple );
use JSON::MaybeXS;
use Mojo::File qw(path);

use Bugzilla::Extension::BMO::Constants;
use Bugzilla::Extension::BMO::FakeBug;
use Bugzilla::Extension::BMO::Data;

our $VERSION = '0.1';

#
# Monkey-patched methods
#

BEGIN {
    *Bugzilla::Bug::last_closed_date                = \&_last_closed_date;
    *Bugzilla::Bug::reporters_hw_os                 = \&_bug_reporters_hw_os;
    *Bugzilla::Bug::is_unassigned                   = \&_bug_is_unassigned;
    *Bugzilla::Bug::has_current_patch               = \&_bug_has_current_patch;
    *Bugzilla::Bug::missing_sec_approval            = \&_bug_missing_sec_approval;
    *Bugzilla::Product::default_security_group      = \&_default_security_group;
    *Bugzilla::Product::default_security_group_obj  = \&_default_security_group_obj;
    *Bugzilla::Product::group_always_settable       = \&_group_always_settable;
    *Bugzilla::Product::default_platform_id         = \&_product_default_platform_id;
    *Bugzilla::Product::default_op_sys_id           = \&_product_default_op_sys_id;
    *Bugzilla::Product::default_platform            = \&_product_default_platform;
    *Bugzilla::Product::default_op_sys              = \&_product_default_op_sys;
    *Bugzilla::check_default_product_security_group = \&_check_default_product_security_group;
    *Bugzilla::Attachment::is_bounty_attachment     = \&_attachment_is_bounty_attachment;
    *Bugzilla::Attachment::bounty_details           = \&_attachment_bounty_details;
    *Bugzilla::Attachment::external_redirect        = \&_attachment_external_redirect;
    *Bugzilla::Attachment::can_review               = \&_attachment_can_review;
    *Bugzilla::Attachment::fetch_github_pr_diff     = \&_attachment_fetch_github_pr_diff;
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
    elsif ($file eq 'bug/edit.html.tmpl' || $file eq 'bug_modal/edit.html.tmpl') {
        $vars->{split_cf_crash_signature} = $self->_split_crash_signature($vars);
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

    if ($file =~ /^admin\/products\/(create|edit)\./) {
        my $product = $vars->{product};
        my $security_groups = Bugzilla::Group->match({ isbuggroup => 1, isactive => 1 });
        if ($product) {
            # If set group is not active currently, we add it into the list
            if (!grep($_->name eq $product->default_security_group, @$security_groups)) {
                push(@$security_groups, $product->default_security_group_obj);
                @$security_groups = sort { $a->name cmp $b->name } @$security_groups;
            }
        }
        $vars->{security_groups} = $security_groups;
    }
}

sub page_before_template {
    my ($self, $args) = @_;
    my $page = $args->{'page_id'};
    my $vars = $args->{'vars'};

    if ($page eq 'user_activity.html') {
        require Bugzilla::Extension::BMO::Reports::UserActivity;
        Bugzilla::Extension::BMO::Reports::UserActivity::report($vars);

    }
    elsif ($page eq 'triage_reports.html') {
        require Bugzilla::Extension::BMO::Reports::Triage;
        Bugzilla::Extension::BMO::Reports::Triage::unconfirmed($vars);
    }
    elsif ($page eq 'triage_owners.html') {
        require Bugzilla::Extension::BMO::Reports::Triage;
        Bugzilla::Extension::BMO::Reports::Triage::owners($vars);
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
        Bugzilla::Extension::BMO::Reports::Groups::members_report($page, $vars);
    }
    elsif ($page eq 'recruiting_dashboard.html') {
        require Bugzilla::Extension::BMO::Reports::Recruiting;
        Bugzilla::Extension::BMO::Reports::Recruiting::report($vars);
    }
    elsif ($page eq 'internship_dashboard.html') {
        require Bugzilla::Extension::BMO::Reports::Internship;
        Bugzilla::Extension::BMO::Reports::Internship::report($vars);
    }
    elsif ($page eq 'email_queue.html') {
        print Bugzilla->cgi->redirect('view_job_queue.cgi');
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
    elsif ($page eq 'attachment_bounty_form.html') {
        bounty_attachment($vars);
    }
    elsif ($page eq 'triage_request.html') {
        triage_request($vars);
    }
}

sub bounty_attachment {
    my ($vars) = @_;

    my $user = Bugzilla->user;
    $user->in_group('bounty-team')
        || ThrowUserError("auth_failure", { group  => "bounty-team",
                                            action => "add",
                                            object => "bounty_attachments" });

    my $input      = Bugzilla->input_params;
    my $dbh        = Bugzilla->dbh;
    my $bug        = Bugzilla::Bug->check({ id => $input->{bug_id}, cache => 1 });
    my $attachment = first { $_ && _attachment_is_bounty_attachment($_) } @{$bug->attachments};
    $vars->{bug}   = $bug;

    if ($input->{submit}) {
        ThrowUserError('bounty_attachment_missing_reporter')
            unless $input->{reporter_email};

        check_hash_token($input->{token}, ['bounty', $bug->id]);

        my @fields = qw( reporter_email amount_paid reported_date fixed_date awarded_date publish );
        my %form =  map { $_ => $input->{$_} } @fields;
        $form{credit} = [ grep { defined } map { $input->{"credit_$_"} } 1..3 ];

        $dbh->bz_start_transaction();
        if ($attachment) {
            $attachment->set(
                description => format_bounty_attachment_description(\%form)
            );
            $attachment->update;
        }
        else {
            my $attachment = Bugzilla::Attachment->create({
                bug         => $bug,
                isprivate   => 1,
                mimetype    => 'text/plain',
                data        => 'bounty',
                filename    => 'bugbounty.data',
                description => format_bounty_attachment_description(\%form),
            });
        }
        $dbh->bz_commit_transaction();

        Bugzilla::BugMail::Send($bug->id, { changer => $user });

        print Bugzilla->cgi->redirect('show_bug.cgi?id=' . $bug->id);
        exit;
    }

    if ($attachment) {
        $vars->{form} = $attachment->bounty_details;
    }
    else {
        my $now = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
        $vars->{form} = {
            reporter_email => $bug->reporter->email,
            reported_date  => format_time($bug->creation_ts, "%Y-%m-%d"),
            awarded_date   => format_time($now, "%Y-%m-%d"),
            publish        => 1
        };
        if ($bug->cf_last_resolved) {
            $vars->{form}{fixed_date} = format_time($bug->cf_last_resolved, "%Y-%m-%d"),
        }
    }
    $vars->{form}{token} = issue_hash_token(['bounty', $bug->id]);
}

sub _attachment_is_bounty_attachment {
    my ($attachment) = @_;

    return 0 unless $attachment->filename eq 'bugbounty.data';
    return 0 unless $attachment->contenttype eq 'text/plain';
    return 0 unless $attachment->isprivate;
    return 0 unless $attachment->attacher->in_group('bounty-team');

    return $attachment->description =~ /^(?:[^,]*,)+[^,]*$/;
}

sub _attachment_bounty_details {
    my ($attachment) = @_;
    if (!exists $attachment->{bounty_details}) {
        if ($attachment->is_bounty_attachment) {
            $attachment->{bounty_details} = parse_bounty_attachment_description($attachment->description);
        }
        else {
            $attachment->{bounty_details} = undef;
        }
    }
    return $attachment->{bounty_details};
}

sub format_bounty_attachment_description {
    my ($form) = @_;
    my @fields = (
        @$form{qw( reporter_email amount_paid reported_date fixed_date awarded_date )},
        $form->{publish} ? 'true' : 'false',
        @{ $form->{credit} // [] }
    );

    return join(',', map { $_ // '' } @fields);
}

sub parse_bounty_attachment_description {
    my ($desc) = @_;

    my %map = ( true => 1, false => 0 );
    my $date = qr/\d{4}-\d{2}-\d{2}/;
    $desc =~ m!
        ^
        (?<reporter_email> [^,]+)          \s*,\s*
        (?<amount_paid>    [0-9]+[-+?]?) ? \s*,\s*
        (?<reported_date>  $date)        ? \s*,\s*
        (?<fixed_date>     $date)        ? \s*,\s*
        (?<awarded_date>   $date)        ? \s*,\s*
        (?<publish>        (?i: true | false )) ?
        (?: \s*,\s* (?<credits>.*) ) ?
        $
    !x;

    return {
        reporter_email => $+{reporter_email} // '',
        amount_paid    => $+{amount_paid}    // '',
        reported_date  => $+{reported_date}  // '',
        fixed_date     => $+{fixed_date}     // '',
        awarded_date   => $+{awarded_date}   // '',
        publish        => $map{ $+{publish} // 'false' },
        credit         => [grep { $_ } split(/\s*,\s*/, $+{credits}) ]
    };
}

sub triage_request {
    my ($vars) = @_;
    my $user = Bugzilla->login(LOGIN_REQUIRED);
    if (Bugzilla->input_params->{update}) {
        Bugzilla->set_user(Bugzilla::User->super_user);
        $user->set_groups({ add => [ 'canconfirm' ] });
        Bugzilla->set_user($user);
        $user->update();
        $vars->{updated} = 1;
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
    my ($field_name, $product_name, $component_name, $bug) = @_;

    # check bugzilla's built-in visibility controls first
    if ($bug) {
        my $field = Bugzilla::Field->new({ name => $field_name, cache => 1 });
        return 1 if $field && !$field->is_visible_on_bug($bug);
    }

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
        # Cannot use the standard %cf_setter mapping as we want anyone
        # to be able to set ?, just not the other values.
        if ($field eq 'cf_cab_review') {
            if ($new_value ne '1'
                && $new_value ne '?'
                && !$user->in_group('infra', $bug->product_id))
            {
                push (@$priv_results, PRIVILEGES_REQUIRED_EMPOWERED);
            }
        }
        # "other" custom field setters restrictions
        elsif (exists $cf_setters->{$field}) {
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
                $new_value eq 'INCOMPLETE' ||
                ($old_value eq '' && $new_value eq '1')))
        {
            push (@$priv_results, PRIVILEGES_REQUIRED_NONE);
        }
        elsif ($field eq 'dup_id') {
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
        match => qr/(?<!\/|=)\b((?:CVE|CAN)-\d{4}-(?:\d{4}|[1-9]\d{4,})(?!\d))\b/,
        replace => sub {
            my $args = shift;
            my $match = html_quote($args->{matches}->[0]);
            return qq{<a href="https://cve.mitre.org/cgi-bin/cvename.cgi?name=$match">$match</a>};
        }
    });

    # link to svn.m.o
    push (@$regexes, {
        match => qr/(^|\s)r(\d{4,})\b/,
        replace => sub {
            my $args = shift;
            my $match = html_quote($args->{matches}->[1]);
            return
                $args->{matches}->[0] .
                qq{<a href="https://viewvc.svn.mozilla.org/vc?view=rev&amp;revision=$match">r$match</a>};
        }
    });

    # link old git.mozilla.org commit messages to github
    push (@$regexes, {
        match => qr#^(To\s(?:ssh://)?(?:[^\@]+\@)?git\.mozilla\.org[:/](.+?\.git)\n
                    \s+)([0-9a-z]+\.\.([0-9a-z]+)\s+\S+\s->\s\S+)#mx,
        replace => sub {
            my $args = shift;
            my $preamble = html_quote($args->{matches}->[0]);
            my $repo = html_quote($args->{matches}->[1]);
            my $text = html_quote($args->{matches}->[2]);
            my $revision = html_quote($args->{matches}->[3]);
            $repo = 'mozilla/webtools-bmo-bugzilla' if $repo =~ /^webtools\/bmo\/bugzilla/;
            $repo = 'bugzilla/bugzilla' if $repo =~ /^bugzilla\/bugzilla\.git/;
            $repo = 'bugzilla/bugzilla.org' if $repo =~ /^www\/bugzilla\.org/;
            return qq#$preamble<a href="https://github.com/$repo/commit/$revision">$text</a>#;
        }
    });

    # link github commit messages
    push (@$regexes, {
        match => qr#^(To\s(?:https://|git@)?github\.com[:/](.+?)\.git\n
                    \s+)([0-9a-z]+\.\.([0-9a-z]+)\s+\S+\s->\s\S+)#mx,
        replace => sub {
            my $args = shift;
            my $preamble = html_quote($args->{matches}->[0]);
            my $repo = html_quote($args->{matches}->[1]);
            my $text = html_quote($args->{matches}->[2]);
            my $revision = html_quote($args->{matches}->[3]);
            return qq#$preamble<a href="https://github.com/$repo/commit/$revision">$text</a>#;
        }
    });

    # link github pull requests and issues
    push (@$regexes, {
        match => qr/(\s)([A-Za-z0-9_\.-]+)\/([A-Za-z0-9_\.-]+)\#([0-9]+)\b/,
        replace => sub {
            my $args = shift;
            my $owner = html_quote($args->{matches}->[1]);
            my $repo = html_quote($args->{matches}->[2]);
            my $number = html_quote($args->{matches}->[3]);
            return qq# <a href="https://github.com/$owner/$repo/issues/$number">$owner/$repo\#$number</a>#;
        }
    });

    # Update certain links to git.mozilla.org to go to github.com instead
    # https://git.mozilla.org/?p=webtools/bmo/bugzilla.git;a=blob;f=Bugzilla/WebService/Bug.pm;h=d7a1d8f9bb5fdee524f2bb342a4573a63d890f2e;hb=HEAD#l657
    push(@$regexes, {
        match => qr#\b(https?://git\.mozilla\.org\S+)\b#mx,
        replace => sub {
            my $args  = shift;
            my $match = $args->{matches}->[0];
            my $uri   = URI->new($match);
            my $text  = html_quote($match);

            # Only work on BMO and Bugzilla repos
            my $repo = html_quote($uri->query_param_delete("p")) || '';
            if ($repo !~ /(webtools\/bmo|bugzilla)\//) {
                return qq#<a href="$text">$text</a>#;
            }

            my $action   = html_quote($uri->query_param_delete("a"))  || '';
            my $file     = html_quote($uri->query_param_delete("f"))  || '';
            my $frag     = html_quote($uri->fragment)                 || '';
            my $from_rev = html_quote($uri->query_param_delete("h"))  || '';
            my $to_rev   = html_quote($uri->query_param_delete("hb")) || '';

            if ($frag) {
               $frag =~ tr/l/L/;
               $frag = "#$frag";
            }

            $to_rev = $from_rev if !$to_rev;
            $to_rev = 'master' if $to_rev eq 'HEAD';
            $to_rev =~ s#refs/heads/(.*)$#$1#;

            $repo = 'mozilla-bteam/bmo' if $repo =~ /^webtools\/bmo\/bugzilla\.git$/;
            $repo = 'bugzilla/bugzilla' if $repo =~ /^bugzilla\/bugzilla\.git$/;
            $repo = 'bugzilla/bugzilla.org' if $repo =~ /^www\/bugzilla\.org\.git$/;

            if ($action eq 'tree') {
                return $to_rev eq 'HEAD'
                       ? qq#<a href="https://github.com/$repo">$text [github]</a>#
                       : qq#<a href="https://github.com/$repo/tree/$to_rev">$text [github]</a>#;
            }
            if ($action eq 'blob') {
                return qq#<a href="https://github.com/$repo/blob/$to_rev/$file$frag">$text [github]</a>#;
            }
            if ($action eq 'shortlog' || $action eq 'log') {
                return qq#<a href="https://github.com/$repo/commits/$to_rev">$text [github]</a>#;
            }
            if ($action eq 'commit' || $action eq 'commitdiff') {
                return qq#<a href="https://github.com/$repo/commit/$to_rev">$text [github]</a>#;
            }
            return qq#<a href="$text">$text</a>#;
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

sub object_columns {
    my ($self, $args) = @_;
    return unless $args->{class}->isa('Bugzilla::Product');
    push @{ $args->{columns} }, qw(
        default_platform_id
        default_op_sys_id
        security_group_id
    );
}

sub object_update_columns {
    my ($self, $args) = @_;
    return unless $args->{object}->isa('Bugzilla::Product');
    push @{ $args->{columns} }, qw(
        default_platform_id
        default_op_sys_id
        security_group_id
    );
}

sub object_before_create {
    my ($self, $args) = @_;
    return unless $args->{class}->isa('Bugzilla::Product');

    my $cgi = Bugzilla->cgi;
    my $params = $args->{params};
    foreach my $field (qw( default_platform_id default_op_sys_id security_group_id )) {
        $params->{$field} = $cgi->param($field);
    }
}

sub object_end_of_set_all {
    my ($self, $args) = @_;
    my $object = $args->{object};
    return unless $object->isa('Bugzilla::Product');

    my $cgi = Bugzilla->cgi;
    my $params = $args->{params};
    foreach my $field (qw( default_platform_id default_op_sys_id security_group_id )) {
        my $value = $cgi->param($field);
        detaint_natural($value);
        $object->set($field, $value);
    }
}

sub object_end_of_create {
    my ($self, $args) = @_;
    my $class = $args->{class};

    if ($class eq 'Bugzilla::User') {
        my $user = $args->{object};

        # Log real IP addresses for auditing
        Bugzilla->audit(sprintf('<%s> created user %s', remote_ip(), $user->login));

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
        Bugzilla->audit(sprintf('%s <%s> created bug %s', Bugzilla->user->login, remote_ip(), $args->{object}->id));
    }
}

sub _bug_reporters_hw_os {
    my ($self) = @_;
    return $self->{ua_hw_os} if exists $self->{ua_hw_os};
    my $memcached = Bugzilla->memcached;
    my $hw_os = $memcached->get({ key => 'bug.ua.' . $self->id });
    if (!$hw_os) {
        (my $ua) = Bugzilla->dbh->selectrow_array(
            "SELECT user_agent FROM bug_user_agent WHERE bug_id = ?",
            undef,
            $self->id);
        $hw_os = $ua
            ? [ detect_platform($ua), detect_op_sys($ua) ]
            : [];
        $memcached->set({ key => 'bug.ua.' . $self->id, value => $hw_os });
    }
    return $self->{ua_hw_os} = $hw_os;
}

sub _bug_is_unassigned {
    my ($self) = @_;
    my $assignee = $self->assigned_to->login;
    return $assignee eq 'nobody@mozilla.org' || $assignee =~ /\.bugs$/;
}

sub _bug_has_current_patch {
    my ($self) = @_;
    foreach my $attachment (@{ $self->attachments }) {
        next if $attachment->isobsolete;
        return 1 if $attachment->can_review;
    }
    return 0;
}

sub _bug_missing_sec_approval {
    my ($self) = @_;
    # see https://wiki.mozilla.org/Security/Bug_Approval_Process for the rules

    # no need to alert once a bug is closed
    return 0 if $self->resolution;

    # only bugs with sec-high or sec-critical keywords need sec-approval
    return 0 unless $self->has_keyword('sec-high') || $self->has_keyword('sec-critical');

    # look for patches with sec-approval set to any value
    foreach my $attachment (@{ $self->attachments }) {
        next if $attachment->isobsolete || !$attachment->ispatch;
        foreach my $flag (@{ $attachment->flags }) {
            # only one patch needs sec-approval
            return 0 if $flag->name eq 'sec-approval';
        }
    }

    # tracking flags
    require Bugzilla::Extension::TrackingFlags::Flag;
    my $flags = Bugzilla::Extension::TrackingFlags::Flag->match({
        product     => $self->product,
        component   => $self->component,
        bug_id      => $self->id,
        is_active   => 1,
        WHERE       => {
            'name like ?' => 'cf_status_firefox%',
        },
    });
    # set flags are added after the sql query, filter those out
    $flags = [ grep { $_->name =~ /^cf_status_firefox/ } @$flags ];
    return 0 unless @$flags;

    my $nightly = last_value { $_->name !~ /_esr\d+$/ } @$flags;
    my $set = 0;
    foreach my $flag (@$flags) {
        my $value = $flag->bug_flag($self->id)->value;
        next if $value eq '---';
        $set++;
        # sec-approval is required if any of the current status-firefox
        # tracking flags that aren't the latest are set to 'affected'
        return 1 if $flag->name ne $nightly->name && $value eq 'affected';
    }
    # sec-approval is required if no tracking flags are set
    return $set == 0;
}

sub _product_default_platform_id { $_[0]->{default_platform_id} }
sub _product_default_op_sys_id   { $_[0]->{default_op_sys_id}   }

sub _product_default_platform {
    my ($self) = @_;
    if (!exists $self->{default_platform}) {
        $self->{default_platform} = $self->default_platform_id
            ? Bugzilla::Field::Choice
                ->type('rep_platform')
                ->new($_[0]->{default_platform_id})
                ->name
            : undef;
    }
    return $self->{default_platform};
}
sub _product_default_op_sys {
    my ($self) = @_;
    if (!exists $self->{default_op_sys}) {
        $self->{default_op_sys} = $self->default_op_sys_id
            ? Bugzilla::Field::Choice
                ->type('op_sys')
                ->new($_[0]->{default_op_sys_id})
                ->name
            : undef;
    }
    return $self->{default_op_sys};
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

sub bug_end_of_create {
    my ($self, $args) = @_;
    my $bug = $args->{'bug'};

    # automatically CC users to bugs based on group & product
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

    # store user-agent
    if (my $ua = Bugzilla->cgi->user_agent) {
        trick_taint($ua);
        Bugzilla->dbh->do(
            "INSERT INTO bug_user_agent (bug_id, user_agent) VALUES (?, ?)",
            undef,
            $bug->id, $ua
        );
    }
}

sub sanitycheck_check {
    my ($self, $args) = @_;

    my $dbh = Bugzilla->dbh;
    my $status = $args->{'status'};
    $status->('bmo_check_cf_visible_in_products');

    my $products = $dbh->selectcol_arrayref('SELECT name FROM products');
    my %product = map { $_ => 1 } @$products;
    my @cf_products = map { keys %$_ } values %$cf_visible_in_products;
    foreach my $cf_product (@cf_products) {
        $status->('bmo_check_cf_visible_in_products_missing',
                  { cf_product => $cf_product }, 'alert') unless $product{$cf_product};
    }
}

sub db_sanitize {
    print "deleting reporter's user-agents...\n";
    Bugzilla->dbh->do("TRUNCATE TABLE bug_user_agent");
}

# bugs in an ASSIGNED state must be assigned to a real person
# reset bugs to NEW if the assignee is nobody/.bugs$
sub object_start_of_update {
    my ($self, $args) = @_;
    my ($new_bug, $old_bug) = @$args{qw( object old_object )};
    return unless $new_bug->isa('Bugzilla::Bug');

    # if either the assignee or status has changed
    return unless
        $old_bug->assigned_to->id != $new_bug->assigned_to->id
        || $old_bug->bug_status ne $new_bug->bug_status;

    # and the bug is now ASSIGNED
    return unless
        $new_bug->bug_status eq 'ASSIGNED';

    # and the assignee isn't a real person
    return unless
        $new_bug->assigned_to->login eq 'nobody@mozilla.org'
        || $new_bug->assigned_to->login =~ /\.bugs$/;

    # and the user can set the status to NEW
    return unless
        $old_bug->check_can_change_field('bug_status', $old_bug->bug_status, 'NEW');

    # if the user is changing the assignee, silently change the bug's status to new
    if ($old_bug->assigned_to->id != $new_bug->assigned_to->id) {
        $new_bug->set_bug_status('NEW');
    }

    # otherwise the user is trying to set the bug's status to ASSIGNED without
    # assigning a real person.  throw an error.
    else {
        ThrowUserError('bug_status_unassigned');
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

    if (my $detected = _detect_attached_url($url)) {
        $attributes->{mimetype} = $detected->{content_type};
        $attributes->{ispatch}  = 0;
    }
}

sub _detect_attached_url {
    my ($url) = @_;

    # trim and check for the pull request url
    return unless defined $url;
    return if length($url) > 256;
    $url = trim($url);
    # ignore urls that contain unescaped characters outside of the range mentioned in RFC 3986 section 2
    return if $url =~ m<[^A-Za-z0-9._~:/?#\[\]@!\$&'()*+,;=`.%-]>;

    foreach my $key (keys %autodetect_attach_urls) {
        my $regex = $autodetect_attach_urls{$key}->{regex};
        if (ref($regex) eq 'CODE') {
            $regex = $regex->();
        }
        if ($url =~ $regex) {
            return $autodetect_attach_urls{$key};
        }
    }

    return undef;
}

sub _attachment_external_redirect {
    my ($self) = @_;

    # must be our supported content-type
    return undef unless
        any { $self->contenttype eq $autodetect_attach_urls{$_}->{content_type} }
        keys %autodetect_attach_urls;

    # must still be a valid url
    return _detect_attached_url($self->data)
}

sub _attachment_can_review {
    my ($self) = @_;

    return 1 if $self->ispatch;
    my $external = $self->external_redirect // return;
    return $external->{can_review};
}

sub _attachment_fetch_github_pr_diff {
    my ($self) = @_;

    # must be our supported content-type
    return undef unless
        any { $self->contenttype eq $autodetect_attach_urls{$_}->{content_type} }
        keys %autodetect_attach_urls;

    # must still be a valid url
    return undef unless _detect_attached_url($self->data);

    my $ua = LWP::UserAgent->new( timeout => 10 );
    if (Bugzilla->params->{proxy_url}) {
        $ua->proxy('https', Bugzilla->params->{proxy_url});
    }

    my $pr_diff = $self->data . ".diff";
    my $response = $ua->get($pr_diff);
    if ($response->is_error) {
        warn "Github fetch error: $pr_diff, " . $response->status_line;
        return "Error retrieving Github pull request diff for " . $self->data;
    }
    return $response->decoded_content;
}

# redirect automatically to github urls
sub attachment_view {
    my ($self, $args) = @_;
    my $attachment = $args->{attachment};
    my $cgi = Bugzilla->cgi;

    # don't redirect if the content-type is specified explicitly
    return if defined $cgi->param('content_type');

    # must be a valid redirection url
    return unless defined $attachment->external_redirect;

    # redirect
    print $cgi->redirect(trim($attachment->data));
    exit;
}

sub install_before_final_checks {
    my ($self, $args) = @_;

    # Add product chooser setting
    add_setting({
        name     => 'product_chooser',
        options  => ['pretty_product_chooser', 'full_product_chooser'],
        default  => 'pretty_product_chooser',
        category => 'User Interface'
    });

    # Add option to inject x-bugzilla headers into the message body to work
    # around gmail filtering limitations
    add_setting({
        name     => 'headers_in_body',
        options  => ['on', 'off'],
        default  => 'off',
        category => 'Email Notifications'
    });

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

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    $args->{schema}->{bug_user_agent} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            bug_id => {
                TYPE       => 'INT3',
                NOTNULL    => 1,
                REFERENCES => {
                    TABLE  => 'bugs',
                    COLUMN => 'bug_id',
                    DELETE => 'CASCADE',
                },
            },
            user_agent => {
                TYPE    => 'MEDIUMTEXT',
                NOTNULL => 1,
            },
        ],
        INDEXES => [
            bug_user_agent_idx => {
                FIELDS => [ 'bug_id' ],
                TYPE   => 'UNIQUE',
            },
        ],
    };
    $args->{schema}->{job_last_run} = {
        FIELDS => [
            id => {
                TYPE       => 'INTSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            name => {
                TYPE => 'VARCHAR(100)',
                NOTNULL => 1,
            },
            last_run => {
                TYPE => 'DATETIME',
                NOTNULL => 1,
            },
        ],
        INDEXES => [
            job_last_run_name_idx => {
                FIELDS => [ 'name' ],
                TYPE   => 'UNIQUE',
            },
        ],
    };
}

sub install_update_db {
    my $dbh = Bugzilla->dbh;

    # per-product hw/os defaults
    my $op_sys_default = _field_value('op_sys', 'Unspecified', 50);
    $dbh->bz_add_column(
        'products',
        'default_op_sys_id' => {
            TYPE       => 'INT2',
            DEFAULT    => $op_sys_default->id,
            REFERENCES => {
                TABLE  => 'op_sys',
                COLUMN => 'id',
                DELETE => 'SET NULL',
            },
        }
    );
    my $platform_default = _field_value('rep_platform', 'Unspecified', 50);
    $dbh->bz_add_column(
        'products',
        'default_platform_id' => {
            TYPE       => 'INT2',
            DEFAULT    => $platform_default->id,
            REFERENCES => {
                TABLE  => 'rep_platform',
                COLUMN => 'id',
                DELETE => 'SET NULL',
            },
        }
    );

    # Migrate old is_active stuff to new patch (is in core in 4.2), The old
    # column name was 'is_active', the new one is 'isactive' (no underscore).
    if ($dbh->bz_column_info('milestones', 'is_active')) {
        $dbh->do("UPDATE milestones SET isactive = 0 WHERE is_active = 0;");
        $dbh->bz_drop_column('milestones', 'is_active');
        $dbh->bz_drop_column('milestones', 'is_searchable');
    }

    # remove tables from the old TryAutoLand extension
    $dbh->bz_drop_table('autoland_branches');
    $dbh->bz_drop_table('autoland_attachments');

    unless (Bugzilla::Field->new({ name => 'cf_rank' })) {
        Bugzilla::Field->create({
            name        => 'cf_rank',
            description => 'Rank',
            type        => FIELD_TYPE_INTEGER,
            mailhead    => 0,
            enter_bug   => 0,
            obsolete    => 0,
            custom      => 1,
            buglist     => 1,
        });
    }
    unless (Bugzilla::Field->new({ name => 'cf_crash_signature' })) {
        Bugzilla::Field->create({
            name        => 'cf_crash_signature',
            description => 'Crash Signature',
            type        => FIELD_TYPE_TEXTAREA,
            mailhead    => 0,
            enter_bug   => 1,
            obsolete    => 0,
            custom      => 1,
            buglist     => 0,
        });
    }

    # Add default security group id column
    if (!$dbh->bz_column_info('products', 'security_group_id')) {
        $dbh->bz_add_column(
            'products',
            'security_group_id' => {
                TYPE    => 'INT3',
                REFERENCES => {
                    TABLE  => 'groups',
                    COLUMN => 'id',
                    DELETE => 'SET NULL',
                },
            }
        );

        # if there are no groups, then we're creating a database from scratch
        # and there's nothing to migrate
        my ($group_count) = $dbh->selectrow_array("SELECT COUNT(*) FROM groups");
        if ($group_count) {
            # Migrate old product_sec_group mappings from the time this change was made
            my %product_sec_groups = (
                "addons.mozilla.org"            => 'client-services-security',
                "Air Mozilla"                   => 'mozilla-employee-confidential',
                "Android Background Services"   => 'cloud-services-security',
                "Audio/Visual Infrastructure"   => 'mozilla-employee-confidential',
                "AUS"                           => 'client-services-security',
                "Bugzilla"                      => 'bugzilla-security',
                "bugzilla.mozilla.org"          => 'bugzilla-security',
                "Cloud Services"                => 'cloud-services-security',
                "Community Tools"               => 'websites-security',
                "Data & BI Services Team"       => 'metrics-private',
                "Developer Documentation"       => 'websites-security',
                "Developer Ecosystem"           => 'client-services-security',
                "Finance"                       => 'finance',
                "Firefox Friends"               => 'mozilla-employee-confidential',
                "Firefox Health Report"         => 'cloud-services-security',
                "Infrastructure & Operations"   => 'mozilla-employee-confidential',
                "Input"                         => 'websites-security',
                "Intellego"                     => 'intellego-team',
                "Internet Public Policy"        => 'mozilla-employee-confidential',
                "L20n"                          => 'l20n-security',
                "Legal"                         => 'legal',
                "Marketing"                     => 'marketing-private',
                "Mozilla Communities"           => 'mozilla-communities-security',
                "Mozilla Corporation"           => 'mozilla-employee-confidential',
                "Mozilla Developer Network"     => 'websites-security',
                "Mozilla Foundation"            => 'mozilla-employee-confidential',
                "Mozilla Foundation Operations" => 'mozilla-foundation-operations',
                "Mozilla Grants"                => 'grants',
                "mozillaignite"                 => 'websites-security',
                "Mozilla Messaging"             => 'mozilla-messaging-confidential',
                "Mozilla Metrics"               => 'metrics-private',
                "mozilla.org"                   => 'mozilla-employee-confidential',
                "Mozilla PR"                    => 'pr-private',
                "Mozilla QA"                    => 'mozilla-employee-confidential',
                "Mozilla Reps"                  => 'mozilla-reps',
                "Popcorn"                       => 'websites-security',
                "Privacy"                       => 'privacy',
                "quality.mozilla.org"           => 'websites-security',
                "Recruiting"                    => 'hr',
                "Release Engineering"           => 'mozilla-employee-confidential',
                "Snippets"                      => 'websites-security',
                "Socorro"                       => 'client-services-security',
                "support.mozillamessaging.com"  => 'websites-security',
                "support.mozilla.org"           => 'websites-security',
                "Talkback"                      => 'talkback-private',
                "Tamarin"                       => 'tamarin-security',
                "Taskcluster"                   => 'taskcluster-security',
                "Testopia"                      => 'bugzilla-security',
                "Tree Management"               => 'mozilla-employee-confidential',
                "Web Apps"                      => 'client-services-security',
                "Webmaker"                      => 'websites-security',
                "Websites"                      => 'websites-security',
                "Webtools"                      => 'webtools-security',
                "www.mozilla.org"               => 'websites-security',
            );
            # 1. Set all to core-security by default
            my $core_sec_group = Bugzilla::Group->new({ name => 'core-security' });
            $dbh->do("UPDATE products SET security_group_id = ?", undef, $core_sec_group->id);
            # 2. Update the ones that have explicit security groups
            foreach my $prod_name (keys %product_sec_groups) {
                my $group_name = $product_sec_groups{$prod_name};
                next if $group_name eq 'core-security'; # already done
                my $group = Bugzilla::Group->new({ name => $group_name, cache => 1 });
                if (!$group) {
                    warn "Security group $group_name not found. Using core-security instead.\n";
                    next;
                }
                $dbh->do("UPDATE products SET security_group_id = ? WHERE name = ?", undef, $group->id, $prod_name);
            }
        }
    }
}

# return the Bugzilla::Field::Choice object for the specified field and value.
# if the value doesn't exist it will be created.
sub _field_value {
    my ($field_name, $value_name, $sort_key) = @_;
    my $field = Bugzilla::Field->check({ name => $field_name });
    my $existing = Bugzilla::Field::Choice->type($field)->match({ value => $value_name });
    return $existing->[0] if $existing && @$existing;
    return Bugzilla::Field::Choice->type($field)->create({
        value    => $value_name,
        sortkey  => $sort_key,
        isactive => 1,
    });
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

    if (Bugzilla->localconfig->{'urlbase'} ne 'https://bugzilla.mozilla.org/'
        && Bugzilla->localconfig->{'urlbase'} ne 'https://bugzilla.allizom.org/')
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
        product      => 'Data & BI Services Team',
        component    => 'Database Operations',
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
    elsif (!$email->content_type
           || $email->content_type =~ /^text\/(?:html|plain)/)
    {
        # text-only email
        _replace_placeholder_in_part($email, $replacement);
    }
}

sub _replace_placeholder_in_part {
    my ($part, $replacement) = @_;

    _fix_encoding($part);

    # replace
    my $placeholder = quotemeta('@@body-headers@@');
    my $body = $part->body_str;
    $body =~ s/$placeholder/$replacement/;
    $part->body_str_set($body);
}

sub _fix_encoding {
    my $part = shift;

    # don't touch the top-level part of multi-part mail
    return if $part->parts > 1;

    # nothing to do if the part already has a charset
    my $ct = parse_content_type($part->content_type);
    my $charset = $ct->{attributes}{charset}
        ? $ct->{attributes}{charset}
        : '';
    return unless !$charset || $charset eq 'us-ascii';

    if (Bugzilla->params->{utf8}) {
        $part->charset_set('UTF-8');
        my $raw = $part->body_raw;
        if (utf8::is_utf8($raw)) {
            utf8::encode($raw);
            $part->body_set($raw);
        }
    }
    $part->encoding_set('quoted-printable');
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
    elsif ($format eq 'shield-studies') {
        $self->_post_shield_studies($args);
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

sub _post_shield_studies {
    my ($self, $args) = @_;
    my $vars       = $args->{vars};
    my $parent_bug = $vars->{bug};
    my $params     = Bugzilla->input_params;
    my (@dep_comment, @dep_errors, @send_mail);

    # Common parameters always passed to _file_child_bug
    # bug_data and template_suffix will be different for each bug
    my $child_params = {
        parent_bug    => $parent_bug,
        template_vars => $vars,
        dep_comment   => \@dep_comment,
        dep_errors    => \@dep_errors,
        send_mail     => \@send_mail,
    };

    # Study Validation Review
    $child_params->{'bug_data'} = {
        short_desc   => '[SHIELD] Study Validation Review for ' . $params->{hypothesis},
        product      => 'Shield',
        component    => 'Shield Study',
        bug_severity => 'normal',
        op_sys       => 'All',
        rep_platform => 'All',
        version      => 'unspecified',
        blocked      => $parent_bug->bug_id,
    };
    $child_params->{'template_suffix'} = 'validation-review';
    _file_child_bug($child_params);

    # Shipping Status
    $child_params->{'bug_data'} = {
        short_desc   => '[SHIELD] Shipping Status for ' . $params->{hypothesis},
        product      => 'Shield',
        component    => 'Shield Study',
        bug_severity => 'normal',
        op_sys       => 'All',
        rep_platform => 'All',
        version      => 'unspecified',
        blocked      => $parent_bug->bug_id,
    };
    $child_params->{'template_suffix'} = 'shipping-status';

    # Data Review
    _file_child_bug($child_params);
    $child_params->{'bug_data'} = {
        short_desc   => '[SHIELD] Data Review for ' . $params->{hypothesis},
        product      => 'Shield',
        component    => 'Shield Study',
        bug_severity => 'normal',
        op_sys       => 'All',
        rep_platform => 'All',
        version      => 'unspecified',
        blocked      => $parent_bug->bug_id,
    };
    $child_params->{'template_suffix'} = 'data-review';
    _file_child_bug($child_params);

    # Legal Review
    $child_params->{'bug_data'} = {
        short_desc   => '[SHIELD] Legal Review for ' . $params->{hypothesis},
        product      => 'Legal',
        component    => 'Firefox',
        bug_severity => 'normal',
        op_sys       => 'All',
        rep_platform => 'All',
        groups       => [ 'mozilla-employee-confidential' ],
        version      => 'unspecified',
        blocked      => $parent_bug->bug_id,
    };
    $child_params->{'template_suffix'} = 'legal';
    _file_child_bug($child_params);

    if (scalar @dep_errors) {
        warn "[Bug " . $parent_bug->id . "] Failed to create additional moz-project-review bugs:\n" .
        join("\n", @dep_errors);
        $vars->{'message'} = 'moz_project_review_creation_failed';
    }

    if (scalar @dep_comment) {
        my $comment = join("\n", @dep_comment);
        if (scalar @dep_errors) {
            $comment .= "\n\nSome errors occurred creating dependent bugs and have been recorded";
        }
        $parent_bug->add_comment($comment);
        $parent_bug->update($parent_bug->creation_ts);
    }

    foreach my $bug_id (@send_mail) {
        Bugzilla::BugMail::Send($bug_id, { changer => Bugzilla->user });
    }
}

sub _file_child_bug {
    my ($params) = @_;
    my ($parent_bug, $template_vars, $template_suffix, $bug_data, $dep_comment, $dep_errors, $send_mail)
        = @$params{qw(parent_bug template_vars template_suffix bug_data dep_comment dep_errors send_mail)};
    my $old_error_mode = Bugzilla->error_mode;
    Bugzilla->error_mode(ERROR_MODE_DIE);

    my $new_bug;
    eval {
        my $comment;
        my $full_template = "bug/create/comment-shield-studies-$template_suffix.txt.tmpl";
        Bugzilla->template->process($full_template, $template_vars, \$comment)
            || ThrowTemplateError(Bugzilla->template->error());
        $bug_data->{'comment'} = $comment;
        if ($new_bug = Bugzilla::Bug->create($bug_data)) {
            my $set_all = {
                dependson => { add => [ $new_bug->bug_id ] }
            };
            $parent_bug->set_all($set_all);
            $parent_bug->update($parent_bug->creation_ts);
        }
    };

    if ($@ || !($new_bug && $new_bug->{'bug_id'})) {
        push(@$dep_comment, "Error creating $template_suffix review bug");
        push(@$dep_errors, "$template_suffix : $@") if $@;
        # Since we performed Bugzilla::Bug::create in an eval block, we
        # need to manually rollback the commit as this is not done
        # in Bugzilla::Error automatically for eval'ed code.
        Bugzilla->dbh->bz_rollback_transaction();
    }
    else {
        push(@$send_mail, $new_bug->id);
        push(@$dep_comment, "Bug " . $new_bug->id . " - " . $new_bug->short_desc);
    }

    undef $@;
    Bugzilla->error_mode($old_error_mode);
}

sub _pre_fxos_feature {
    my ($self, $args) = @_;
    my $cgi = Bugzilla->cgi;
    my $user = Bugzilla->user;
    my $params = $args->{params};

    $params->{keywords} = 'foxfood';
    $params->{keywords} .= ',feature' if ($cgi->param('feature_type') // '') eq 'new';
    $params->{bug_status} = $user->in_group('canconfirm') ? 'NEW' : 'UNCONFIRMED';
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
    if ($cgi->param('format')) {
        if ($cgi->param('format') eq '__standard__') {
            $cgi->delete('format');
            $cgi->param('format_forced', 1);
        }
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
    if ((Bugzilla->cgi->param('format') // '') eq 'fxos-feature') {
        $self->_pre_fxos_feature($args);
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
    my $cgi      = Bugzilla->cgi;
    my $user     = Bugzilla->user;
    my $template = Bugzilla->template;

    # validate group membership
    $user->in_group('query_database')
        || ThrowUserError('auth_failure', { group  => 'query_database',
                                            action => 'access',
                                            object => 'query_database' });

    # read query
    my $input = Bugzilla->input_params;
    my $query = $input->{query};
    $vars->{query} = $query;

    if ($query) {
        # Only allow POST requests
        if ($cgi->request_method ne 'POST') {
            ThrowCodeError('illegal_request_method',
                           { method => $cgi->request_method, accepted => ['POST'] });
        }

        check_hash_token($input->{token}, ['query_database']);
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

        if ($input->{csv}) {
            print $cgi->header(-type=> 'text/csv',
                               -content_disposition=> "attachment; filename=\"query_database.csv\"");
            $template->process("pages/query_database.csv.tmpl", $vars)
                || ThrowTemplateError($template->error());
            exit;
        }
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
    return $_[0]->default_security_group_obj->name;
}

sub _default_security_group_obj {
    my $group_id = $_[0]->{security_group_id};
    if (!$group_id) {
        return Bugzilla::Group->new({ name => Bugzilla->params->{insidergroup}, cache => 1 });
    }
    return Bugzilla::Group->new({ id => $group_id, cache => 1 });
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
    my $create_files = $args->{create_files};
    my $extensions_dir = bz_locations()->{extensionsdir};
    $create_files->{__lbheartbeat__} = {
        perms     => Bugzilla::Install::Filesystem::WS_SERVE,
        overwrite => 1, # the original value for this was wrong, overwrite it
        contents  => 'httpd OK',
    };


    # version.json needs to have a source attribute pointing to
    # our repository. We already have this information in the (static)
    # contribute.json file, so parse that in
    my $json = JSON::MaybeXS->new->pretty->utf8->canonical();
    my $contribute = eval {
        $json->decode(path(bz_locations()->{cgi_path}, "/contribute.json")->slurp);
    };

    if (!$contribute) {
        die "Missing or invalid contribute.json file";
    }

    my $version_obj = {
        source  => $contribute->{repository}{url},
        version => BUGZILLA_VERSION,
        commit  => $ENV{CIRCLE_SHA1}      // 'unknown',
        build   => $ENV{CIRCLE_BUILD_URL} // 'unknown',
    };

    $create_files->{'version.json'} = {
        overwrite => 1,
        perms     => Bugzilla::Install::Filesystem::WS_SERVE,
        contents  => $json->encode($version_obj),
    };

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
        choices => \&get_all_group_names,
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

sub _split_crash_signature {
    my ($self, $vars) = @_;
    my $bug = $vars->{bug} // return;
    my $crash_signature = $bug->cf_crash_signature // return;
    return [
        grep { /\S/ }
        extract_multiple($crash_signature, [ sub { extract_bracketed($_[0], '[]') } ])
    ];
}

sub enter_bug_entrydefaultvars {
    my ($self, $args) = @_;
    my $vars = $args->{vars};
    my $cgi  = Bugzilla->cgi;
    return unless my $format = $cgi->param('format');

    if ($format eq 'fxos-feature') {
        $vars->{feature_type} = $cgi->param('feature_type');
        $vars->{description}  = $cgi->param('description');
        $vars->{discussion}   = $cgi->param('discussion');
    }
}

sub app_startup {
    my ($self, $args) = @_;
    my $app = $args->{app};
    my $r = $app->routes;

    $r->get(
        '/favicon.ico' => sub {
            my $c = shift;
            $c->reply->file(
                $c->app->home->child('extensions/BMO/web/images/favicon.ico')
            );
        }
    );

    $r->any( '/:REWRITE_itrequest' => [ REWRITE_itrequest => qr{form[\.:]itrequest} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'Infrastructure & Operations', 'format' => 'itrequest' } );
    $r->any( '/:REWRITE_mozlist' => [ REWRITE_mozlist => qr{form[\.:]mozlist} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'mozilla.org', 'format' => 'mozlist' } );
    $r->any( '/:REWRITE_presentation' => [ REWRITE_presentation => qr{form[\.:]presentation} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'mozilla.org', 'format' => 'presentation' } );
    $r->any( '/:REWRITE_trademark' => [ REWRITE_trademark => qr{form[\.:]trademark} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'mozilla.org', 'format' => 'trademark' } );
    $r->any( '/:REWRITE_recoverykey' => [ REWRITE_recoverykey => qr{form[\.:]recoverykey} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'mozilla.org', 'format' => 'recoverykey' } );
    $r->any( '/:REWRITE_legal' => [ REWRITE_legal => qr{form[\.:]legal} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'Legal', 'format' => 'legal' }, );
    $r->any( '/:REWRITE_recruiting' => [ REWRITE_recruiting => qr{form[\.:]recruiting} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'Recruiting', 'format' => 'recruiting' } );
    $r->any( '/:REWRITE_intern' => [ REWRITE_intern => qr{form[\.:]intern} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'Recruiting', 'format' => 'intern' } );
    $r->any( '/:REWRITE_mozpr' => [ REWRITE_mozpr => qr{form[\.:]mozpr} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'Mozilla PR', 'format' => 'mozpr' }, );
    $r->any( '/:REWRITE_reps_mentorship' => [ REWRITE_reps_mentorship => qr{form[\.:]reps[\.:]mentorship} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'Mozilla Reps', 'format' => 'mozreps' }, );
    $r->any( '/:REWRITE_reps_budget' => [ REWRITE_reps_budget => qr{form[\.:]reps[\.:]budget} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'Mozilla Reps', 'format' => 'remo-budget' } );
    $r->any( '/:REWRITE_reps_swag' => [ REWRITE_reps_swag => qr{form[\.:]reps[\.:]swag} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'Mozilla Reps', 'format' => 'remo-swag' } );
    $r->any( '/:REWRITE_reps_it' => [ REWRITE_reps_it => qr{form[\.:]reps[\.:]it} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'Mozilla Reps', 'format' => 'remo-it' } );
    $r->any( '/:REWRITE_reps_payment' => [ REWRITE_reps_payment => qr{form[\.:]reps[\.:]payment} ] )
      ->to( 'CGI#page_cgi' => { 'id' => 'remo-form-payment.html' } );
    $r->any( '/:REWRITE_csa_discourse' => [ REWRITE_csa_discourse => qr{form[\.:]csa[\.:]discourse} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'Infrastructure & Operations', 'format' => 'csa-discourse' } );
    $r->any( '/:REWRITE_employee_incident' => [ REWRITE_employee_incident => qr{form[\.:]employee[\.\-:]incident} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'mozilla.org', 'format' => 'employee-incident' } );
    $r->any( '/:REWRITE_brownbag' => [ REWRITE_brownbag => qr{form[\.:]brownbag} ] )
      ->to( 'CGI#https_air_mozilla_org_requests' => {} );
    $r->any( '/:REWRITE_finance' => [ REWRITE_finance => qr{form[\.:]finance} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'Finance', 'format' => 'finance' } );
    $r->any(
        '/:REWRITE_moz_project_review' => [ REWRITE_moz_project_review => qr{form[\.:]moz[\.\-:]project[\.\-:]review} ]
    )->to( 'CGI#enter_bug_cgi' => { 'product' => 'mozilla.org', 'format' => 'moz-project-review' } );
    $r->any( '/:REWRITE_docs' => [ REWRITE_docs => qr{form[\.:]docs?} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'Developer Documentation', 'format' => 'doc' } );
    $r->any( '/:REWRITE_mdn' => [ REWRITE_mdn => qr{form[\.:]mdn?} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'format' => 'mdn', 'product' => 'developer.mozilla.org' } );
    $r->any( '/:REWRITE_swag_gear' => [ REWRITE_swag_gear => qr{form[\.:](?:swag|gear)} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'format' => 'swag', 'product' => 'Marketing' } );
    $r->any( '/:REWRITE_costume' => [ REWRITE_costume => qr{form[\.:]costume} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'Marketing', 'format' => 'costume' } );
    $r->any( '/:REWRITE_ipp' => [ REWRITE_ipp => qr{form[\.:]ipp} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'Internet Public Policy', 'format' => 'ipp' } );
    $r->any( '/:REWRITE_creative' => [ REWRITE_creative => qr{form[\.:]creative} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'format' => 'creative', 'product' => 'Marketing' } );
    $r->any( '/:REWRITE_user_engagement' => [ REWRITE_user_engagement => qr{form[\.:]user[\.\-:]engagement} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'format' => 'user-engagement', 'product' => 'Marketing' } );
    $r->any( '/:REWRITE_mobile_compat' => [ REWRITE_mobile_compat => qr{form[\.:]mobile[\.\-:]compat} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'Tech Evangelism', 'format' => 'mobile-compat' } );
    $r->any( '/:REWRITE_web_bounty' => [ REWRITE_web_bounty => qr{form[\.:]web[\.:]bounty} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'format' => 'web-bounty', 'product' => 'mozilla.org' } );
    $r->any( '/:REWRITE_automative' => [ REWRITE_automative => qr{form[\.:]automative} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'Testing', 'format' => 'automative' } );
    $r->any( '/:REWRITE_comm_newsletter' => [ REWRITE_comm_newsletter => qr{form[\.:]comm[\.:]newsletter} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'format' => 'comm-newsletter', 'product' => 'Marketing' } );
    $r->any( '/:REWRITE_screen_share_whitelist' =>
          [ REWRITE_screen_share_whitelist => qr{form[\.:]screen[\.:]share[\.:]whitelist} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'format' => 'screen-share-whitelist', 'product' => 'Firefox' } );
    $r->any( '/:REWRITE_data_compliance' => [ REWRITE_data_compliance => qr{form[\.:]data[\.\-:]compliance} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'Data Compliance', 'format' => 'data-compliance' } );
    $r->any( '/:REWRITE_fsa_budget' => [ REWRITE_fsa_budget => qr{form[\.:]fsa[\.:]budget} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'FSA', 'format' => 'fsa-budget' } );
    $r->any( '/:REWRITE_triage_request' => [ REWRITE_triage_request => qr{form[\.:]triage[\.\-]request} ] )
      ->to( 'CGI#page_cgi' => { 'id' => 'triage_request.html' } );
    $r->any( '/:REWRITE_crm_CRM' => [ REWRITE_crm_CRM => qr{form[\.:](?:crm|CRM)} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'format' => 'crm', 'product' => 'Marketing' } );
    $r->any( '/:REWRITE_nda' => [ REWRITE_nda => qr{form[\.:]nda} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'Legal', 'format' => 'nda' } );
    $r->any( '/:REWRITE_name_clearance' => [ REWRITE_name_clearance => qr{form[\.:]name[\.:]clearance} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'format' => 'name-clearance', 'product' => 'Legal' } );
    $r->any( '/:REWRITE_shield_studies' => [ REWRITE_shield_studies => qr{form[\.:]shield[\.:]studies} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'Shield', 'format' => 'shield-studies' } );
    $r->any( '/:REWRITE_client_bounty' => [ REWRITE_client_bounty => qr{form[\.:]client[\.:]bounty} ] )
      ->to( 'CGI#enter_bug_cgi' => { 'product' => 'Firefox', 'format' => 'client-bounty' } );
}

__PACKAGE__->NAME;
