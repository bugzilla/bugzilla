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
# The Initial Developer of the Original Code is Netscape Communications
# Corporation. Portions created by Netscape are
# Copyright (C) 1998 Netscape Communications Corporation. All
# Rights Reserved.
#
# Contributor(s): Zach Lipton <zach@zachlipton.com>
#                 Max Kanat-Alexander <mkanat@bugzilla.org>

package Bugzilla::Hook;
use strict;

sub process {
    my ($name, $args) = @_;

    _entering($name);

    foreach my $extension (@{ Bugzilla->extensions }) {
        if ($extension->can($name)) {
            $extension->$name($args);
        }
    }

    _leaving($name);
}

sub in {
    my $hook_name = shift;
    my $currently_in = Bugzilla->request_cache->{hook_stack}->[-1] || '';
    return $hook_name eq $currently_in ? 1 : 0;
}

sub _entering {
    my ($hook_name) = @_;
    my $hook_stack = Bugzilla->request_cache->{hook_stack} ||= [];
    push(@$hook_stack, $hook_name);
}

sub _leaving {
    pop @{ Bugzilla->request_cache->{hook_stack} };
}

1;

__END__

=head1 NAME

Bugzilla::Hook - Extendable extension hooks for Bugzilla code

=head1 SYNOPSIS

 use Bugzilla::Hook;

 Bugzilla::Hook::process("hookname", { arg => $value, arg2 => $value2 });

=head1 DESCRIPTION

Bugzilla allows extension modules to drop in and add routines at 
arbitrary points in Bugzilla code. These points are referred to as
hooks. When a piece of standard Bugzilla code wants to allow an extension
to perform additional functions, it uses Bugzilla::Hook's L</process>
subroutine to invoke any extension code if installed. 

The implementation of extensions is described in L<Bugzilla::Extension>.

There is sample code for every hook in the Example extension, located in
F<extensions/Example/Extension.pm>.

=head2 How Hooks Work

When a hook named C<HOOK_NAME> is run, Bugzilla looks through all
enabled L<extensions|Bugzilla::Extension> for extensions that implement
a subroutined named C<HOOK_NAME>.

See L<Bugzilla::Extension> for more details about how an extension
can run code during a hook.

=head1 SUBROUTINES

=over

=item C<process>

=over

=item B<Description>

Invoke any code hooks with a matching name from any installed extensions.

See C<customization.xml> in the Bugzilla Guide for more information on
Bugzilla's extension mechanism.

=item B<Params>

=over

=item C<$name> - The name of the hook to invoke.

=item C<$args> - A hashref. The named args to pass to the hook. 
They will be accessible to the hook via L<Bugzilla/hook_args>.

=back

=item B<Returns> (nothing)

=back

=back

=head1 HOOKS

This describes what hooks exist in Bugzilla currently. They are mostly
in alphabetical order, but some related hooks are near each other instead
of being alphabetical.

=head2 attachment_process_data

This happens at the very beginning process of the attachment creation.
You can edit the attachment content itself as well as all attributes
of the attachment, before they are validated and inserted into the DB.

Params:

=over

=item C<data> - A reference pointing either to the content of the file
being uploaded or pointing to the filehandle associated with the file.

=item C<attributes> - A hashref whose keys are the same as
L<Bugzilla::Attachment/create>. The data it contains hasn't been checked yet.

=back

=head2 auth_login_methods

This allows you to add new login types to Bugzilla.
(See L<Bugzilla::Auth::Login>.)

Params:

=over

=item C<modules>

This is a hash--a mapping from login-type "names" to the actual module on
disk. The keys will be all the values that were passed to 
L<Bugzilla::Auth/login> for the C<Login> parameter. The values are the
actual path to the module on disk. (For example, if the key is C<DB>, the
value is F<Bugzilla/Auth/Login/DB.pm>.)

For your extension, the path will start with 
F<extensions/yourextension/lib/>. (See the code in the example extension.)

If your login type is in the hash as a key, you should set that key to the
right path to your module. That module's C<new> method will be called,
probably with empty parameters. If your login type is I<not> in the hash,
you should not set it.

You will be prevented from adding new keys to the hash, so make sure your
key is in there before you modify it. (In other words, you can't add in
login methods that weren't passed to L<Bugzilla::Auth/login>.)

=back

=head2 auth_verify_methods

This works just like L</auth_login_methods> except it's for
login verification methods (See L<Bugzilla::Auth::Verify>.) It also
takes a C<modules> parameter, just like L</auth_login_methods>.

=head2 bug_columns

This allows you to add new fields that will show up in every L<Bugzilla::Bug>
object. Note that you will also need to use the L</bug_fields> hook in
conjunction with this hook to make this work.

Params:

=over

=item C<columns> - An arrayref containing an array of column names. Push
your column name(s) onto the array.

=back

=head2 bug_end_of_create

This happens at the end of L<Bugzilla::Bug/create>, after all other changes are
made to the database. This occurs inside a database transaction.

Params:

=over

=item C<bug> - The changed bug object, with all fields set to their updated
values.

=item C<timestamp> - The timestamp used for all updates in this transaction.

=back

=head2 bug_end_of_create_validators

This happens during L<Bugzilla::Bug/create>, after all parameters have
been validated, but before anything has been inserted into the database.

Params:

=over

=item C<params>

A hashref. The validated parameters passed to C<create>.

=back

=head2 bug_end_of_update

This happens at the end of L<Bugzilla::Bug/update>, after all other changes are
made to the database. This generally occurs inside a database transaction.

Params:

=over

=item C<bug> - The changed bug object, with all fields set to their updated
values.

=item C<timestamp> - The timestamp used for all updates in this transaction.

=item C<changes> - The hash of changed fields. 
C<$changes-E<gt>{field} = [old, new]>

=back

=head2 bug_fields

Allows the addition of database fields from the bugs table to the standard
list of allowable fields in a L<Bugzilla::Bug> object, so that
you can call the field as a method.

Note: You should add here the names of any fields you added in L</bug_columns>.

Params:

=over

=item C<columns> - A arrayref containing an array of column names. Push
your column name(s) onto the array.

=back

=head2 bug_format_comment

Allows you to do custom parsing on comments before they are displayed. You do
this by returning two regular expressions: one that matches the section you
want to replace, and then another that says what you want to replace that
match with.

The matching and replacement will be run with the C</g> switch on the regex.

Params:

=over

=item C<regexes>

An arrayref of hashrefs.

You should push a hashref containing two keys (C<match> and C<replace>)
in to this array. C<match> is the regular expression that matches the
text you want to replace, C<replace> is what you want to replace that
text with. (This gets passed into a regular expression like 
C<s/$match/$replace/>.)

Instead of specifying a regular expression for C<replace> you can also
return a coderef (a reference to a subroutine). If you want to use
backreferences (using C<$1>, C<$2>, etc. in your C<replace>), you have to use
this method--it won't work if you specify C<$1>, C<$2> in a regular expression
for C<replace>. Your subroutine will get a hashref as its only argument. This
hashref contains a single key, C<matches>. C<matches> is an arrayref that
contains C<$1>, C<$2>, C<$3>, etc. in order, up to C<$10>. Your subroutine
should return what you want to replace the full C<match> with. (See the code
example for this hook if you want to see how this actually all works in code.
It's simpler than it sounds.)

B<You are responsible for HTML-escaping your returned data.> Failing to
do so could open a security hole in Bugzilla.

=item C<text>

A B<reference> to the exact text that you are parsing.

Generally you should not modify this yourself. Instead you should be 
returning regular expressions using the C<regexes> array.

The text has already been word-wrapped, but has not been parsed in any way
otherwise. (So, for example, it is not HTML-escaped. You get "&", not 
"&amp;".)

=item C<bug>

The L<Bugzilla::Bug> object that this comment is on. Sometimes this is
C<undef>, meaning that we are parsing text that is not on a bug.

=item C<comment>

A hashref representing the comment you are about to parse, including
all of the fields that comments contain when they are returned by
by L<Bugzilla::Bug/longdescs>.

Sometimes this is C<undef>, meaning that we are parsing text that is
not a bug comment (but could still be some other part of a bug, like
the summary line).

=back

=head2 buglist_columns

This happens in buglist.cgi after the standard columns have been defined and
right before the display column determination.  It gives you the opportunity
to add additional display columns.

Params:

=over

=item C<columns> - A hashref, where the keys are unique string identifiers
for the column being defined and the values are hashrefs with the
following fields:

=over

=item C<name> - The name of the column in the database.

=item C<title> - The title of the column as displayed to users.

=back

The definition is structured as:

 $columns->{$id} = { name => $name, title => $title };

=back

=head2 bugmail_recipients

This allows you to modify the list of users who are going to be receiving
a particular bugmail. It also allows you to specify why they are receiving
the bugmail.

Users' bugmail preferences will be applied to any users that you add
to the list. (So, for example, if you add somebody as though they were
a CC on the bug, and their preferences state that they don't get email
when they are a CC, they won't get email.)

This hook is called before watchers or globalwatchers are added to the
recipient list.

Params:

=over

=item C<bug>

The L<Bugzilla::Bug> that bugmail is being sent about.

=item C<recipients>

This is a hashref. The keys are numeric user ids from the C<profiles>
table in the database, for each user who should be receiving this bugmail.
The values are hashrefs. The keys in I<these> hashrefs correspond to
the "relationship" that the user has to the bug they're being emailed
about, and the value should always be C<1>. The "relationships"
are described by the various C<REL_> constants in L<Bugzilla::Constants>.

Here's an example of adding userid C<123> to the recipient list
as though he were on the CC list:

 $recipients->{123}->{+REL_CC} = 1

(We use C<+> in front of C<REL_CC> so that Perl interprets it as a constant
instead of as a string.)

=back


=head2 colchange_columns

This happens in F<colchange.cgi> right after the list of possible display
columns have been defined and gives you the opportunity to add additional
display columns to the list of selectable columns.

Params:

=over

=item C<columns> - An arrayref containing an array of column IDs.  Any IDs
added by this hook must have been defined in the the L</buglist_columns> hook.

=back

=head2 config_add_panels

If you want to add new panels to the Parameters administrative interface,
this is where you do it.

Params:

=over

=item C<panel_modules>

A hashref, where the keys are the "name" of the module and the value
is the Perl module containing that config module. For example, if
the name is C<Auth>, the value would be C<Bugzilla::Config::Auth>.

For your extension, the Perl module name must start with 
C<extensions::yourextension::lib>. (See the code in the example
extension.)

=back

=head2 config_modify_panels

This is how you modify already-existing panels in the Parameters
administrative interface. For example, if you wanted to add a new
Auth method (modifying Bugzilla::Config::Auth) this is how you'd
do it.

Params:

=over

=item C<panels>

A hashref, where the keys are lower-case panel "names" (like C<auth>, 
C<admin>, etc.) and the values are hashrefs. The hashref contains a
single key, C<params>. C<params> is an arrayref--the return value from
C<get_param_list> for that module. You can modify C<params> and
your changes will be reflected in the interface.

Adding new keys to C<panels> will have no effect. You should use
L</config_add_panels> if you want to add new panels.

=back

=head2 enter_bug_entrydefaultvars

B<DEPRECATED> - Use L</template_before_process> instead.

This happens right before the template is loaded on enter_bug.cgi.

Params:

=over

=item C<vars> - A hashref. The variables that will be passed into the template.

=back

=head2 flag_end_of_update

This happens at the end of L<Bugzilla::Flag/update_flags>, after all other changes
are made to the database and after emails are sent. It gives you a before/after
snapshot of flags so you can react to specific flag changes.
This generally occurs inside a database transaction.

Note that the interface to this hook is B<UNSTABLE> and it may change in the
future.

Params:

=over

=item C<object> - The changed bug or attachment object.

=item C<timestamp> - The timestamp used for all updates in this transaction.

=item C<old_flags> - The snapshot of flag summaries from before the change.

=item C<new_flags> - The snapshot of flag summaries after the change. Call
C<my ($removed, $added) = diff_arrays(old_flags, new_flags)> to get the list of
changed flags, and search for a specific condition like C<added eq 'review-'>.

=back

=head2 group_before_delete

This happens in L<Bugzilla::Group/remove_from_db>, after we've confirmed
that the group can be deleted, but before any rows have actually
been removed from the database. This occurs inside a database
transaction.

Params:

=over

=item C<group> - The L<Bugzilla::Group> being deleted.

=back

=head2 group_end_of_create

This happens at the end of L<Bugzilla::Group/create>, after all other
changes are made to the database. This occurs inside a database transaction.

Params:

=over

=item C<group> - The changed L<Bugzilla::Group> object, with all fields set
to their updated values.

=back

=head2 group_end_of_update

This happens at the end of L<Bugzilla::Group/update>, after all other 
changes are made to the database. This occurs inside a database transaction.

Params:

=over

=item C<group> - The changed L<Bugzilla::Group> object, with all fields set 
to their updated values.

=item C<changes> - The hash of changed fields. 
C<< $changes->{$field} = [$old, $new] >>

=back

=head2 install_before_final_checks

Allows execution of custom code before the final checks are done in 
checksetup.pl.

Params:

=over

=item C<silent>

A flag that indicates whether or not checksetup is running in silent mode.

=back

=head2 install_update_db

This happens at the very end of all the tables being updated
during an installation or upgrade. If you need to modify your custom
schema, do it here. No params are passed.

=head2 db_schema_abstract_schema

This allows you to add tables to Bugzilla. Note that we recommend that you 
prefix the names of your tables with some word, so that they don't conflict 
with any future Bugzilla tables.

If you wish to add new I<columns> to existing Bugzilla tables, do that
in L</install_update_db>.

Params:

=over

=item C<schema> - A hashref, in the format of 
L<Bugzilla::DB::Schema/ABSTRACT_SCHEMA>. Add new hash keys to make new table
definitions. F<checksetup.pl> will automatically add these tables to the
database when run.

=back

=head2 mailer_before_send

Called right before L<Bugzilla::Mailer> sends a message to the MTA.

Params:

=over

=item C<email> - The C<Email::MIME> object that's about to be sent.

=item C<mailer_args> - An arrayref that's passed as C<mailer_args> to
L<Email::Send/new>.

=back

=head2 object_before_create

This happens at the beginning of L<Bugzilla::Object/create>.

Params:

=over

=item C<class>

The name of the class that C<create> was called on. You can check this 
like C<< if ($class->isa('Some::Class')) >> in your code, to perform specific
tasks before C<create> for only certain classes.

=item C<params>

A hashref. The set of named parameters passed to C<create>.

=back

=head2 object_before_set

Called during L<Bugzilla::Object/set>, before any actual work is done.
You can use this to perform actions before a value is changed for
specific fields on certain types of objects.

Params:

=over

=item C<object>

The object that C<set> was called on. You will probably want to
do something like C<< if ($object->isa('Some::Class')) >> in your code to
limit your changes to only certain subclasses of Bugzilla::Object.

=item C<field>

The name of the field being updated in the object.

=item C<value> 

The value being set on the object.

=back

=head2 object_end_of_create_validators

Called at the end of L<Bugzilla::Object/run_create_validators>. You can
use this to run additional validation when creating an object.

If a subclass has overridden C<run_create_validators>, then this usually
happens I<before> the subclass does its custom validation.

Params:

=over

=item C<class>

The name of the class that C<create> was called on. You can check this 
like C<< if ($class->isa('Some::Class')) >> in your code, to perform specific
tasks for only certain classes.

=item C<params>

A hashref. The set of named parameters passed to C<create>, modified and
validated by the C<VALIDATORS> specified for the object.

=back


=head2 object_end_of_set

Called during L<Bugzilla::Object/set>, after all the code of the function
has completed (so the value has been validated and the field has been set
to the new value). You can use this to perform actions after a value is
changed for specific fields on certain types of objects.

The new value is not specifically passed to this hook because you can
get it as C<< $object->{$field} >>.

Params:

=over

=item C<object>

The object that C<set> was called on. You will probably want to
do something like C<< if ($object->isa('Some::Class')) >> in your code to
limit your changes to only certain subclasses of Bugzilla::Object.

=item C<field>

The name of the field that was updated in the object.

=back


=head2 object_end_of_set_all

This happens at the end of L<Bugzilla::Object/set_all>. This is a
good place to call custom set_ functions on objects, or to make changes
to an object before C<update()> is called.

Params:

=over

=item C<object>

The L<Bugzilla::Object> which is being updated. You will probably want to
do something like C<< if ($object->isa('Some::Class')) >> in your code to
limit your changes to only certain subclasses of Bugzilla::Object.

=item C<params>

A hashref. The set of named parameters passed to C<set_all>.

=back

=head2 object_end_of_update

Called during L<Bugzilla::Object/update>, after changes are made
to the database, but while still inside a transaction.

Params:

=over

=item C<object>

The object that C<update> was called on. You will probably want to
do something like C<< if ($object->isa('Some::Class')) >> in your code to
limit your changes to only certain subclasses of Bugzilla::Object.

=item C<old_object>

The object as it was before it was updated.

=item C<changes>

The fields that have been changed, in the same format that
L<Bugzilla::Object/update> returns.

=back

=head2 page_before_template

This is a simple way to add your own pages to Bugzilla. This hooks C<page.cgi>,
which loads templates from F<template/en/default/pages>. For example,
C<page.cgi?id=fields.html> loads F<template/en/default/pages/fields.html.tmpl>.

This hook is called right before the template is loaded, so that you can
pass your own variables to your own pages.

Params:

=over

=item C<page_id>

This is the name of the page being loaded, like C<fields.html>.

Note that if two extensions use the same name, it is uncertain which will
override the others, so you should be careful with how you name your pages.

=item C<vars>

This is a hashref--put variables into here if you want them passed to
your template.

=back

=head2 product_confirm_delete

B<DEPRECATED> - Use L</template_before_process> instead.

Called before displaying the confirmation message when deleting a product.

Params:

=over

=item C<vars> - The template vars hashref.

=back

=head2 sanitycheck_check

This hook allows for extra sanity checks to be added, for use by
F<sanitycheck.cgi>.

Params:

=over

=item C<status> - a CODEREF that allows status messages to be displayed
to the user. (F<sanitycheck.cgi>'s C<Status>)

=back

=head2 product_end_of_create

Called right after a new product has been created, allowing additional
changes to be made to the new product's attributes. This occurs inside of
a database transaction, so if the hook throws an error all previous
changes will be rolled back including the creation of the new product.

Params:

=over

=item C<product> - The new L<Bugzilla::Product> object that was just created.

=back

=head2 sanitycheck_repair

This hook allows for extra sanity check repairs to be made, for use by
F<sanitycheck.cgi>.

Params:

=over

=item C<status> - a CODEREF that allows status messages to be displayed
to the user. (F<sanitycheck.cgi>'s C<Status>)

=back

=head2 template_before_create

This hook allows you to modify the configuration of L<Bugzilla::Template>
objects before they are created. For example, you could add a new
global template variable this way.

Params:

=over

=item C<config>

A hashref--the configuration that will be passed to L<Template/new>.
See L<http://template-toolkit.org/docs/modules/Template.html#section_CONFIGURATION_SUMMARY>
for information on how this configuration variable is structured (or just
look at the code for C<create> in L<Bugzilla::Template>.)

=back

=head2 template_before_process

This hook is called any time Bugzilla processes a template file, including
calls to C<< $template->process >>, C<PROCESS> statements in templates,
and C<INCLUDE> statements in templates. It is not called when templates
process a C<BLOCK>, only when they process a file.

This hook allows you to define additional variables that will be available to
the template being processed, or to modify the variables that are currently
in the template. It works exactly as though you inserted code to modify
template variables at the top of a template.

You probably want to restrict this hook to operating only if a certain 
file is being processed (which is why you get a C<file> argument
below). Otherwise, modifying the C<vars> argument will affect every single
template in Bugzilla.

B<Note:> This hook is not called if you are already in this hook.
(That is, it won't call itself recursively.) This prevents infinite
recursion in situations where this hook needs to process a template
(such as if this hook throws an error).

Params:

=over

=item C<vars>

This is the entire set of variables that the current template can see.
Technically, this is a L<Template::Stash> object, but you can just
use it like a hashref if you want.

=item C<file>

The name of the template file being processed. This is relative to the
main template directory for the language (i.e. for
F<template/en/default/bug/show.html.tmpl>, this variable will contain
C<bug/show.html.tmpl>).

=item C<context>

A L<Template::Context> object. Usually you will not have to use this, but
if you need information about the template itself (other than just its
name), you can get it from here.

=back

=head2 webservice

This hook allows you to add your own modules to the WebService. (See
L<Bugzilla::WebService>.)

Params:

=over

=item C<dispatch>

A hashref that you can specify the names of your modules and what Perl
module handles the functions for that module. (This is actually sent to 
L<SOAP::Lite/dispatch_with>. You can see how that's used in F<xmlrpc.cgi>.)

The Perl module name must start with C<extensions::yourextension::lib::>
(replace C<yourextension> with the name of your extension). The C<package>
declaration inside that module must also start with 
C<extensions::yourextension::lib::> in that module's code.

Example:

  $dispatch->{Example} = "extensions::example::lib::Example";

And then you'd have a module F<extensions/example/lib/Example.pm>

It's recommended that all the keys you put in C<dispatch> start with the
name of your extension, so that you don't conflict with the standard Bugzilla
WebService functions (and so that you also don't conflict with other
plugins).

=back

=head2 webservice_error_codes

If your webservice extension throws custom errors, you can set numeric
codes for those errors here.

Extensions should use error codes above 10000, unless they are re-using
an already-existing error code.

Params:

=over

=item C<error_map>

A hash that maps the names of errors (like C<invalid_param>) to numbers.
See L<Bugzilla::WebService::Constants/WS_ERROR_CODE> for an example.

=back

=head1 SEE ALSO

L<Bugzilla::Extension>
