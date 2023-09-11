This is a list of known release blockers for Bugzilla Harmony, in prority list
order.

# MySQL compatibility & checksetup

We can and should only support current and previous releases of MySQL.  People
coming from MySQL 5.6 or earlier should be nudged to use utf8mb4, which allows
for emojis and some obscure languages.

Currently harmony will work with MariaDB 10+ (any version), but will not
function in MySQL 8 due to the word "groups" becoming a reserved word.

We need to make Bugzilla work on MySQL 8+.

I believe the code I wrote over a year ago could allow us to support mysql 8,
and that's in [this
branch](https://github.com/bugzilla/harmony/blob/dylan/mysql-8)

# Upgrade Path from 4.4, 5.0, 5.2, and 5.1

Code must be added to Bugzilla::DB::Install to support upgrading existing
schemas from 4.4, 5.0, and 5.2 installs. In addition, we should provide a way
to migrate from the abandoned 5.1 development branch, which has some feature
mis-match with harmony.

Things to check:
- Multiple aliases was reverted and we'll have to have code to handle that.
- 5.1 supports usernames that are distinct from email addresses. Harmony
  doesn't have that yet.
- (TODO, I'm sure someone will make a suggestion)

# Merge or Re-Apply the Email Code from 5.0

Harmony is a descendant of Bugzilla 4.2.  The email mechanism used in 4.2
depends on Perl modules that no longer have upstream support. BMO maintained
their own bugfixes to those modules, but that’s not something we want to do
upstream.  Version 5.0 rewrote the email code to use currently-supported Perl
modules.  That needs to be ported into Harmony.

# Postgresql Compatibility

We suspect, but don’t know for certain, that BMO may have moved to using
PostgreSQL on their back end at one point, and may have switched back to MySQL
and/or Maria DB since. Bugzilla upstream supports PostgreSQL, but for whatever
reason some of BMO’s code for handling it was placed in the Bugzilla extension
they used for their local customizations instead of in the actual database
abstraction modules. This code needs to be migrated back to the database
abstraction modules so their extension can be disposed of.

# Sensible, Default Logging Configuration

Bugzilla::Logging controls how the application logs. It has support for
defaults, but those defautls were written for BMO and don't make sense for the
app.

The defaults need to be updated to log to a more generic location users are
likely to have, or walk through setting it during the installation script.

# Docker and Containerization

I would like the Dockerfile to be rewritten such that the ENTRYPOINT is the
bugzilla.pl script, so that the container can be used as a drop in replacement
for the bugzilla.pl executable.

It would be good to add sub-commands for checksetup and the jobqueue to this.
bugzilla.pl sub-commands can be defined in the Bugzilla::App::Cmd::* namespace.

If we release harmony and it has a good (and small!) container, it will look
good.

# Documentation

BMO gutted some of upstream's documentation about Bugzilla, so the entirety of
the documentation for the Harmony branch will need to be reviewed and
potentially heavily edited prior to release. We may need to port some of the
existing upstream documentation back into it.

# Release Notes

Release notes for Harmony will be a HUGE task. Since Harmony diverged from
upstream at 4.2, but backported many (but not all) upstream features, someone
will need to go through and determine what changes the two forks did NOT have
in common so we can properly document in the release notes any features that
were dropped or new features being picked up when compared to version 5.2.

- Start with an empty list.
- Go through [Harmony's commit
  logs](https://github.com/bugzilla/harmony/commits/main) going all the way
  back to Version 4.2, and make note of anything new/changed that's release-note
  worthy.
- Go through [5.2's commit
  logs](https://github.com/bugzilla/bugzilla/commits/5.2) goinng all the way
  back to Version 4.2
  - anything new/changed that is already on the list needs to be removed from
    the list (because 5.2 already had it, so it's not a change)
  - anything new/changed that is NOT already on your list needs to be added to
    the list as a removed feature
