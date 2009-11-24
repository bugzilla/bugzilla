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
# The Initial Developer of the Original Code is Everything Solved, Inc.
# Portions created by the Initial Developers are Copyright (C) 2009 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Max Kanat-Alexander <mkanat@bugzilla.org>
#   Frédéric Buclin <LpSolit@gmail.com>

package Bugzilla::Extension::Example;
use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::Util qw(diff_arrays html_quote);

# This is extensions/Example/lib/Util.pm. I can load this here in my
# Extension.pm only because I have a Config.pm.
use Bugzilla::Extension::Example::Util;

use Data::Dumper;

our $VERSION = '1.0';

sub attachment_process_data {
    my ($self, $params) = @_;
    my $type     = $params->{attributes}->{mimetype};
    my $filename = $params->{attributes}->{filename};

    # Make sure images have the correct extension.
    # Uncomment the two lines below to make this check effective.
    if ($type =~ /^image\/(\w+)$/) {
        my $format = $1;
        if ($filename =~ /^(.+)(:?\.[^\.]+)$/) {
            my $name = $1;
            #$params->{attributes}->{filename} = "${name}.$format";
        }
        else {
            # The file has no extension. We append it.
            #$params->{attributes}->{filename} .= ".$format";
        }
    }
}

sub auth_login_methods {
    my ($self, $params) = @_;
    my $modules = $params->{modules};
    if (exists $modules->{Example}) {
        $modules->{Example} = 'Bugzilla/Extension/Example/Auth/Login.pm';
    }
}

sub auth_verify_methods {
    my ($self, $params) = @_;
    my $modules = $params->{modules};
    if (exists $modules->{Example}) {
        $modules->{Example} = 'Bugzilla/Extension/Example/Auth/Verify.pm';
    }
}

sub bug_columns {
    my ($self, $params) = @_;
    my $columns = $params->{'columns'};
    push (@$columns, "delta_ts AS example")
}

sub bug_end_of_create {
    my ($self, $params) = @_;

    # This code doesn't actually *do* anything, it's just here to show you
    # how to use this hook.
    my $bug = $params->{'bug'};
    my $timestamp = $params->{'timestamp'};
    
    my $bug_id = $bug->id;
    # Uncomment this line to see a line in your webserver's error log whenever
    # you file a bug.
    # warn "Bug $bug_id has been filed!";
}

sub bug_end_of_create_validators {
    my ($self, $params) = @_;
    
    # This code doesn't actually *do* anything, it's just here to show you
    # how to use this hook.
    my $bug_params = $params->{'params'};
    
    # Uncomment this line below to see a line in your webserver's error log
    # containing all validated bug field values every time you file a bug.
    # warn Dumper($bug_params);
    
    # This would remove all ccs from the bug, preventing ANY ccs from being
    # added on bug creation.
    # $bug_params->{cc} = [];
}

sub bug_end_of_update {
    my ($self, $params) = @_;
    
    # This code doesn't actually *do* anything, it's just here to show you
    # how to use this hook.
    my ($bug, $timestamp, $changes) = @$params{qw(bug timestamp changes)};
    
    foreach my $field (keys %$changes) {
        my $used_to_be = $changes->{$field}->[0];
        my $now_it_is  = $changes->{$field}->[1];
    }
    
    my $status_message;
    if (my $status_change = $changes->{'bug_status'}) {
        my $old_status = new Bugzilla::Status({ name => $status_change->[0] });
        my $new_status = new Bugzilla::Status({ name => $status_change->[1] });
        if ($new_status->is_open && !$old_status->is_open) {
            $status_message = "Bug re-opened!";
        }
        if (!$new_status->is_open && $old_status->is_open) {
            $status_message = "Bug closed!";
        }
    }
    
    my $bug_id = $bug->id;
    my $num_changes = scalar keys %$changes;
    my $result = "There were $num_changes changes to fields on bug $bug_id"
                 . " at $timestamp.";
    # Uncomment this line to see $result in your webserver's error log whenever
    # you update a bug.
    # warn $result;
}

sub bug_fields {
    my ($self, $params) = @_;

    my $fields = $params->{'fields'};
    push (@$fields, "example")
}

sub bug_format_comment {
    my ($self, $params) = @_;
    
    # This replaces every occurrence of the word "foo" with the word
    # "bar"
    
    my $regexes = $params->{'regexes'};
    push(@$regexes, { match => qr/\bfoo\b/, replace => 'bar' });
    
    # And this links every occurrence of the word "bar" to example.com,
    # but it won't affect "foo"s that have already been turned into "bar"
    # above (because each regex is run in order, and later regexes don't modify
    # earlier matches, due to some cleverness in Bugzilla's internals).
    #
    # For example, the phrase "foo bar" would become:
    # bar <a href="http://example.com/bar">bar</a>
    my $bar_match = qr/\b(bar)\b/;
    push(@$regexes, { match => $bar_match, replace => \&_replace_bar });
}

# Used by bug_format_comment--see its code for an explanation.
sub _replace_bar {
    my $params = shift;
    # $match is the first parentheses match in the $bar_match regex 
    # in bug-format_comment.pl. We get up to 10 regex matches as 
    # arguments to this function.
    my $match = $params->{matches}->[0];
    # Remember, you have to HTML-escape any data that you are returning!
    $match = html_quote($match);
    return qq{<a href="http://example.com/">$match</a>};
};

sub buglist_columns {
    my ($self, $params) = @_;
    
    my $columns = $params->{'columns'};
    $columns->{'example'} = { 'name' => 'bugs.delta_ts' , 'title' => 'Example' };
}

sub colchange_columns {
    my ($self, $params) = @_;
    
    my $columns = $params->{'columns'};
    push (@$columns, "example")
}

sub config {
    my ($self, $params) = @_;

    my $config = $params->{config};
    $config->{Example} = "Bugzilla::Extension::Example::Config";
}

sub config_add_panels {
    my ($self, $params) = @_;
    
    my $modules = $params->{panel_modules};
    $modules->{Example} = "Bugzilla::Extension::Example::Config";
}

sub config_modify_panels {
    my ($self, $params) = @_;
    
    my $panels = $params->{panels};
    
    # Add the "Example" auth methods.
    my $auth_params = $panels->{'auth'}->{params};
    my ($info_class)   = grep($_->{name} eq 'user_info_class', @$auth_params);
    my ($verify_class) = grep($_->{name} eq 'user_verify_class', @$auth_params);
    
    push(@{ $info_class->{choices} },   'CGI,Example');
    push(@{ $verify_class->{choices} }, 'Example');
}

sub flag_end_of_update {
    my ($self, $params) = @_;
    
    # This code doesn't actually *do* anything, it's just here to show you
    # how to use this hook.
    my $flag_params = $params;
    my ($object, $timestamp, $old_flags, $new_flags) =
        @$flag_params{qw(object timestamp old_flags new_flags)};
    my ($removed, $added) = diff_arrays($old_flags, $new_flags);
    my ($granted, $denied) = (0, 0);
    foreach my $new_flag (@$added) {
        $granted++ if $new_flag =~ /\+$/;
        $denied++ if $new_flag =~ /-$/;
    }
    my $bug_id = $object->isa('Bugzilla::Bug') ? $object->id 
                                               : $object->bug_id;
    my $result = "$granted flags were granted and $denied flags were denied"
                 . " on bug $bug_id at $timestamp.";
    # Uncomment this line to see $result in your webserver's error log whenever
    # you update flags.
    # warn $result;
}

sub install_before_final_checks {
    my ($self, $params) = @_;
    print "Install-before_final_checks hook\n" unless $params->{silent};
}

sub mailer_before_send {
    my ($self, $params) = @_;
    
    my $email = $params->{email};
    # If you add a header to an email, it's best to start it with
    # 'X-Bugzilla-<Extension>' so that you don't conflict with
    # other extensions.
    $email->header_set('X-Bugzilla-Example-Header', 'Example');
}

sub object_before_create {
    my ($self, $params) = @_;
    
    my $class = $params->{'class'};
    my $object_params = $params->{'params'};
    
    # Note that this is a made-up class, for this example.
    if ($class->isa('Bugzilla::ExampleObject')) {
        warn "About to create an ExampleObject!";
        warn "Got the following parameters: " 
             . join(', ', keys(%$object_params));
    }
}

sub object_before_set {
    my ($self, $params) = @_;
    
    my ($object, $field, $value) = @$params{qw(object field value)};
    
    # Note that this is a made-up class, for this example.
    if ($object->isa('Bugzilla::ExampleObject')) {
        warn "The field $field is changing from " . $object->{$field} 
             . " to $value!";
    }
}

sub object_end_of_create_validators {
    my ($self, $params) = @_;
    
    my $class = $params->{'class'};
    my $object_params = $params->{'params'};
    
    # Note that this is a made-up class, for this example.
    if ($class->isa('Bugzilla::ExampleObject')) {
        # Always set example_field to 1, even if the validators said otherwise.
        $object_params->{example_field} = 1;
    }
    
}

sub object_end_of_set_all {
    my ($self, $params) = @_;
    
    my $object = $params->{'class'};
    my $object_params = $params->{'params'};
    
    # Note that this is a made-up class, for this example.
    if ($object->isa('Bugzilla::ExampleObject')) {
        if ($object_params->{example_field} == 1) {
            $object->{example_field} = 1;
        }
    }
    
}

sub object_end_of_update {
    my ($self, $params) = @_;
    
    my ($object, $old_object, $changes) = 
        @$params{qw(object old_object changes)};
    
    # Note that this is a made-up class, for this example.
    if ($object->isa('Bugzilla::ExampleObject')) {
        if (defined $changes->{'name'}) {
            my ($old, $new) = @{ $changes->{'name'} };
            print "The name field changed from $old to $new!";
        }
    }
}

sub page_before_template {
    my ($self, $params) = @_;
    
    my ($vars, $page) = @$params{qw(vars page_id)};
    
    # You can see this hook in action by loading page.cgi?id=example.html
    if ($page eq 'example.html') {
        $vars->{cgi_variables} = { Bugzilla->cgi->Vars };
    }
}

sub product_confirm_delete {
    my ($self, $params) = @_;
    
    my $vars = $params->{vars};
    $vars->{'example'} = 1;
}

sub sanitycheck_check {
    my ($self, $params) = @_;
    
    my $dbh = Bugzilla->dbh;
    my $sth;
    
    my $status = $params->{'status'};
    
    # Check that all users are Australian
    $status->('example_check_au_user');
    
    $sth = $dbh->prepare("SELECT userid, login_name
                            FROM profiles
                           WHERE login_name NOT LIKE '%.au'");
    $sth->execute;
    
    my $seen_nonau = 0;
    while (my ($userid, $login, $numgroups) = $sth->fetchrow_array) {
        $status->('example_check_au_user_alert',
                  { userid => $userid, login => $login },
                  'alert');
        $seen_nonau = 1;
    }
    
    $status->('example_check_au_user_prompt') if $seen_nonau;
}

sub sanitycheck_repair {
    my ($self, $params) = @_;
    
    my $cgi = Bugzilla->cgi;
    my $dbh = Bugzilla->dbh;
    
    my $status = $params->{'status'};
    
    if ($cgi->param('example_repair_au_user')) {
        $status->('example_repair_au_user_start');
    
        #$dbh->do("UPDATE profiles
        #             SET login_name = CONCAT(login_name, '.au')
        #           WHERE login_name NOT LIKE '%.au'");
    
        $status->('example_repair_au_user_end');
    }
}

sub template_before_create {
    my ($self, $params) = @_;
    
    my $config = $params->{'config'};
    # This will be accessible as "example_global_variable" in every
    # template in Bugzilla. See Bugzilla/Template.pm's create() function
    # for more things that you can set.
    $config->{VARIABLES}->{example_global_variable} = sub { return 'value' };
}

sub template_before_process {
    my ($self, $params) = @_;
    
    my ($vars, $file, $template) = @$params{qw(vars file template)};
    
    $vars->{'example'} = 1;
    
    if ($file =~ m{^bug/show}) {
        $vars->{'showing_a_bug'} = 1;
    }
}

sub webservice {
    my ($self, $params) = @_;

    my $dispatch = $params->{dispatch};
    $dispatch->{Example} = "Bugzilla::Extension::Example::WebService";
}

sub webservice_error_codes {
    my ($self, $params) = @_;
    
    my $error_map = $params->{error_map};
    $error_map->{'example_my_error'} = 10001;
}

# This must be the last line of your extension.
__PACKAGE__->NAME;
