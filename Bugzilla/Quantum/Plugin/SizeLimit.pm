# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Quantum::Plugin::SizeLimit;
use 5.10.1;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::JSON qw(decode_json);
use Bugzilla::Logging;

use constant MIN_SIZE_LIMIT        => 750_000;
use constant HAVE_LINUX_SMAPS_TINY => eval { require Linux::Smaps::Tiny };
use constant HAVE_BSD_RESOURCE     => eval { require BSD::Resource };

BEGIN {
  if (HAVE_LINUX_SMAPS_TINY) {
    Linux::Smaps::Tiny->import('get_smaps_summary');
  }
  if (HAVE_BSD_RESOURCE) {
    BSD::Resource->import;
  }
}

my @RESOURCES = qw(
  RLIMIT_CPU RLIMIT_FSIZE RLIMIT_DATA RLIMIT_STACK RLIMIT_CORE RLIMIT_RSS RLIMIT_MEMLOCK RLIMIT_NPROC RLIMIT_NOFILE
  RLIMIT_OFILE RLIMIT_OPEN_MAX RLIMIT_LOCKS RLIMIT_AS RLIMIT_VMEM RLIMIT_PTHREAD RLIMIT_TCACHE RLIMIT_AIO_MEM
  RLIMIT_AIO_OPS RLIMIT_FREEMEM RLIMIT_NTHR RLIMIT_NPTS RLIMIT_RSESTACK RLIMIT_SBSIZE RLIMIT_SWAP RLIMIT_MSGQUEUE
  RLIMIT_RTPRIO RLIMIT_RTTIME RLIMIT_SIGPENDING
);

my %RESOURCE;
if (HAVE_BSD_RESOURCE) {
  $RESOURCE{$_} = eval $_ for @RESOURCES;
}

sub register {
  my ($self, $app, $conf) = @_;

  if (HAVE_BSD_RESOURCE) {
    my $setrlimit = decode_json(Bugzilla->localconfig->{setrlimit});

    # This trick means the master process will not a size limit.
    Mojo::IOLoop->next_tick(sub {
      foreach my $resource (keys %$setrlimit) {
        setrlimit($RESOURCE{$resource}, $setrlimit->{$resource}, $setrlimit->{$resource});
      }
    });
  }

  if (HAVE_LINUX_SMAPS_TINY) {
    my $size_limit = Bugzilla->localconfig->{size_limit};
    return unless $size_limit;

    if ($size_limit < MIN_SIZE_LIMIT) {
      WARN(sprintf "size_limit cannot be smaller than %d", MIN_SIZE_LIMIT);
      $size_limit = MIN_SIZE_LIMIT;
    }

    $app->hook(
      after_dispatch => sub {
        my $c       = shift;
        my $summary = get_smaps_summary();
        if ($summary->{Size} >= $size_limit) {
          my $diff = $summary->{Size} - $size_limit;
          INFO("memory size exceeded $size_limit by $diff ($summary->{Size})");
          $c->res->headers->connection('close');
          Mojo::IOLoop->singleton->stop_gracefully;
        }
      }
    );
  }
}

1;
