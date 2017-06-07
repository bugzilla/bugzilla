=========================
BMO: bugzilla.mozilla.org
=========================

BMO is Mozilla's highly customized version of Bugzilla.

If you are looking to run Bugzilla, you should see
https://github.com/bugzilla/bugzilla.

If you want to contribute to BMO, you can fork this repo and get a local copy
of BMO running in a few minutes.

Install Vagrant
===============

You will need to install the following software:

* Vagrant 1.9.1 or later

Doing this on OSX can be accomplished with homebrew:

.. code-block:: bash

    brew install vagrant

For Ubuntu 16.04, download the vagrant .dpkg directly from
https://vagrantup.com.  The one that ships with Ubuntu is too old.

Setup Vagrant VMs
=================

From your BMO checkout run the following command:

.. code-block:: bash

    vagrant up

Depending on the speed of your computer and your Internet connection, this
will take from a few minutes to much longer.

If this fails, please file a bug `using this link <https://bugzilla.mozilla.org/enter_bug.cgi?assigned_to=nobody%40mozilla.org&bug_file_loc=http%3A%2F%2F&bug_ignored=0&bug_severity=normal&bug_status=NEW&cf_fx_iteration=---&cf_fx_points=---&component=Developer%20Box&contenttypemethod=autodetect&contenttypeselection=text%2Fplain&defined_groups=1&flag_type-254=X&flag_type-4=X&flag_type-607=X&flag_type-791=X&flag_type-800=X&flag_type-803=X&form_name=enter_bug&maketemplate=Remember%20values%20as%20bookmarkable%20template&op_sys=Unspecified&priority=--&product=bugzilla.mozilla.org&rep_platform=Unspecified&target_milestone=---&version=Production>`__.

Otherwise, you should have a working BMO developer machine!

To test it, you'll want to add an entry to /etc/hosts for bmo-web.vm pointing
to 192.168.3.43.

After that, you should be able to visit http://bmo-web.vm/ from your browser.
You can login as vagrant@bmo-web.vm with the password "vagrant01!" (without
quotes).

Making Changes and Seeing them
==============================

After editing files in the bmo directory, you will need to run

.. code-block:: bash

    vagrant rsync && vagrant provision web

to see the changes applied to your vagrant VM.

Technical Details
=================

This Vagrant environment is a very complete but scaled-down version of
production BMO.  It uses roughly the same RPMs (from CentOS 6, versus RHEL 6
in production) and the same perl dependencies (via
https://github.com/mozilla-bteam/carton-bundles).

It includes a couple example products, some fake users, and some of BMO's
real groups. Email is disabled for all users; however, it is safe to enable
email as the box is configured to send all email to the 'vagrant' user on the
web vm.

Most of the cron jobs and the jobqueue daemon are running.  It is also
configured to use memcached.

The push connector is not currently configured, nor is the Pulse publisher.
