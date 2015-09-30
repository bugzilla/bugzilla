.. _files-to-be-localized:

Files To Be Localized
#####################

There are several different types of files to be localized:

Templates
---------

\*.tmpl files
   These files are `Template Toolkit <http://template-toolkit.org/>`_
   templates, which are used to generate the HTML pages which make up
   Bugzilla's user interface. There are templates in both
   the :file:`extensions` and :file:`template` subdirectories.

strings.txt.pl:
   This is a Perl file. It contains strings which are used when displaying
   information or error messages during Bugzilla's setup, when the templating
   infrastructure is not available. It is located in the
   :file:`template/en/default/setup` directory.

Documentation
-------------

\*.rst files:
   These files are `ReStructuredText <http://docutils.sourceforge.net/docs/ref/rst/restructuredtext.html>`_,
   and contain Bugzilla's documentation. There are reST files in the
   :file:`docs` and :file:`extensions/Example/docs/en/rst` subdirectories.

bzLifecycle.xml:
   This is an XML source file for the diagramming tool
   `Dia <https://wiki.gnome.org/Apps/Dia>`_. It is used to generate the flow
   diagram showing the different states in a bug lifecycle, which is part of
   the documentation.
