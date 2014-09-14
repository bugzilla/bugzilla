.. _sanity-check:

Sanity Check
############

Over time it is possible for the Bugzilla database to become corrupt
or to have anomalies.
This could happen through normal usage of Bugzilla, manual database
administration outside of the Bugzilla user interface, or from some
other unexpected event. Bugzilla includes a "Sanity Check" script that
can perform several basic database checks, and repair certain problems or
inconsistencies.

To run the "Sanity Check" script, log in as an Administrator and click the
"Sanity Check" link in the admin page. Any problems that are found will be
displayed in red letters. If the script is capable of fixing a problem,
it will present a link to initiate the fix. If the script cannot
fix the problem it will require manual database administration or recovery.

The "Sanity Check" script can also be run from the command line via the perl
script :file:`sanitycheck.pl`. The script can also be run as
a :command:`cron` job. Results will be delivered by email.

The "Sanity Check" script should be run on a regular basis as a matter of
best practice.

.. warning:: The "Sanity Check" script is no substitute for a competent database
   administrator. It is only designed to check and repair basic database
   problems.


