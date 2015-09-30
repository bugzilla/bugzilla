.. _localizing-documentation:

Localizing The Documentation
############################

The Bugzilla documentation uses `reStructured Text (reST) <http://docutils.sourceforge.net/rst.html>`_,
as extended by our documentation compilation tool, `Sphinx <http://sphinx-doc.org/>`_.

`The Sphinx documentation <http://sphinx-doc.org/latest/rest.html>`_
gives a good introduction to reST and the Sphinx-specific extensions. Reading
that one immediately-linked page should be enough to get started. Later, the
`inline markup section <http://sphinx-doc.org/latest/markup/inline.html>`_
is worth a read.

As with the template files, the ``.rst`` files should be localized using an UTF8 compliant editor.

Spacing, blank lines and indentation are very important in reStructured Text, so be sure to follow exactly
the pattern of the English, otherwise your localized version will not look the same as the English one.

Though I recommend that you read the documents stated above, here are a few rules:

.. raw:: html

  <ul>
    <li>In <code>index.rst</code> files, never localize what is under the <code>.. toctree::</code> directive: these are file names.</li>
    <li>Never localize a term surrounded with a double dot and two colons. For instance: <code><mark>.. warning::</mark> <span class="green">This is a warning.</span></code>. This
    will be automatically localized if necessary at compilation time. You can localize what is located after, in green in this example.</li>
    <li>Exception: do not localize what is located after the directive <code>.. highlight:: console</code>. The word console here is for formatting purpose.</li>
    <li>Do not localize a term surrounded with two colons or with the signs lesser than and greater than:
    <code>:<mark>ref</mark>:`<span class="green">Démarrage rapide</span>&lt;<mark>quick-start</mark>&gt;`</code>. "ref" is a reserved word and "quick-start" is a file name. In the following syntax example, do not localize "using"
    as it is also a file name: <code>:<mark>ref</mark>:`<mark>using</mark>`</code></li>
  </ul>
