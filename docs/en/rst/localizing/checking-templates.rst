.. _checking-templates:

Checking Templates
##################

Checking Syntax
---------------

This step is important because if you have some wrong syntax in your template, this will break the user interface.

You can see the checking scripts in the ``t/`` subdirectory in your Bugzilla root directory.

To check the localized templates, you would only need to run these three ones:

* t/004template.t
* t/008filter.t
* t/009bugwords.t

So run e.g.:

:command:`prove -Q t/004template.t`

If your templates are valid, you should see a result like this:

.. raw:: html

  <pre>
  t/004template.t .. ok         
  <span class="green">All tests successful.</span>
  Files=1, Tests=1236,  5 wallclock secs ( 0.11 usr  0.00 sys +  4.70 cusr  0.05 csys =  4.86 CPU)
  Result: PASS
  </pre>

If something went wrong, you will see something like this:

.. raw:: html

  <pre>
  #   Failed test 'template/fr/default/index.html.tmpl has bad syntax --ERROR'
  #   at t/004template.t line 106.
  # Looks like you failed 1 test of 1236.
  
  Test Summary Report
  -------------------
  <mark>t/004template.t (Wstat: 256 Tests: 1236 Failed: 1)
    Failed test:  671
    Non-zero exit status: 1</mark>
  Files=1, Tests=1236,  4 wallclock secs ( 0.09 usr  0.01 sys +  4.74 cusr  0.04 csys =  4.88 CPU)
  Result: FAIL
  </pre>

where you would hopefully see the faulty template and the line number where the error occurred.

Then, fix the error and run the scripts again.

Viewing In Bugzilla
-------------------

Once your templates have good syntax, you will want to use them in Bugzilla.

Run:

:command:`./checksetup.pl`

to compile the templates and clear the language cache. Bugzilla will then
have a language chooser in the top right corner. By default, it uses the
``Accept-Language`` HTTP header to decide which version to serve you, but you can
override that by choosing a version explicitly. This is then remembered
in a cookie.

Choose the language you have localized in, if it's not already chosen for
you, and then view every page in Bugzilla to test your templates :-) This
may take some time...
