.. _get-the-source:

Get The Source Files
####################

First, you need to install Bugzilla and get it running. See the
:ref:`installing`.

The installed software should have the following tree structure:

.. raw:: html

  <pre>
  |-- Bugzilla
  |-- contrib
  |-- docs
  |   `-- <mark>en</mark>
  |-- extensions
  |   |-- BmpConvert
  |   |-- Example
  |   |   |-- docs
  |   |   |   `-- <mark>en</mark>
  |   |   |-- lib
  |   |   `-- template
  |   |       `-- <mark>en</mark>
  |   |-- MoreBugUrl
  |   |   |-- lib
  |   |   `-- template
  |   |       `-- <mark>en</mark>
  |   `-- Voting
  |       |-- template
  |       |   `-- <mark>en</mark>
  |-- images
  |-- js
  |-- template
  |   `-- <mark>en</mark>
  | ...
  </pre>

All localizable content is in directories called ``en``, for English. You
are going to create a parallel set of directories named after your locale
code, and build your localized version in there.

So next, you need to work out your locale code. You
can find the locale code matching your language on
`this wiki page <https://wiki.mozilla.org/L10n:Simple_locale_names>`_.
For instance, ``fr`` is used for French and ``ca`` for Catalan. You can
also use a four-letter locale code, e.g. ``pt-BR`` for Brazilian Portuguese or
``zh-CN`` for Chinese (Simplified). In the rest of this guide, your locale
code will be represented by ``ab-CD``.

Then, run:

:command:`contrib/new-locale.pl ab-CD`

This will make a copy of all the English documentation for you, in parallel
directories to the "en" directories, named after your locale code.
