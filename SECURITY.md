# Security Policy

Current policy is to maintain two stable releases at all times. There
will be three stable releases for 4 months after each major release,
after which support for the oldest stable release will be dropped, 
returning us to two stable releases.

Right now we are in an "in-between" situation where a release was mistakenly
made on the 5.0.x branch that should have been 5.2 but was instead 5.0.5.
This caused us to fork the 5.0 branch after 5.0.4 to continue supporting
that code base, and support for 5.0.6 will continue on the 5.2.x branch
(5.2 will be considered a "point release" from 5.0.6, and 5.0.4.1 will
be the "point release" from 5.0.4, whereas 5.0.5 is a "major release"
from 5.0.4).

## Supported Versions

| Version             | Supported          | End of Support             |
| ------------------- | ------------------ | -------------------------- |
| 5.9.x (harmony/6.0) | :ballot_box_with_check: | 4 months after 6.4 release |
| 5.1.x               | :ballot_box_with_check: | When 5.9.1 is released     |
| 5.0.6 (5.2.x)       | :white_check_mark: | 4 months after 6.2 release |
| 5.0.4.x             | :white_check_mark: | 4 months after 6.0 release |
| 4.4.x               | :white_check_mark: | 4 months after 5.2 release |
| < 4.4               | :x:                |                            |

:ballot_box_with_check: = Development Branch

:white_check_mark: = Security Supported Branch

:x: = No longer supported

## Reporting a Vulnerability

Security vulnerabilities should be reported to
[Bugzilla](https://bugzilla.mozilla.org/enter_bug.cgi?product=Bugzilla).
There is a checkbox at the bottom of the submission form to indicate
a security issue. Checking the box will hide the bug from the public
and notify the security team. You should receive a response within a few
days. Note that we are a very small volunteer team, so time to fix the
problem may vary.
