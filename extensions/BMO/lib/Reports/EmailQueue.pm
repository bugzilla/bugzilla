# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BMO::Reports::EmailQueue;
use strict;
use warnings;

use Bugzilla::Error;
use Scalar::Util qw(blessed);
use Storable ();

sub report {
    my ($vars, $filter) = @_;
    my $dbh = Bugzilla->dbh;
    my $user = Bugzilla->user;

    $user->in_group('admin') || $user->in_group('infra')
        || ThrowUserError('auth_failure', { group  => 'admin',
                                            action => 'run',
                                            object => 'email_queue' });

    my $query = "
        SELECT j.jobid,
               j.arg,
               j.insert_time,
               j.run_after AS run_time,
               COUNT(e.jobid) AS error_count,
               MAX(e.error_time) AS error_time,
               e.message AS error_message
          FROM ts_job j
               LEFT JOIN ts_error e ON e.jobid = j.jobid
      GROUP BY j.jobid
      ORDER BY j.run_after";

    $vars->{'jobs'} = $dbh->selectall_arrayref($query, { Slice => {} });
    foreach my $job (@{ $vars->{'jobs'} }) {
        eval {
            my ($recipient, $description);
            my $arg = _cond_thaw(delete $job->{arg});

            if (exists $arg->{vars}) {
                my $vars = $arg->{vars};
                $recipient = $vars->{to_user}->{login_name};
                $description = '[Bug ' . $vars->{bug}->{bug_id} . '] ' . $vars->{bug}->{short_desc};
            } elsif (exists $arg->{msg}) {
                my $msg = $arg->{msg};
                if (ref($msg) && blessed($msg) eq 'Email::MIME') {
                    $recipient = $msg->header('to');
                    $description = $msg->header('subject');
                } else {
                    ($recipient) = $msg =~ /\nTo: ([^\n]+)/;
                    ($description) = $msg =~ /\nSubject: ([^\n]+)/;
                }
            }

            if ($recipient) {
                $job->{subject} = "<$recipient> $description";
            }
        };
    }
    $vars->{'now'} = (time);
}

sub _cond_thaw {
    my $data = shift;
    my $magic = eval { Storable::read_magic($data); };
    if ($magic && $magic->{major} && $magic->{major} >= 2 && $magic->{major} <= 5) {
        my $thawed = eval { Storable::thaw($data) };
        if ($@) {
            # false alarm... looked like a Storable, but wasn't.
            return $data;
        }
        return $thawed;
    } else {
        return $data;
    }
}


1;
