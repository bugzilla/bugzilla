# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Job::RunTask;

use 5.10.1;
use strict;
use warnings;

use parent 'TheSchwartz::Worker';

use constant grab_for    => 300;
use constant max_retries => 0;

use Bugzilla::Logging;
use Module::Runtime qw(require_module);
use Scalar::Util qw(blessed);
use Email::MIME;
use Bugzilla::Mailer qw(MessageToMTA);

sub work {
  my ($class, $job) = @_;
  my $task       = $job->arg;
  my $task_class = blessed($task) // '';
  die "Invalid task class: $task_class" unless $task_class =~ /^Bugzilla::Task::/;
  require_module($task_class);

  my $template = Bugzilla->template;
  my $vars     = $task->run();
  my $name     = $task->name;
  my $html     = "";
  my $ok       = $template->process("email/task/$name.html.tmpl", $vars, \$html);

  unless ($ok) {
    FATAL($template->error);
    $html = "Something went run running task '$name'";
  }

  my @parts = (
    Email::MIME->create(
      attributes => {
        content_type => 'text/html',
        charset      => 'UTF-8',
        encoding     => 'quoted-printable',
      },
      body_str => $html,
    ),
  );

  my $email = Email::MIME->create(
    header_str => [
      From              => Bugzilla->params->{'mailfrom'},
      To                => $task->user->email,
      Subject           => $task->subject,
      'X-Bugzilla-Type' => 'task',
    ],
    parts => [@parts],
  );

  # We're already in the jobqueue, so send right away.
  MessageToMTA($email, 1);

  $job->completed;
}


1;
