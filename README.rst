============================================
Bugzilla: A Free and Open-Source Bug Tracker
============================================

Bugzilla is free and open source web-based bug-tracking software that is
developed by an active group of volunteers in the Mozilla community, and
used by thousands of projects and companies around the world.

----
|homepage| |documentation| |irc| |docker_pulls| |license|
----

Usage
=====

Bugzilla requires Perl 5.14 (or newer) and tools to compile and install perl
modules, including make(1) and a C compiler.

For Developers
--------------

Debian/Ubuntu users: you probably need to run the following:

.. code-block:: bash

    sudo apt-get install git perl cpanminus build-essential libexpat-dev libssl-dev

CentOS / Fedora users:

.. code-block:: bash

     sudo yum group install -y "Development tools"
     sudo yum install -y perl-App-cpanminus

After that, you should run the following command from a git clone of this repository:

.. code-block:: bash

    perl checksetup.pl --cpanm

At this point ``localconfig`` can be edited to specify database connection parameters. If SQLite is acceptable,
no edits are required.

The checksetup.pl script should be run again to set up the database schema.

.. code-block:: bash

    perl checksetup.pl

It will ask for some details, such as login name and password.

Finally, a webserver can be started by the following:

.. code-block:: bash

    perl app.psgi

Navigate to http://localhost:5000/ and login with the username and password provided earlier to checksetup.
Remember to set the urlbase on http://localhost:5000/editparams.cgi. "http://localhost:5000" will probably suffice.

For Operations
--------------

For a production setup, see the `installation guide <http://bugzilla.readthedocs.io/en/latest/installing/index.html>`__

Links and Other Resources
=========================

-  Join irc.mozilla.org #bugzilla (or use the `Bugzilla IRC Gateway <http://landfill.bugzilla.org/irc/>`__)
-  Ask questions on the `Support <https://www.mozilla.org/en-US/about/forums/#support-bugzilla>`__
   mailing list
- `Report Bugs <https://bugzilla.mozilla.org/enter_bug.cgi?product=Bugzilla>`__
   (Please do not file test bugs in this installation of Bugzilla.)
-  Contributing a patch? Join us from 11:00 to 12:00 US/Eastern every Thursday in Bugzilla IRC Channel for `Contributor Office Hours <http://goo.gl/2Wz8x6>`__.
-  If you haven't already, subscribe to the `Development <https://www.mozilla.org/en-US/about/forums/#dev-apps-bugzilla>`__
   mailing list.

License
-------

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.

This Source Code Form is "Incompatible With Secondary Licenses", as
defined by the Mozilla Public License, v. 2.0.

However, this is all only relevant to you if you want to modify the code and
redistribute it. As with all open source software, there are no restrictions
on running it, or on modifying it for your own purposes.

.. |homepage| image:: https://img.shields.io/badge/home-bugzilla.org-blue.svg
   :target: http://bugzilla.org
.. |docker_pulls| image:: https://img.shields.io/docker/pulls/dklawren/docker-bugzilla.svg
   :target: https://hub.docker.com/r/dklawren/docker-bugzilla/
   :alt: docker pulls
.. |documentation| image:: https://readthedocs.org/projects/bugzilla/badge/?version=latest
   :target: http://bugzilla.readthedocs.io/en/latest/
   :alt: Documentation
.. |irc| image:: https://img.shields.io/badge/chat-%23bugzilla-blue.svg
   :target: http://landfill.bugzilla.org/irc/
   :alt: Chat with us on IRC
.. |license| image:: https://img.shields.io/github/license/bugzilla/bugzilla.svg?maxAge=2592000
   :target: #license
   :alt: License
