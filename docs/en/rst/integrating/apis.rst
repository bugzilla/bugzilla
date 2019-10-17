.. _api-list:

APIs
####

Bugzilla has a number of APIs that you can call in your code to extract
information from and put information into Bugzilla. Some are deprecated and
will soon be removed. Which one to use? Short answer: the
:ref:`REST WebService API v1 <apis>`
should be used for all new integrations, but keep an eye out for version 2,
coming soon.

The APIs currently available are as follows:

Ad-Hoc APIs
===========

Various pages on Bugzilla are available in machine-parsable formats as well
as HTML. For example, bugs can be downloaded as XML, and buglists as CSV.
CSV is useful for spreadsheet import. There should be links on the HTML page
to alternate data formats where they are available.

REST
====

Bugzilla has a :ref:`REST API <apis>` which is the currently-recommended API
for integrating with Bugzilla. The current REST API is version 1. It is stable,
and so will not be changed in a backwardly-incompatible way.

**This is the currently-recommended API for new development.**

Endpoint: :file:`/rest`
