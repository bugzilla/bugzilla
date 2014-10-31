# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Job::Mailer;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Constants;
use Bugzilla::Mailer;
BEGIN { eval "use parent qw(TheSchwartz::Worker)"; }

# The longest we expect a job to possibly take, in seconds.
use constant grab_for => 300;
# We don't want email to fail permanently very easily. Retry for 30 days.
use constant max_retries => 725;

# The first few retries happen quickly, but after that we wait an hour for
# each retry.
sub retry_delay {
    my ($class, $num_retries) = @_;
    if ($num_retries < 5) {
        return (10, 30, 60, 300, 600)[$num_retries];
    }
    # One hour
    return 60*60;
}

sub work {
    my ($class, $job) = @_;
    eval { $class->process_job($job->arg) };
    if (my $error = $@) {
        if ($error eq EMAIL_LIMIT_EXCEPTION) {
            $job->declined();
        }
        else {
            $job->failed($error);
        }
        undef $@;
    }
    else {
        $job->completed;
    }
}

sub process_job {
    my ($class, $arg) = @_;
    MessageToMTA($arg, 1);
}

1;
