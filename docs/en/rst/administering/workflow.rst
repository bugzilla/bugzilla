.. _workflow:

Workflow
########

The bug status workflow is no longer hardcoded but can be freely customized
from the web interface. Only one bug status cannot be renamed nor deleted,
UNCONFIRMED, but the workflow involving it is free. The configuration
page displays all existing bug statuses twice, first on the left for bug
statuses we come from and on the top for bug statuses we move to.
If the checkbox is checked, then the transition between the two bug statuses
is legal, else it's forbidden independently of your privileges. The bug status
used for the "duplicate_or_move_bug_status" parameter must be part of the
workflow as that is the bug status which will be used when duplicating or
moving a bug, so it must be available from each bug status.

When the workflow is set, the "View Current Triggers" link below the table
lets you set which transitions require a comment from the user.
