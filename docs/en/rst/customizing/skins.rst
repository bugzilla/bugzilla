.. _skins:

Skins
=====

Bugzilla supports skins. It ships with two - "Classic" and "Dusk". You can
find some more listed
`on the wiki <https://wiki.mozilla.org/Bugzilla:Addons#Skins>`_, and there
are a couple more which are part of
`bugzilla.mozilla.org <http://git.mozilla.org/?p=webtools/bmo/bugzilla.git>`_.
However, in each
case you may need to check that the skin supports the version of Bugzilla
you have. 

To create a new custom skin, you have two choices:

- Make a single CSS file, and put it in the
  :file:`skins/contrib` directory.

- Make a directory that contains all the same CSS file
  names as :file:`skins/standard/`, and put
  your directory in :file:`skins/contrib/`.

After you put the file or the directory there, make sure to run checksetup.pl
so that it can reset the file permissions correctly.

After you have installed the new skin, it will show up as an option in the
user's General Preferences. If you would like to force a particular skin on all
users, just select it in the Default Preferences and then uncheck "Enabled" on
the preference.
