.. This file is included in multiple places, so can't have labels as they
   appear as duplicates.
   
The procedure to migrate to Git is as follows. The idea is to switch version
control systems without changing the version of Bugzilla you are using,
to minimise the risk of conflict or problems. Any major upgrade can then
happen as a separate step. 

Update Bugzilla To The Latest Point Release
===========================================

It is recommended that you switch to Git while using the latest
point release for your version, so if you aren't running that, you may
want to do a minor upgrade first.

.. todo:: Is this actually necessary? It adds several extra steps. What are we
          trying to avoid here? If we do have to do it, can we avoid them
          having to work out the latest point release manually? And do the
          bzr and CVS update commands take the full version number including
          the third digit, or do they just take major and minor? We need to
          make sure all commands operate on the same version number style,
          and that it's clearly explained.

First, you need to find what version of Bugzilla you are using. It should be
in the top right corner of the front page but, if not, open the file
:file:`Bugzilla/Constants.pm` in your Bugzilla directory and search for
:code:`BUGZILLA_VERSION`.

Then, you need to find out what the latest point release for that major
version of Bugzilla is. The
`Bugzilla download page <http://www.bugzilla.org/download/>`_
should tell you that for supported versions. For versions out of support, here
is a list of the final point releases:

* 3.6.13
* 3.4.14
* 3.2.10
* 3.0.11
* 2.22.7
* 2.20.7
* 2.18.6
* 2.16.11
* 2.14.5

If you are not currently running the latest point release, you should use the
following update command:

|updatecommand|

Where you replace $VERSION by the version number of the latest point release.
Then run checksetup to upgrade your database:

:command:`./checksetup.pl`

You should then test your Bugzilla carefully, or just use it for a day or two,
to make sure it's all still working fine.
