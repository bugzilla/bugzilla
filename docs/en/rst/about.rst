

.. _about:

================
About This Guide
================

.. _introduction:

Introduction
############

This is the documentation for version |version| of Bugzilla, a
bug-tracking system from mozilla.org.
Bugzilla is an enterprise-class piece of software
that tracks millions of bugs and issues for hundreds of
organizations around the world.

The most current version of this document can always be found on the
`Bugzilla
Documentation Page <http://www.bugzilla.org/docs/>`_.

.. _copyright:

Copyright Information
#####################

This document is copyright (c) 2000-2012 by the various
Bugzilla contributors who wrote it.

    Permission is granted to copy, distribute and/or modify this
    document under the terms of the GNU Free Documentation
    License, Version 1.1 or any later version published by the
    Free Software Foundation; with no Invariant Sections, no
    Front-Cover Texts, and with no Back-Cover Texts. A copy of
    the license is included in :ref:`gfdl`.

If you have any questions regarding this document, its
copyright, or publishing this document in non-electronic form,
please contact the Bugzilla Team.

.. _disclaimer:

Disclaimer
##########

No liability for the contents of this document can be accepted.
Follow the instructions herein at your own risk.
This document may contain errors
and inaccuracies that may damage your system, cause your partner
to leave you, your boss to fire you, your cats to
pee on your furniture and clothing, and global thermonuclear
war. Proceed with caution.

Naming of particular products or brands should not be seen as
endorsements, with the exception of the term "GNU/Linux". We
wholeheartedly endorse the use of GNU/Linux; it is an extremely
versatile, stable,
and robust operating system that offers an ideal operating
environment for Bugzilla.

Although the Bugzilla development team has taken great care to
ensure that all exploitable bugs have been fixed, security holes surely
exist in any piece of code. Great care should be taken both in
the installation and usage of this software. The Bugzilla development
team members assume no liability for your use of Bugzilla. You have
the source code, and are responsible for auditing it yourself to ensure
your security needs are met.

.. COMMENT: Section 2: New Versions

.. _newversions:

New Versions
############

This is version |version| of The Bugzilla Guide. It is so named
to match the current version of Bugzilla.

.. todo:: BZ-DEVEL This version of the guide, like its associated Bugzilla version, is a
   development version.

The latest version of this guide can always be found at `<http://www.bugzilla.org/docs/>`_. However, you should read
the version which came with the Bugzilla release you are using.

In addition, there are Bugzilla template localization projects in
`several languages <http://www.bugzilla.org/download/#localizations>`_.
They may have translated documentation available. If you would like to
volunteer to translate the Guide into additional languages, please visit the
`Bugzilla L10n team <https://wiki.mozilla.org/Bugzilla:L10n>`_
page.

.. _credits:

Credits
#######

The people listed below have made enormous contributions to the
creation of this Guide, through their writing, dedicated hacking efforts,
numerous e-mail and IRC support sessions, and overall excellent
contribution to the Bugzilla community:

.. COMMENT: TODO: This is evil... there has to be a valid way to get this look

Matthew P. Barnson mbarnson@sisna.com
    for the Herculean task of pulling together the Bugzilla Guide
    and shepherding it to 2.14.

Terry Weissman terry@mozilla.org
    for initially writing Bugzilla and creating the README upon
    which the UNIX installation documentation is largely based.

Tara Hernandez tara@tequilarists.org
    for keeping Bugzilla development going strong after Terry left
    mozilla.org and for running landfill.

Dave Lawrence dkl@redhat.com
    for providing insight into the key differences between Red
    Hat's customized Bugzilla.

Dawn Endico endico@mozilla.org
    for being a hacker extraordinaire and putting up with Matthew's
    incessant questions and arguments on irc.mozilla.org in #mozwebtools

Jacob Steenhagen jake@bugzilla.org
    for taking over documentation during the 2.17 development
    period.

Dave Miller justdave@bugzilla.org
    for taking over as project lead when Tara stepped down and
    continually pushing for the documentation to be the best it can be.

Thanks also go to the following people for significant contributions
to this documentation:
Kevin Brannen, Vlad Dascalu, Ben FrantzDale, Eric Hanson, Zach Lipton, Gervase Markham, Andrew Pearson, Joe Robins, Spencer Smith, Ron Teitelbaum, Shane Travis, Martin Wulffeld.

Also, thanks are due to the members of the
`mozilla.support.bugzilla <news://news.mozilla.org/mozilla.support.bugzilla>`_
newsgroup (and its predecessor, netscape.public.mozilla.webtools).
Without your discussions, insight, suggestions, and patches,
this could never have happened.

.. _conventions:

Document Conventions
####################

This document uses the following conventions:

.. warning:: This is a warning - something you should be aware of.

.. note:: This is just a note, for your information.

A filename or a path to a filename is displayed like this:
:file:`/path/to/filename.ext`

A command to type in the shell is displayed like this:
:command:`command --arguments`

bash$ represents a normal user's prompt under bash shell

bash# represents a root user's prompt under bash shell

A word which is in the glossary will appear like this:
Bugzilla

A sample of code is illustrated like this:

::

    First Line of Code
    Second Line of Code
    ...

This documentation is maintained in reStructured Text format.
Changes are best submitted as diffs, attached
to a bug filed in the `Bugzilla Documentation <https://bugzilla.mozilla.org/enter_bug.cgi?product=Bugzilla;component=Documentation>`_
component.

