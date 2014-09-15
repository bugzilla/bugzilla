.. _voting:

Voting
######

To enable the Voting extension, you must remove the :file:`disabled`
file from the directory :file:`extensions/Voting/`, and run
:file:`checksetup.pl`.

Voting allows users to be given a pot of votes which they can allocate
to bugs, to indicate that they'd like them fixed.
This allows developers to gauge
user need for a particular enhancement or bugfix. By allowing bugs with
a certain number of votes to automatically move from "UNCONFIRMED" to
"CONFIRMED", users of the bug system can help high-priority bugs garner
attention so they don't sit for a long time awaiting triage.

To modify Voting settings, navigate to the "Edit product" screen for the
Product you wish to modify. The following settings are available:

*Maximum votes per person:*
    Setting this field to "0" disables voting.

*Maximum votes a person can put on a single bug:*
    It should probably be some number lower than the
    "Maximum votes per person". Don't set this field to "0" if
    "Maximum votes per person" is non-zero; that doesn't make
    any sense.

*Number of votes a bug in this product needs to automatically get out of the UNCONFIRMED state:*
    Setting this field to "0" disables the automatic move of
    bugs from UNCONFIRMED to CONFIRMED.

Once you have adjusted the values to your preference, click "Update".
