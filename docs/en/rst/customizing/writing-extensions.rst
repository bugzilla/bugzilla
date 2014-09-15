.. _writing-extensions:

Writing Extensions
##################

See the `Bugzilla Extension
documentation <../html/api/Bugzilla/Extension.html>`_ for the core
documentation on how to write an Extension. We also have some additional
tips and tricks here.

XXX These came from the wiki. Should they actually be integrated into the
POD, or should some of the POD come here, or something else?

Checking Syntax
===============

It's not immediately obvious how to check the syntax of your extension's
modules. Running checksetup.pl might do some of it, but the errors aren't
necessarily massively informative.

:command:`perl -Mlib=lib -MBugzilla -e 'BEGIN { Bugzilla->extensions; } use Bugzilla::Extension::ExtensionName::Class;'`

(run from ``$BUGZILLA_HOME``) will do the trick.

Adding New Fields To Bugs
=========================

To add new fields to a bug, you need to do the following:

* Add an ``install_update_db`` hook to add the fields by calling
  ``Bugzilla::Field->create`` (only if the field doesn't already exist).
  Here's what it might look like for a single field:

  .. code-block:: perl

    my $field = new Bugzilla::Field({ name => $name });
    return if $field;
 
    $field = Bugzilla::Field->create({
        name        => $name,
        description => $description,
        type        => $type,        # From list in Constants.pm
        enter_bug   => 0,
        buglist     => 0,
        custom      => 1,
    });

* Push the name of the field onto the relevant arrays in the ``bug_columns``
  and ``bug_fields`` hooks.

* If you want direct accessors, or other functions on the object, you need to
  add a BEGIN block to your Extension.pm:

  .. code-block:: perl

    BEGIN { 
       *Bugzilla::Bug::is_foopy = \&_bug_is_foopy; 
    }
 
    ...
 
    sub _bug_is_foopy {
        return $_[0]->{'is_foopy'};
    }

* You don't have to change ``Bugzilla/DB/Schema.pm``.

Adding New Fields To Other Things
=================================

If you are adding the new fields to an object other than a bug, you need to
go a bit lower-level. 

* In ``install_update_db``, use ``bz_add_column`` instead

* Push on the columns in ``object_columns`` and ``object_update_columns``
  instead of ``bug_columns``.

* Add validators for the values in ``object_validators``

The process for adding accessor functions is the same.

Adding Configuration Panels
===========================

As well as using the ``config_add_panels`` hook, you will need a template to
define the UI strings for the panel. See the templates in
:file:`template/en/default/admin/params` for examples, and put your own
template in :file:`template/en/default/admin/params` in your extension's
directory.

Adding User Preferences
=======================

To add a new user preference:

* Call ``add_setting('setting_name', ['some_option', 'another_option'],
  'some_option')`` in the ``install_before_final_checks`` hook. (The last
  parameter is the name of the option which should be the default.)

* Add descriptions for the identifiers for your setting and choices
  (setting_name, some_option etc.) to the hash defined in
  :file:`global/setting-descs.none.tmpl`. Do this in a hook:
  :file:`hook/global/setting-descs-settings.none.tmpl`. Your code can see the
  hash variable; just set more members in it.

* To change behaviour based on the setting, reference it in templates using
  ``[% user.settings.setting_name.value %]``. Reference it in code using
  ``$user->settings->{'setting_name'}->{'value'}``. The value will be one of
  the option tag names (e.g. some_option).
