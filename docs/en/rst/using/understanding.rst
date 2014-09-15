.. _understanding:

Understanding a Bug
###################

The core of Bugzilla is the screen which displays a particular
bug. Note that the labels for most fields are hyperlinks;
clicking them will take you to context-sensitive help on that
particular field. Fields marked * may not be present on every
installation of Bugzilla.

*Summary:*
   A one-sentence summary of the problem, displayed in the header next to
   the bug number.

*Status (and Resolution):*
   These define exactly what state the bug is in - from not even
   being confirmed as a bug, through to being fixed and the fix
   confirmed by Quality Assurance. The different possible values for
   Status and Resolution on your installation should be documented in the
   context-sensitive help for those items.

*Alias:*
   A unique short text name for the bug, which can be used instead of the
   bug number.

*Product and Component*:
   Bugs are divided up by Product and Component, with a Product
   having one or more Components in it. 

*Version:*
   The "Version" field is usually used for versions of a product which
   have been released, and is set to indicate which versions of a
   Component have the particular problem the bug report is
   about.

*Hardware (Platform and OS):*
   These indicate the computing environment where the bug was
   found.

*Importance (Priority and Severity):*
   The bug assignee uses the Priority field to prioritize his or her bugs.
   It's a good idea not to change this on other people's bugs. The default
   values are P1 to P5.

   The Severity field indicates how severe the problem is - from blocker
   ("application unusable") to trivial ("minor cosmetic issue"). You
   can also use this field to indicate whether a bug is an enhancement
   request.

*\*Target Milestone:*
   A future version by which the bug is to
   be fixed. e.g. The Bugzilla Project's milestones for future
   Bugzilla versions are 4.4, 5.0, 6.0, etc. Milestones are not
   restricted to numbers, though - you can use any text strings, such
   as dates.

*Assigned To:*
   The person responsible for fixing the bug.

*\*QA Contact:*
   The person responsible for quality assurance on this bug.

*URL:*
   A URL associated with the bug, if any.

*\*Whiteboard:*
   A free-form text area for adding short notes and tags to a bug.

*Keywords:*
   The administrator can define keywords which you can use to tag and
   categorise bugs - e.g. ``crash`` or ``regression``.

*Personal Tags:*
   Unlike Keywords which are global and visible by all users, Personal Tags
   are personal and can only be viewed and edited by their author. Editing
   them won't send any notification to other users. Use them to tag and keep
   track of bugs. 

*Dependencies (Depends On and Blocks):*
   If this bug cannot be fixed unless other bugs are fixed (depends
   on), or this bug stops other bugs being fixed (blocks), their
   numbers are recorded here.

   Clicking the ``Dependency tree`` link shows
   the dependency relationships of the bug as a tree structure.
   You can change how much depth to show, and you can hide resolved bugs
   from this page. You can also collaps/expand dependencies for
   each non-terminal bug on the tree view, using the [-]/[+] buttons that
   appear before the summary.

*Reported:*
   The person who filed the bug, and the date and time they did it.

*Modified:*
   The date and time the bug was last changed.

*CC List:*
   A list of people who get mail when the bug changes.

*Ignore Bug Mail:*
   Set this if you want never to get bug mail from this bug again.

*\*See Also:*
   Bugs, in this Bugzilla or other Bugzillas or bug trackers, which are
   related to this one.

*Flags:*
   A flag is a kind of status that can be set on bugs or attachments
   to indicate that the bugs/attachments are in a certain state.
   Each installation can define its own set of flags that can be set
   on bugs or attachments. See :ref:`flags`.

*\*Time Tracking:*
   This form can be used for time tracking.
   To use this feature, you have to be blessed group membership
   specified by the ``timetrackinggroup`` parameter. See :ref:`time-tracking`
   for more information.

   Orig. Est.:
       This field shows the original estimated time.
   Current Est.:
       This field shows the current estimated time.
       This number is calculated from ``Hours Worked``
       and ``Hours Left``.
   Hours Worked:
       This field shows the number of hours worked.
   Hours Left:
       This field shows the ``Current Est.`` -
       ``Hours Worked``.
       This value + ``Hours Worked`` will become the
       new Current Est.
   %Complete:
       This field shows what percentage of the task is complete.
   Gain:
       This field shows the number of hours that the bug is ahead of the
       ``Orig. Est.``.
   Deadline:
       This field shows the deadline for this bug.

*Attachments:*
   You can attach files (e.g. testcases or patches) to bugs. If there
   are any attachments, they are listed in this section. See
   :ref:`attachments` for more information.

*Additional Comments:*
   You can add your two cents to the bug discussion here, if you have
   something worthwhile to say.
