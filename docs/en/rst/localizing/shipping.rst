.. _localizing-templates:

Shipping
########

Once you have localized everything, you will want to ship it. The best way
of doing this is still to create a tarball of all your files, which the
Bugzilla administrator will untar in their ``$BUGZILLA_HOME`` directory.

This command will find all of the files you've localized and put them into
an appropriate tarball. Don't forget to replace both instances of ``ab-CD``:

:command:`find -name "ab-CD" -print0 -o -path "./data" -prune | tar -cjvf ../bugzilla-ab-CD.tar.bz2 --null -T -`
