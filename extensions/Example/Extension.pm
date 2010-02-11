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

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Group;
use Bugzilla::User;
use Bugzilla::Util qw(diff_arrays html_quote);

# This is extensions/Example/lib/Util.pm. I can load this here in my
# Extension.pm only because I have a Config.pm.
use Bugzilla::Extension::Example::Util;

use Data::Dumper;

# See bugmail_relationships.
use constant REL_EXAMPLE => -127;

our $VERSION = '1.0';

sub attachment_process_data {
    my ($self, $args) = @_;
    my $type     = $args->{attributes}->{mimetype};
    my $filename = $args->{attributes}->{filename};

    # Make sure images have the correct extension.
    # Uncomment the two lines below to make this check effective.
    if ($type =~ /^image\/(\w+)$/) {
        my $format = $1;
        if ($filename =~ /^(.+)(:?\.[^\.]+)$/) {
            my $name = $1;
            #$args->{attributes}->{filename} = "${name}.$format";
        }
        else {
            # The file has no extension. We append it.
            #$args->{attributes}->{filename} .= ".$format";
        }
    }
}

sub auth_login_methods {
    my ($self, $args) = @_;
    my $modules = $args->{modules};
    if (exists $modules->{Example}) {
        $modules->{Example} = 'Bugzilla/Extension/Example/Auth/Login.pm';
    }
}

sub auth_verify_methods {
    my ($self, $args) = @_;
    my $modules = $args->{modules};
    if (exists $modules->{Example}) {
        $modules->{Example} = 'Bugzilla/Extension/Example/Auth/Verify.pm';
    }
}

sub bug_columns {
    my ($self, $args) = @_;
    my $columns = $args->{'columns'};
    push (@$columns, "delta_ts AS example")
}

sub bug_end_of_create {
    my ($self, $args) = @_;

    # This code doesn't actually *do* anything, it's just here to show you
    # how to use this hook.
    my $bug = $args->{'bug'};
    my $timestamp = $args->{'timestamp'};
    
    my $bug_id = $bug->id;
    # Uncomment this line to see a line in your webserver's error log whenever
    # you file a bug.
    # warn "Bug $bug_id has been filed!";
}

sub bug_end_of_create_validators {
    my ($self, $args) = @_;
    
    # This code doesn't actually *do* anything, it's just here to show you
    # how to use this hook.
    my $bug_params = $args->{'params'};
    
    # Uncomment this line below to see a line in your webserver's error log
    # containing all validated bug field values every time you file a bug.
    # warn Dumper($bug_params);
    
    # This would remove all ccs from the bug, preventing ANY ccs from being
    # added on bug creation.
    # $bug_params->{cc} = [];
}

sub bug_end_of_update {
    my ($self, $args) = @_;
    
    # This code doesn't actually *do* anything, it's just here to show you
    # how to use this hook.
    my ($bug, $timestamp, $changes) = @$args{qw(bug timestamp changes)};
    
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
    my ($self, $args) = @_;

    my $fields = $args->{'fields'};
    push (@$fields, "example")
}

sub bug_format_comment {
    my ($self, $args) = @_;
    
    # This replaces every occurrence of the word "foo" with the word
    # "bar"
    
    my $regexes = $args->{'regexes'};
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
    my $args = shift;
    # $match is the first parentheses match in the $bar_match regex 
    # in bug-format_comment.pl. We get up to 10 regex matches as 
    # arguments to this function.
    my $match = $args->{matches}->[0];
    # Remember, you have to HTML-escape any data that you are returning!
    $match = html_quote($match);
    return qq{<a href="http://example.com/">$match</a>};
};

sub buglist_columns {
    my ($self, $args) = @_;
    
    my $columns = $args->{'columns'};
    $columns->{'example'} = { 'name' => 'bugs.delta_ts' , 'title' => 'Example' };
}

sub bugmail_recipients {
    my ($self, $args) = @_;
    my $recipients = $args->{recipients};
    my $bug = $args->{bug};

    my $user = 
        new Bugzilla::User({ name => Bugzilla->params->{'maintainer'} });

    if ($bug->id == 1) {
        # Uncomment the line below to add the maintainer to the recipients
        # list of every bugmail from bug 1 as though that the maintainer
        # were on the CC list.
        #$recipients->{$user->id}->{+REL_CC} = 1;

        # And this line adds the maintainer as though he had the "REL_EXAMPLE"
        # relationship from the bugmail_relationships hook below.
        #$recipients->{$user->id}->{+REL_EXAMPLE} = 1;
    }
}

sub bugmail_relationships {
    my ($self, $args) = @_;
    my $relationships = $args->{relationships};
    $relationships->{+REL_EXAMPLE} = 'Example';
}

sub colchange_columns {
    my ($self, $args) = @_;
    
    my $columns = $args->{'columns'};
    push (@$columns, "example")
}

sub config {
    my ($self, $args) = @_;

    my $config = $args->{config};
    $config->{Example} = "Bugzilla::Extension::Example::Config";
}

sub config_add_panels {
    my ($self, $args) = @_;
    
    my $modules = $args->{panel_modules};
    $modules->{Example} = "Bugzilla::Extension::Example::Config";
}

sub config_modify_panels {
    my ($self, $args) = @_;
    
    my $panels = $args->{panels};
    
    # Add the "Example" auth methods.
    my $auth_params = $panels->{'auth'}->{params};
    my ($info_class)   = grep($_->{name} eq 'user_info_class', @$auth_params);
    my ($verify_class) = grep($_->{name} eq 'user_verify_class', @$auth_params);
    
    push(@{ $info_class->{choices} },   'CGI,Example');
    push(@{ $verify_class->{choices} }, 'Example');
}

sub flag_end_of_update {
    my ($self, $args) = @_;
    
    # This code doesn't actually *do* anything, it's just here to show you
    # how to use this hook.
    my $flag_params = $args;
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

sub group_before_delete {
    my ($self, $args) = @_;
    # This code doesn't actually *do* anything, it's just here to show you
    # how to use this hook.

    my $group = $args->{'group'};
    my $group_id = $group->id;
    # Uncomment this line to see a line in your webserver's error log whenever
    # you file a bug.
    # warn "Group $group_id is about to be deleted!";
}

sub group_end_of_create {
    my ($self, $args) = @_;
    # This code doesn't actually *do* anything, it's just here to show you
    # how to use this hook.
    my $group = $args->{'group'};

    my $group_id = $group->id;
    # Uncomment this line to see a line in your webserver's error log whenever
    # you create a new group.
    #warn "Group $group_id has been created!";
}

sub group_end_of_update {
    my ($self, $args) = @_;
    # This code doesn't actually *do* anything, it's just here to show you
    # how to use this hook.

    my ($group, $changes) = @$args{qw(group changes)};

    foreach my $field (keys %$changes) {
        my $used_to_be = $changes->{$field}->[0];
        my $now_it_is  = $changes->{$field}->[1];
    }

    my $group_id = $group->id;
    my $num_changes = scalar keys %$changes;
    my $result = 
        "There were $num_changes changes to fields on group $group_id.";
    # Uncomment this line to see $result in your webserver's error log whenever
    # you update a group.
    #warn $result;
}

sub install_before_final_checks {
    my ($self, $args) = @_;
    print "Install-before_final_checks hook\n" unless $args->{silent};
}

sub mailer_before_send {
    my ($self, $args) = @_;
    
    my $email = $args->{email};
    # If you add a header to an email, it's best to start it with
    # 'X-Bugzilla-<Extension>' so that you don't conflict with
    # other extensions.
    $email->header_set('X-Bugzilla-Example-Header', 'Example');
}

sub object_before_create {
    my ($self, $args) = @_;
    
    my $class = $args->{'class'};
    my $object_params = $args->{'params'};
    
    # Note that this is a made-up class, for this example.
    if ($class->isa('Bugzilla::ExampleObject')) {
        warn "About to create an ExampleObject!";
        warn "Got the following parameters: " 
             . join(', ', keys(%$object_params));
    }
}

sub object_before_set {
    my ($self, $args) = @_;
    
    my ($object, $field, $value) = @$args{qw(object field value)};
    
    # Note that this is a made-up class, for this example.
    if ($object->isa('Bugzilla::ExampleObject')) {
        warn "The field $field is changing from " . $object->{$field} 
             . " to $value!";
    }
}

sub object_columns {
    my ($self, $args) = @_;
    my ($class, $columns) = @$args{qw(class columns)};

    if ($class->isa('Bugzilla::ExampleObject')) {
        push(@$columns, 'example');
    }
}

sub object_end_of_create_validators {
    my ($self, $args) = @_;
    
    my $class = $args->{'class'};
    my $object_params = $args->{'params'};
    
    # Note that this is a made-up class, for this example.
    if ($class->isa('Bugzilla::ExampleObject')) {
        # Always set example_field to 1, even if the validators said otherwise.
        $object_params->{example_field} = 1;
    }
    
}

sub object_end_of_set_all {
    my ($self, $args) = @_;
    
    my $object = $args->{'class'};
    my $object_params = $args->{'params'};
    
    # Note that this is a made-up class, for this example.
    if ($object->isa('Bugzilla::ExampleObject')) {
        if ($object_params->{example_field} == 1) {
            $object->{example_field} = 1;
        }
    }
    
}

sub object_end_of_update {
    my ($self, $args) = @_;
    
    my ($object, $old_object, $changes) = 
        @$args{qw(object old_object changes)};
    
    # Note that this is a made-up class, for this example.
    if ($object->isa('Bugzilla::ExampleObject')) {
        if (defined $changes->{'name'}) {
            my ($old, $new) = @{ $changes->{'name'} };
            print "The name field changed from $old to $new!";
        }
    }
}

sub object_update_columns {
    my ($self, $args) = @_;
    my ($object, $columns) = @$args{qw(object columns)};

    if ($object->isa('Bugzilla::ExampleObject')) {
        push(@$columns, 'example');
    }
}

sub object_validators {
    my ($self, $args) = @_;
    my ($class, $validators) = @$args{qw(class validators)};

    if ($class->isa('Bugzilla::Bug')) {
        # This is an example of adding a new validator.
        # See the _check_example subroutine below.
        $validators->{example} = \&_check_example;

        # This is an example of overriding an existing validator.
        # See the check_short_desc validator below.
        my $original = $validators->{short_desc};
        $validators->{short_desc} = sub { _check_short_desc($original, @_) };
    }
}

sub _check_example {
    my ($invocant, $value, $field) = @_;
    warn "I was called to validate the value of $field.";
    warn "The value of $field that I was passed in is: $value";

    # Make the value always be 1.
    my $fixed_value = 1;
    return $fixed_value;
}

sub _check_short_desc {
    my $original = shift;
    my $invocant = shift;
    my $value = $invocant->$original(@_);
    if ($value !~ /example/i) {
        # Uncomment this line to make Bugzilla throw an error every time
        # you try to file a bug or update a bug without the word "example"
        # in the summary.
        #ThrowUserError('example_short_desc_invalid');
    }
    return $value;
}

sub page_before_template {
    my ($self, $args) = @_;
    
    my ($vars, $page) = @$args{qw(vars page_id)};
    
    # You can see this hook in action by loading page.cgi?id=example.html
    if ($page eq 'example.html') {
        $vars->{cgi_variables} = { Bugzilla->cgi->Vars };
    }
}

sub product_confirm_delete {
    my ($self, $args) = @_;
    
    my $vars = $args->{vars};
    $vars->{'example'} = 1;
}


sub product_end_of_create {
    my ($self, $args) = @_;

    my $product = $args->{product};

    # For this example, any lines of code that actually make changes to your
    # database have been commented out.

    # This section will take a group that exists in your installation
    # (possible called test_group) and automatically makes the new
    # product hidden to only members of the group. Just remove
    # the restriction if you want the new product to be public.

    my $example_group = new Bugzilla::Group({ name => 'example_group' });

    if ($example_group) {
        $product->set_group_controls($example_group, 
                { entry          => 1,
                  membercontrol  => CONTROLMAPMANDATORY,
                  othercontrol   => CONTROLMAPMANDATORY });
#        $product->update();
    }

    # This section will automatically add a default component
    # to the new product called 'No Component'.

    my $default_assignee = new Bugzilla::User(
        { name => Bugzilla->params->{maintainer} });

    if ($default_assignee) {
#        Bugzilla::Component->create(
#            { name             => 'No Component',
#              product          => $product,
#              description      => 'Select this component if one does not ' . 
#                                  'exist in the current list of components',
#              initialowner     => $default_assignee });
    }
}

sub sanitycheck_check {
    my ($self, $args) = @_;
    
    my $dbh = Bugzilla->dbh;
    my $sth;
    
    my $status = $args->{'status'};
    
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
    my ($self, $args) = @_;
    
    my $cgi = Bugzilla->cgi;
    my $dbh = Bugzilla->dbh;
    
    my $status = $args->{'status'};
    
    if ($cgi->param('example_repair_au_user')) {
        $status->('example_repair_au_user_start');
    
        #$dbh->do("UPDATE profiles
        #             SET login_name = CONCAT(login_name, '.au')
        #           WHERE login_name NOT LIKE '%.au'");
    
        $status->('example_repair_au_user_end');
    }
}

sub template_before_create {
    my ($self, $args) = @_;
    
    my $config = $args->{'config'};
    # This will be accessible as "example_global_variable" in every
    # template in Bugzilla. See Bugzilla/Template.pm's create() function
    # for more things that you can set.
    $config->{VARIABLES}->{example_global_variable} = sub { return 'value' };
}

sub template_before_process {
    my ($self, $args) = @_;
    
    my ($vars, $file, $context) = @$args{qw(vars file context)};

    if ($file eq 'bug/edit.html.tmpl') {
        $vars->{'viewing_the_bug_form'} = 1;
    }
}

sub webservice {
    my ($self, $args) = @_;

    my $dispatch = $args->{dispatch};
    $dispatch->{Example} = "Bugzilla::Extension::Example::WebService";
}

sub webservice_error_codes {
    my ($self, $args) = @_;
    
    my $error_map = $args->{error_map};
    $error_map->{'example_my_error'} = 10001;
}

# This must be the last line of your extension.
__PACKAGE__->NAME;
