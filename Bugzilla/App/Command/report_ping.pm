# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::Command::report_ping;   ## no critic (Capitalization)
use Mojo::Base 'Mojolicious::Command';

use Bugzilla::Constants;
use Cwd qw(cwd);
use JSON::MaybeXS;
use Module::Runtime 'require_module';
use Mojo::File 'path';
use Mojo::Util 'getopt';
use PerlX::Maybe 'maybe';
use Try::Tiny;

has description => 'send a report ping to a url';
has usage       => sub { shift->extract_usage };

sub run {
  my ($self, @args) = @_;
  my $json
    = JSON::MaybeXS->new(convert_blessed => 1, canonical => 1, pretty => 1);
  my $class       = 'Simple';
  my $working_dir = cwd();
  my ($namespace, $doctype, $page, $rows, $base_url, $test, $dump_schema, $dump_documents, $since);

  Bugzilla->usage_mode(USAGE_MODE_CMDLINE);
  getopt \@args,
    'base-url|u=s'   => \$base_url,
    'page|p=i'       => \$page,
    'rows|r=i'       => \$rows,
    'since=s'        => \$since,
    'dump-schema'    => \$dump_schema,
    'dump-documents' => \$dump_documents,
    'class|c=s'      => \$class,
    'namespace|n=s'  => \$namespace,
    'doctype|d=s'    => \$doctype,
    'workdir|C=s'    => \$working_dir,
    'test'           => \$test;

  $base_url = 'http://localhost' if $dump_schema || $dump_documents || $test;
  die $self->usage unless $base_url;

  unless ($class =~ /::/) {
    $class = "Bugzilla::Report::Ping::$class";
  }
  try {
    require_module($class);
  }
  catch {
    say "Failed to load $class.";
    unless ($_ =~ /^Can't locate \S+ in \@INC/) {
      say "Error: $_";
    }
    exit 1;
  };
  my $report = $class->new(
    model           => Bugzilla->dbh->model,
    base_url        => $base_url,
    maybe rows      => $rows,
    maybe page      => $page,
    maybe namespace => $namespace,
    maybe doctype   => $doctype,
    maybe since     => $since,
  );

  if ($dump_schema) {
    my $schema =  $report->validator->schema->data ;
    $schema->{'$schema'} = "http://json-schema.org/draft-04/schema#";
    print $json->encode($schema);
    exit;
  }

  if ($test) {
    $self->foreach_page(
      $report,
      'Testing',
      sub {
        foreach my $result (@_) {
          my @error = $report->test_row($result);
          if (@error) {
            my $doc = $report->extract_content($result);
            die $json->encode({errors => \@error, result => $doc});
          }
        }
      }
    );
  }
  elsif ($dump_documents) {
    $self->foreach_page(
      $report,
      'Dumping',
      sub {
        foreach my $result (@_) {
          my $doc = $report->extract_content($result);
          my $id = $result->id;
          path($working_dir, "$id.json")->spurt($json->encode($doc));
        }
      }
    );
  }
  else {
    $self->foreach_page(
      $report,
      'Sending',
      sub {
        Mojo::Promise->all(map { $report->send_row($_) } @_)->wait;
      }
    );
  }
}

sub foreach_page {
  my ($self, $report, $label, $cb) = @_;
  my $rs = $report->resultset;
  foreach my $p ($report->page .. $report->pager->last_page) {
    $rs = $rs->page($p);
    say "$label page $p of ", $report->pager->last_page;
    $cb->( $rs->all );
  }
}

1;

__END__

=head1 NAME

Bugzilla::App::Command::report_ping - descriptionsend a report ping to a url';

=head1 SYNOPSIS

  Usage: APPLICATION report_ping

    ./bugzilla.pl report_ping --base-url=http://example.com/path

  Options:
    -h, --help               Print a brief help message and exits.
    -u, --base-url           URL to send the json documents to.
    -r, --rows num           (Optional) Number of requests to send at once. Default: 10.
    -p, --page num           (Optional) Page to start on. Default: 1
    --since str              (Optional) Typically the date of the last run.
    --class word             (Optional) Report class to use. Default: Simple
    --test                   Validate the json documents against the json schema.
    --dump-schema            Print the json schema.

=head1 DESCRIPTION

send a report ping to a url.

=head1 ATTRIBUTES

L<Bugzilla::App::Command::report_ping> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 description

  my $description = $report_ping->description;
  $rereport r      = $re$port_ping->description('Foo');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $report_ping->usage;
  $report_ping  = $report_ping->usage('Foo');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Bugzilla::App::Command::report_ping> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 run

  $report_ping->run(@ARGV);

Run this command.
