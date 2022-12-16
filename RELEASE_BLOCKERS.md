This is a list of known release blockers for Bugzilla Harmony, in prority list order.

# MySQL compatibility & checksetup

We can and should only support current and previous releases of MySQL. 
People coming from MySQL 5.6 or earlier should be nudged to use utf8mb4, which allows for emojis
and some obscure languages.

Currently harmony will work with MariaDB 10+ (any version), 
but will not function in MySQL 8 due to the word "groups" becoming a reserved word.

Checksetup needs to be updated help the user understand if their mysql can work.

For MySQL 8, either:
- We commit to supporting mysql 8
- We detect mysql 8 and direct the user to use either mysql 5.7 or mariadb

The later option is not very pleasant. 
I believe the code I wrote over a year ago could allow us to support mysql 8, and that's in [this branch](https://github.com/bugzilla/harmony/blob/dylan/mysql-8)

# Upgrade Path from 4.4, 5.0, 5.2, and 5.1

Code must be added to Bugzilla::DB::Install to support upgrading existing schemas from 4.4, 5.0, and 5.2 installs. In addition, we should provide a way to migrate from the abandoned 5.1 development branch, which has some feature mis-match with harmony.

Things to check:
- Multiple aliases was reverted and we'll have to have code to handle that.
- (TODO, I'm sure someone will make a suggestion)

# Merge or Re-Apply the Email Code from 5.0

Bugzilla Harmony's email code is from BMO, which was 4.2.
In 5.0 or so, the email code was refactored to use a much better supported email module (Email::Sender, I think)

We need to merge that change back in, or just write the code over again.

# Postgresql Compatibility

I think most of the postgres incompatibility is in the "BMO" extension, and in order to be able to 
release I now believe we should remove the BMO extension from our codebase.
This is unfortunate because it has a lot of useful features, but given resource constraints it is the best move.

# Sensible, Default Logging Configuration

Bugzilla::Logging controls how the application logs. It has support for defaults, but those defautls
were written for BMO and don't make sense for the app. 

This is left a bit vague, but here's the guiding principal: when you install bugzilla it needs to log in
a place you expect it to.

# Docker and Containerization

I would like the Dockerfile to be rewritten such that the ENTRYPOINT is the bugzilla.pl script, so that
the container can be used as a drop in replacement for the bugzilla.pl executable.

It would be good to add sub-commands for checksetup and the jobqueue to this.
bugzilla.pl sub-commands can be defined in the Bugzilla::App::Cmd::* namespace.

If we release harmony and it has a good (and small!) container, it will look good.


