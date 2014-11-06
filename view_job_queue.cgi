#!/usr/bin/perl -T
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Util qw(template_var);
use Scalar::Util qw(blessed);
use Storable qw(read_magic thaw);

my $user = Bugzilla->login(LOGIN_REQUIRED);
$user->in_group("admin")
    || ThrowUserError("auth_failure", { group  => "admin",
                                        action => "access",
                                        object => "job_queue" });

my $vars = {};
generate_report($vars);

print Bugzilla->cgi->header();
my $template = Bugzilla->template;
$template->process('admin/reports/job_queue.html.tmpl', $vars)
    || ThrowTemplateError($template->error());

sub generate_report {
    my ($vars) = @_;
    my $dbh = Bugzilla->dbh;
    my $user = Bugzilla->user;

    my $query = "
        SELECT
            j.jobid,
            j.arg,
            j.run_after AS run_time,
            j.grabbed_until,
            f.funcname AS func,
            (SELECT COUNT(*)
               FROM ts_error
              WHERE ts_error.jobid = j.jobid
            ) AS error_count,
            e.error_time AS error_time,
            e.message AS error_message
        FROM
            ts_job j
            INNER JOIN ts_funcmap f
                ON f.funcid = j.funcid
            NATURAL LEFT JOIN (
                SELECT MAX(error_time) AS error_time, jobid
                  FROM ts_error
                 GROUP BY jobid
            ) t
            LEFT JOIN ts_error e
                ON (e.error_time  = t.error_time) AND (e.jobid = t.jobid)
        ORDER BY
            j.run_after, j.grabbed_until, j.insert_time, j.jobid
        " . $dbh->sql_limit(JOB_QUEUE_VIEW_MAX_JOBS + 1);

    $vars->{jobs} = $dbh->selectall_arrayref($query, { Slice => {} });
    if (@{ $vars->{jobs} } == JOB_QUEUE_VIEW_MAX_JOBS + 1) {
        pop @{ $vars->{jobs} };
        $vars->{job_count} = $dbh->selectrow_array("SELECT COUNT(*) FROM ts_job");
        $vars->{too_many_jobs} = 1;
    }

    my $bug_word = template_var('terms')->{bug};
    foreach my $job (@{ $vars->{jobs} }) {
        my ($recipient, $description);
        eval {
            if ($job->{func} eq 'Bugzilla::Job::BugMail') {
                my $arg = _cond_thaw(delete $job->{arg});
                next unless $arg;
                my $vars = $arg->{vars};
                $recipient = $vars->{to_user}->{login_name};
                $description = "[$bug_word " . $vars->{bug}->{bug_id} . '] '
                               . $vars->{bug}->{short_desc};
            }

            elsif ($job->{func} eq 'Bugzilla::Job::Mailer') {
                my $arg = _cond_thaw(delete $job->{arg});
                next unless $arg;
                my $msg = $arg->{msg};
                if (ref($msg) && blessed($msg) eq 'Email::MIME') {
                    $recipient = $msg->header('to');
                    $description = $msg->header('subject');
                } else {
                    ($recipient) = $msg =~ /\nTo: ([^\n]+)/i;
                    ($description) = $msg =~ /\nSubject: ([^\n]+)/i;
                }
            }
        };
        if ($recipient) {
            $job->{subject} = "<$recipient> $description";
        }
    }
}

sub _cond_thaw {
    my $data = shift;
    my $magic = eval { read_magic($data); };
    if ($magic && $magic->{major} && $magic->{major} >= 2 && $magic->{major} <= 5) {
        my $thawed = eval { thaw($data) };
        if ($@) {
            # false alarm... looked like a Storable, but wasn't
            return undef;
        }
        return $thawed;
    } else {
        return undef;
    }
}
