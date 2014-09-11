.. _upgrading-overview:

Overview
########

You can upgrade Bugzilla from any version to any later version in one go -
there is no need to pass through intermediate versions unless you are changing
the method by which you obtain the code along the way.
 
Bugzilla uses the Git version control system to store its code. A modern Bugzilla
installation consists of a checkout of a stable version of the code from our
Git repository. This makes upgrading much easier. If this is
true of you, see :ref:`upgrading-with-git`.

Before Git, we used to use Bazaar and, before that, CVS. If your installation
of Bugzilla consists of a checkout from one of those two systems, you need to
upgrade in three steps:

1. upgrade to the latest point release of your current Bugzilla version;
2. move to Git while staying on exactly the same release;
3. upgrade to the latest Bugzilla using the instructions for :ref:`upgrading-with-git`.

See :ref:`upgrading-from-bazaar` or :ref:`upgrading-from-cvs` as appropriate.

Some Bugzillas were installed simply by downloading a copy of the code as
an archive file ("tarball"). However, recent tarballs have included source
code management system information, so you may be able to use the Git, Bzr
or CVS instructions.

If you aren't sure which of these categories you fall into, to find out which
version control system your copy of Bugzilla recognizes, look for the
following subdirectories in your root Bugzilla directory:

* :file:`.git`: you installed using Git - follow :ref:`upgrading-with-git`
* :file:`.bzr`: you installed using Bazaar - follow :ref:`upgrading-from-bazaar`
* :file:`CVS`: you installed using CVS - follow :ref:`upgrading-from-cvs`
* none of the above: you installed using an old tarball - follow :ref:`upgrading-with-a-tarball`

It is also possible, particularly if your server machine does not have and
cannot be configured to have access to the public internet, to upgrade using
a tarball. See :ref:`upgrading-with-a-tarball`.

Before performing any upgrade, it's a good idea to back up both your Bugzilla
directory and your database. XXXlink to backup info in Maintenance
