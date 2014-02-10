.. highlight:: console

.. _install-perlmodules-manual:

===================================
Manual Installation of Perl Modules
===================================

.. _modules-manual-instructions:

Instructions
############

If you need to install Perl modules manually, here's how it's done.
Download the module using the link given in the next section, and then
apply this magic incantation, as root:

::

    # tar -xzvf <module>.tar.gz
    # cd <module>
    # perl Makefile.PL
    # make
    # make test
    # make install

.. note:: In order to compile source code under Windows you will need to obtain
   a 'make' utility.  The :command:`nmake` utility provided with
   Microsoft Visual C++ may be used.  As an alternative, there is a
   utility called :command:`dmake` available from CPAN which is
   written entirely in Perl.
   As described in :ref:`modules-manual-download`, however, most
   packages already exist and are available from ActiveState or theory58S.
   We highly recommend that you install them using the ppm GUI available with
   ActiveState and to add the theory58S repository to your list of repositories.

.. _modules-manual-download:

Download Locations
##################

.. note:: Running Bugzilla on Windows requires the use of ActiveState
   Perl |min-perl-ver| or higher. Many modules already exist in the core
   distribution of ActiveState Perl. Additional modules can be downloaded
   from `<http://cpan.uwinnipeg.ca/PPMPackages/10xx/>`_
   if you use Perl |min-perl-ver|.

CGI:

* CPAN Download Page: `<http://search.cpan.org/dist/CGI.pm/>`_
* Documentation: `<http://perldoc.perl.org/CGI.html>`_

Data-Dumper:

* CPAN Download Page: `<http://search.cpan.org/dist/Data-Dumper/>`_
* Documentation: `<http://search.cpan.org/dist/Data-Dumper/Dumper.pm>`_

Date::Format (part of TimeDate):

* CPAN Download Page: `<http://search.cpan.org/dist/TimeDate/>`_
* Documentation: `<http://search.cpan.org/dist/TimeDate/lib/Date/Format.pm>`_

DBI:

* CPAN Download Page: `<http://search.cpan.org/dist/DBI/>`_
* Documentation: `<http://dbi.perl.org/docs/>`_

DBD::mysql:

* CPAN Download Page: `<http://search.cpan.org/dist/DBD-mysql/>`_
* Documentation: `<http://search.cpan.org/dist/DBD-mysql/lib/DBD/mysql.pm>`_

DBD::Pg:

* CPAN Download Page: `<http://search.cpan.org/dist/DBD-Pg/>`_
* Documentation: `<http://search.cpan.org/dist/DBD-Pg/Pg.pm>`_

Template-Toolkit:

* CPAN Download Page: `<http://search.cpan.org/dist/Template-Toolkit/>`_
* Documentation: `<http://www.template-toolkit.org/docs.html>`_

GD:

* CPAN Download Page: `<http://search.cpan.org/dist/GD/>`_
* Documentation: `<http://search.cpan.org/dist/GD/GD.pm>`_

Template::Plugin::GD:

* CPAN Download Page: `<http://search.cpan.org/dist/Template-GD/>`_
* Documentation: `<http://www.template-toolkit.org/docs/aqua/Modules/index.html>`_

MIME::Parser (part of MIME-tools):

* CPAN Download Page: `<http://search.cpan.org/dist/MIME-tools/>`_
* Documentation: `<http://search.cpan.org/dist/MIME-tools/lib/MIME/Parser.pm>`_

.. _modules-manual-optional:

Optional Modules
################

Chart::Lines:

* CPAN Download Page: `<http://search.cpan.org/dist/Chart/>`_
* Documentation: `<http://search.cpan.org/dist/Chart/Chart.pod>`_

GD::Graph:

* CPAN Download Page: `<http://search.cpan.org/dist/GDGraph/>`_
* Documentation: `<http://search.cpan.org/dist/GDGraph/Graph.pm>`_

GD::Text::Align (part of GD::Text::Util):

* CPAN Download Page: `<http://search.cpan.org/dist/GDTextUtil/>`_
* Documentation: `<http://search.cpan.org/dist/GDTextUtil/Text/Align.pm>`_

XML::Twig:

* CPAN Download Page: `<http://search.cpan.org/dist/XML-Twig/>`_
* Documentation: `<http://standards.ieee.org/resources/spasystem/twig/twig_stable.html>`_

PatchReader:

* CPAN Download Page: `<http://search.cpan.org/author/JKEISER/PatchReader/>`_
* Documentation: `<http://www.johnkeiser.com/mozilla/Patch_Viewer.html>`_
