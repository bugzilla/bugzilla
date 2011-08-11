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
use Bugzilla::User;
use Bugzilla::User::Setting;
use Bugzilla::Util qw(html_quote trick_taint trim datetime_from detaint_natural);
use Bugzilla::Token;
use Bugzilla::Error;
use Bugzilla::Mailer;

use Scalar::Util qw(blessed);
use Date::Parse;
use DateTime;

use Bugzilla::Extension::BMO::FakeBug;
use Bugzilla::Extension::BMO::Data qw($cf_visible_in_products
                                      $cf_flags
                                      %group_to_cc_map
                                      $blocking_trusted_setters
                                      $blocking_trusted_requesters
                                      $status_trusted_wanters
                                      $status_trusted_setters
                                      $other_setters
                                      %always_fileable_group
                                      %product_sec_groups);
use Bugzilla::Extension::BMO::Reports qw(user_activity_report
                                         triage_reports);

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
    elsif ($file =~ /^bug\/create\/create[\.-]/) {
        if (!$vars->{'cloned_bug_id'}) {
            # Allow status whiteboard values to be bookmarked
            $vars->{'status_whiteboard'} = 
                               Bugzilla->cgi->param('status_whiteboard') || "";
        }
       
        # Purpose: for pretty product chooser
        $vars->{'format'} = Bugzilla->cgi->param('format');

        # Data needed for "this is a security bug" checkbox
        $vars->{'sec_groups'} = \%product_sec_groups;
    }


    if ($file =~ /^list\/list/ || $file =~ /^bug\/create\/create[\.-]/) {
        # hack to allow the bug entry templates to use check_can_change_field 
        # to see if various field values should be available to the current user.
        $vars->{'default'} = Bugzilla::Extension::BMO::FakeBug->new($vars->{'default'} || {});
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
    elsif ($page eq 'remo-form-payment.html') {
        _remo_form_payment($vars);
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

sub cf_hidden_in_product {
    my ($field_name, $product_name, $component_name, $custom_flag_mode) = @_;

    # If used in buglist.cgi, we pass in one_product which is a Bugzilla::Product
    # elsewhere, we just pass the name of the product.
    $product_name = blessed($product_name) ? $product_name->name
                                           : $product_name;
   
    # Also in buglist.cgi, we pass in a list of components instead 
    # of a single compoent name everywhere else.
    my $component_list = ref $component_name ? $component_name 
                                             : [ $component_name ];

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
                        if (grep($_ eq $component, @$component_list)) {
                            $found_component = 1;
                            last;
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
            my ($who, $whoname, $what, $when, 
                $old, $new, $attachid, $fieldname) = (@$ref);
            
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
    
    if ($group_to_cc_map{$group}) {
        my $id = login_to_id($group_to_cc_map{$group});
        $recipients->{$id}->{+REL_CC} = Bugzilla::BugMail::BIT_DIRECT();
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
    return $value ne '---' && $value ne '?';
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
        
        if ($new_value eq '?') {
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

# Purpose: link up various Mozilla-specific strings.
sub _link_uuid {
    my $args = shift;    
    my $match = html_quote($args->{matches}->[0]);
    
    return qq{<a href="https://crash-stats.mozilla.com/report/index/$match">bp-$match</a>};
}

sub _link_cve {
    my $args = shift;
    my $match = html_quote($args->{matches}->[0]);
    
    return qq{<a href="http://cve.mitre.org/cgi-bin/cvename.cgi?name=$match">$match</a>};
}

sub _link_svn {
    my $args = shift;
    my $match = html_quote($args->{matches}->[0]);
    
    return qq{<a href="http://viewvc.svn.mozilla.org/vc?view=rev&amp;revision=$match">r$match</a>};
}

sub _link_hg {
    my $args = shift;
    my $text = html_quote($args->{matches}->[0]);
    my $repo = html_quote($args->{matches}->[1]);
    my $id   = html_quote($args->{matches}->[2]);
    
    return qq{<a href="https://hg.mozilla.org/$repo/rev/$id">$text</a>};
}

sub bug_format_comment {
    my ($self, $args) = @_;
    my $regexes = $args->{'regexes'};

    # Only match if not already in an URL using the negative lookbehind (?<!\/)
    push (@$regexes, {
        match => qr/(?<!\/)\b(?:UUID\s+|bp\-)([a-f0-9]{8}\-[a-f0-9]{4}\-[a-f0-9]{4}\-
                                       [a-f0-9]{4}\-[a-f0-9]{12})\b/x,
        replace => \&_link_uuid
    });

    push (@$regexes, {
        match => qr/(?<!\/)\b((?:CVE|CAN)-\d{4}-\d{4})\b/,
        replace => \&_link_cve
    });
  
    push (@$regexes, {
        match => qr/\b((?:CVE|CAN)-\d{4}-\d{4})\b/,
        replace => \&_link_cve
    });

    push (@$regexes, {
        match => qr/\br(\d{4,})\b/,
        replace => \&_link_svn
    });

    # Note: for grouping in this regexp, always use non-capturing parentheses.
    my $hgrepos = join('|', qw!(?:releases/)?comm-[\w.]+ 
                               (?:releases/)?mozilla-[\w.]+
                               (?:releases/)?mobile-[\w.]+
                               tracemonkey
                               tamarin-[\w.]+
                               camino!);

    push (@$regexes, {
        match => qr/\b(($hgrepos)\s+changeset:?\s+(?:\d+:)?([0-9a-fA-F]{12}))\b/,
        replace => \&_link_hg
    });
}

# Purpose: make it always possible to file bugs in certain groups.
sub bug_check_groups {
    my ($self, $args) = @_;
    my $group_names = $args->{'group_names'};
    my $add_groups = $args->{'add_groups'};
   
    $group_names = ref $group_names 
                   ? $group_names 
                   : [ map { trim($_) } split(',', $group_names) ];

    foreach my $name (@$group_names) {
        if ($always_fileable_group{$name}) {
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

sub _remo_form_payment {
    my ($vars) = @_;
    my $input = Bugzilla->input_params;

    my $user = Bugzilla->login(LOGIN_REQUIRED);

    if ($input->{'action'} eq 'commit') {
        my $template = Bugzilla->template;
        my $cgi      = Bugzilla->cgi;
        my $dbh      = Bugzilla->dbh;

        my $bug_id = $input->{'bug_id'};
        detaint_natural($bug_id);
        my $bug = Bugzilla::Bug->check($bug_id);

        # Detect if the user already used the same form to submit again
        my $token = trim($input->{'token'});
        if ($token) {
            my ($creator_id, $date, $old_attach_id) = Bugzilla::Token::GetTokenData($token);
            if (!$creator_id 
                || $creator_id != $user->id 
                || $old_attach_id !~ "^remo_form_payment:")
            {
                # The token is invalid.
                ThrowUserError('token_does_not_exist');
            }

            $old_attach_id =~ s/^remo_form_payment://;
            if ($old_attach_id) {
                ThrowUserError('remo_payment_cancel_dupe', 
                               { bugid => $bug_id, attachid => $old_attach_id });
            }
        }

        # Make sure the user can attach to this bug
        if (!$bug->user->{'canedit'}) {
            ThrowUserError("remo_payment_bug_edit_denied", 
                           { bug_id => $bug->id });
        }

        # Make sure the bug is under the correct product/component
        if ($bug->product ne 'Mozilla Reps' 
            || $bug->component ne 'Budget Requests') 
        {
            ThrowUserError('remo_payment_invalid_product');    
        }

        my ($timestamp) = $dbh->selectrow_array("SELECT NOW()");

        $dbh->bz_start_transaction;
    
        # Create the comment to be added based on the form fields from rep-payment-form
        my $comment;
        $template->process("pages/comment-remo-form-payment.txt.tmpl", $vars, \$comment)
            || ThrowTemplateError($template->error());
        $bug->add_comment($comment, { isprivate => 0 });

        # Attach expense report
        # FIXME: Would be nice to be able to have the above prefilled comment and
        # the following attachments all show up under a single comment. But the longdescs
        # table can only handle one attach_id per comment currently. At least only one
        # email is sent the way it is done below.
        my $attachment;
        if (defined $cgi->upload('expenseform')) {
            # Determine content-type
            my $content_type = $cgi->uploadInfo($cgi->param('expenseform'))->{'Content-Type'};
 
            $attachment = Bugzilla::Attachment->create(
                { bug           => $bug, 
                  creation_ts   => $timestamp, 
                  data          => $cgi->upload('expenseform'), 
                  description   => 'Expense Form', 
                  filename      => scalar $cgi->upload('expenseform'), 
                  ispatch       => 0, 
                  isprivate     => 0, 
                  isurl         => 0, 
                  mimetype      => $content_type, 
                  store_in_file => 0, 
            });

            # Insert comment for attachment
            $bug->add_comment('', { isprivate  => 0, 
                                    type       => CMT_ATTACHMENT_CREATED, 
                                    extra_data => $attachment->id });
        }

        # Attach receipts file
        if (defined $cgi->upload("receipts")) {
            # Determine content-type
            my $content_type = $cgi->uploadInfo($cgi->param("receipts"))->{'Content-Type'};

            $attachment = Bugzilla::Attachment->create(
                { bug           => $bug, 
                  creation_ts   => $timestamp, 
                  data          => $cgi->upload('receipts'), 
                  description   => "Receipts", 
                  filename      => scalar $cgi->upload("receipts"), 
                  ispatch       => 0, 
                  isprivate     => 0, 
                  isurl         => 0, 
                  mimetype      => $content_type, 
                  store_in_file => 0, 
            });

            # Insert comment for attachment
            $bug->add_comment('', { isprivate  => 0, 
                                    type       => CMT_ATTACHMENT_CREATED, 
                                    extra_data => $attachment->id });
        }

        $bug->update($timestamp);

        if ($token) {
            trick_taint($token);
            $dbh->do('UPDATE tokens SET eventdata = ? WHERE token = ?', undef,
                     ("remo_form_payment:" . $attachment->id, $token));
        }

        $dbh->bz_commit_transaction;
    
        # Define the variables and functions that will be passed to the UI template.
        $vars->{'attachment'} = $attachment;
        $vars->{'bugs'} = [ new Bugzilla::Bug($bug_id) ];
        $vars->{'header_done'} = 1;
        $vars->{'contenttypemethod'} = 'autodetect';
 
        my $recipients = { 'changer' => $user };
        $vars->{'sent_bugmail'} = Bugzilla::BugMail::Send($bug_id, $recipients);
        
        print $cgi->header();
        # Generate and return the UI (HTML page) from the appropriate template.
        $template->process("attachment/created.html.tmpl", $vars)
            || ThrowTemplateError($template->error()); 
        exit;
    }
    else {
        $vars->{'token'} = issue_session_token('remo_form_payment:');
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
    push @message, 'Please run the following on tm-bugs01-master01:';
    push @message, "  GRANT SELECT ON `bugs`.`$name` TO 'metrics'\@'10.2.70.20_';";
    push @message, "  GRANT SELECT ($name) ON `bugs`.`bugs` TO 'metrics'\@'10.2.70.20_';";
    push @message, '';
    MessageToMTA(join("\n", @message));
}

sub webservice {
    my ($self,  $args) = @_;

    my $dispatch = $args->{dispatch};
    $dispatch->{BMO} = "Bugzilla::Extension::BMO::WebService";
}

__PACKAGE__->NAME;
