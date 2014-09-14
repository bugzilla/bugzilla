Download Code from Git
======================

Download a copy of your current version of Bugzilla from the git repository
into a separate directory alongside your existing Bugzilla installation
(which we will assume is in a directory called :file:`bugzilla`).

You will need a copy of the git program. All Linux installations have it;
search your package manager for "git". On Windows or Mac OS X, you can
`download the official build <http://www.git-scm.com/downloads>`_.

Once git is installed, run these commands to pull a copy of Bugzilla:

:command:`git clone https://git.mozilla.org/bugzilla/bugzilla bugzilla-new`

:command:`cd bugzilla-new`

:command:`git checkout $VERSION`

Replace $VERSION with the two-digit version number of your current Bugzilla, e.g.
4.2. These command will automatically change your version to the latest
point release of version $VERSION.

