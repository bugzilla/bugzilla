.. _apis:

APIs
####

Bugzilla has a number of APIs that you can call in your code to extract
information from and put information into Bugzilla. Some are deprecated and
will soon be removed. Which one to use? Short answer: the
`REST API
<http://www.bugzilla.org/docs/tip/en/html/api/Bugzilla/WebService/Server/REST.html>`_
should be used for all new integrations, but keep an eye out for version 2,
coming soon.

The APIs currently available are as follows:

Ad-Hoc APIs
===========

Various pages on Bugzilla are available in machine-parseable formats as well
as HTML. For example, bugs can be downloaded as XML, and buglists as CSV.
While the team attempts not to break these ad-hoc APIs, they should not be
used for new code.

XML-RPC
=======

Bugzilla has an `XML-RPC API
<http://www.bugzilla.org/docs/tip/en/html/api/Bugzilla/WebService/Server/XMLRPC.html>`_.
This will receive no further updates and will be removed in a future version
of Bugzilla.

JSON-RPC
========

Bugzilla has a `JSON-RPC API
<http://www.bugzilla.org/docs/tip/en/html/api/Bugzilla/WebService/Server/JSONRPC.html>`_.
This will receive no further updates and will be removed in a future version
of Bugzilla.

REST
====

Bugzilla has a `REST API
<http://www.bugzilla.org/docs/tip/en/html/api/Bugzilla/WebService/Server/REST.html>`_
which is the currently-recommended API for integrating with Bugzilla. The
current REST API is version 1. It is stable, and so will not be changed in a
backwardly-incompatible way. **This is the currently-recommended API for
new development.**

BzAPI/BzAPI-Compatible REST
===========================

The first ever REST API for Bugzilla was implemented using an external proxy
called `BzAPI <https://wiki.mozilla.org/Bugzilla:BzAPI>`_. This became popular
enough that a BzAPI-compatible shim on top of the (native) REST API has been
written, to allow code which used the BzAPI API to take advantage of the
speed improvements of direct integration without needing to be rewritten.
The shim is an extension which you would need to install in your Bugzilla.

Neither BzAPI nor this BzAPI-compatible API shim will receive any further
updates, and they should not be used for new code.

REST v2
=======

The future of Bugzilla's APIs is version 2 of the REST API, which will take
the best of the current REST API and the BzAPI API. It is still under
development.
