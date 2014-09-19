.. _keywords:

Keywords
########

The administrator can define keywords which can be used to tag and
categorise bugs. For example, the keyword "regression" is commonly used.
A company might have a policy stating all regressions
must be fixed by the next release - this keyword can make tracking those
bugs much easier.

Keywords are global, rather than per-product. If the administrator changes
a keyword currently applied to any bugs, the keyword cache must be rebuilt
using the :ref:`sanity-check` script.

.. todo:: Does this mean changing the name of the keyword? Is it still true?

Currently keywords cannot be marked obsolete to prevent future usage.

Keywords can be created, edited or deleted by clicking the "Keywords"
link in the admin page. There are two fields for each keyword - the keyword
itself and a brief description.

