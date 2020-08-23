#!/usr/bin/env perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
#
# Usage secbugsreport.pl YYYY MM DD HH MM SS +|-ZZZZ
#  e.g. secbugsreport.pl $(date +'%Y %m %d %H %M %S %z')

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Component;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Logging;
use Bugzilla::Mailer;
use Bugzilla::Report::SecurityRisk;

use DateTime;
use URI;
use JSON::MaybeXS;
use Mojo::File qw(path);
use Data::Dumper;
use Types::Standard qw(Int);

BEGIN { Bugzilla->extensions }
Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my ($year, $month, $day, $hours, $minutes, $seconds, $time_zone_offset) = @ARGV;

die 'secbugsreport.pl: report not active'
  unless Bugzilla->params->{report_secbugs_active};
die 'secbugsreport.pl: improper date format'
  unless Int->check($year)
  && Int->check($month)
  && Int->check($day)
  && Int->check($hours)
  && Int->check($minutes)
  && Int->check($seconds);

my $html_crit_high;
my $html_moderate_low;
my $template_crit_high = Bugzilla->template();
my $template_moderate_low = Bugzilla->template();
my $end_date = DateTime->new(
  year      => $year,
  month     => $month,
  day       => $day,
  hour      => $hours,
  minute    => $minutes,
  second    => $seconds,
  time_zone => $time_zone_offset
);
$end_date->set_time_zone('UTC');

my $start_date            = $end_date->clone()->subtract(months => 12);
my $start_date_no_graphs  = $end_date->clone()->subtract(months => 2);
my $report_week           = $end_date->ymd('-');
my $teams                 = decode_json(Bugzilla->params->{report_secbugs_teams});

# Sec Critical and Sec High report
my $sec_keywords_crit_high = ['sec-critical', 'sec-high'];
my $report_crit_high       = Bugzilla::Report::SecurityRisk->new(
  start_date   => $start_date,
  end_date     => $end_date,
  teams        => $teams,
  sec_keywords => $sec_keywords_crit_high,
  very_old_days => 45
);
my $sorted_teams_crit_high = sorted_team_names_by_open_bugs($report_crit_high);
my $vars_crit_high = {
  urlbase            => Bugzilla->localconfig->urlbase,
  report_week        => $report_week,
  teams              => $sorted_teams_crit_high,
  sec_keywords       => $sec_keywords_crit_high,
  results            => $report_crit_high->results,
  deltas             => $report_crit_high->deltas,
  missing_products   => $report_crit_high->missing_products,
  missing_components => $report_crit_high->missing_components,
  very_old_days      => $report_crit_high->very_old_days,
  build_bugs_link    => \&build_bugs_link,
};
$template_crit_high->process(
  'reports/email/security-risk.html.tmpl',
  $vars_crit_high,
  \$html_crit_high
) or ThrowTemplateError($template_crit_high->error());

# Sec Moderate and Sec Low report
# These have to be done separately since they do not want the by
# teams results combined. This template is specific is to this request,
# for a generic template use security-risk.html.tmpl as above.
my $report_moderate       = Bugzilla::Report::SecurityRisk->new(
  start_date   => $start_date_no_graphs,
  end_date     => $end_date,
  teams        => $teams,
  sec_keywords => ['sec-moderate'],
  very_old_days => 45
);
my $report_low       = Bugzilla::Report::SecurityRisk->new(
  start_date   => $start_date_no_graphs,
  end_date     => $end_date,
  teams        => $teams,
  sec_keywords => ['sec-low'],
  very_old_days => 45
);
my $sorted_teams_moderate = sorted_team_names_by_open_bugs($report_moderate);
my $sorted_teams_low = sorted_team_names_by_open_bugs($report_low);
my $vars_moderate_low = {
  urlbase            => Bugzilla->localconfig->urlbase,
  report_week        => $report_week,
  sec_keywords       => ['sec-moderate', 'sec-low'],
  teams_moderate     => $sorted_teams_moderate,
  results_moderate   => $report_moderate->results,
  deltas_moderate    => $report_moderate->deltas,
  teams_low          => $sorted_teams_low,
  results_low        => $report_low->results,
  deltas_low         => $report_low->deltas,
  very_old_days      => $report_low->very_old_days,
  build_bugs_link    => \&build_bugs_link,
};
$template_moderate_low->process(
  'reports/email/security-risk-moderate-low.html.tmpl',
  $vars_moderate_low,
  \$html_moderate_low
) or ThrowTemplateError($template_moderate_low->error());

# Crit + High Report. For now, only send HTML email.
my @parts_crit_high = (
  Email::MIME->create(
    attributes => {
      content_type => 'text/html',
      charset      => 'UTF-8',
      encoding     => 'quoted-printable',
    },
    body_str => $html_crit_high,
  ),
  map {
    Email::MIME->create(
      header_str => ['Content-ID' => "<$_.png>",],
      attributes => {
        filename     => "$_.png",
        charset      => 'UTF-8',
        content_type => 'image/png',
        disposition  => 'inline',
        name         => "$_.png",
        encoding     => 'base64',
      },
      body => $report_crit_high->graphs->{$_}->slurp,
    )
  } sort { $a cmp $b } keys %{$report_crit_high->graphs}
);

my @recipients = split /[\s,]+/, Bugzilla->params->{report_secbugs_emails};
DEBUG('recipients: ' . join ', ', @recipients);
my $to_address   = shift @recipients;
my $cc_addresses = @recipients ? join ', ', @recipients : '';

my $email_crit_high = Email::MIME->create(
  header_str => [
    From              => Bugzilla->params->{'mailfrom'},
    To                => $to_address,
    Cc                => $cc_addresses,
    Subject           => "Security Bugs Report for $report_week",
    'X-Bugzilla-Type' => 'admin',
  ],
  parts => [@parts_crit_high],
);

MessageToMTA($email_crit_high);

# Moderate + Low Report. For now, only send HTML email.
my @parts_moderate_low = (
  Email::MIME->create(
    attributes => {
      content_type => 'text/html',
      charset      => 'UTF-8',
      encoding     => 'quoted-printable',
    },
    body_str => $html_moderate_low,
  )
);

my $email_moderate_low = Email::MIME->create(
  header_str => [
    From              => Bugzilla->params->{'mailfrom'},
    To                => $to_address,
    Cc                => $cc_addresses,
    Subject           => "Security Bugs Report (moderate & low) for $report_week",
    'X-Bugzilla-Type' => 'admin',
  ],
  parts => [@parts_moderate_low],
);

MessageToMTA($email_moderate_low);

my $report_dump_file = path(bz_locations->{datadir}, "$year-$month-$day.dump");
$report_dump_file->spurt(Dumper($report_crit_high));
# Don't dump moderate low

sub build_bugs_link {
  my ($arr, $product) = @_;
  my $uri = URI->new(Bugzilla->localconfig->urlbase . 'buglist.cgi');
  $uri->query_param(bug_id => (join ',', @$arr));
  $uri->query_param(product => $product) if $product;
  return $uri->as_string;
}

sub sorted_team_names_by_open_bugs {
  my ($report) = @_;
  my $bugs_by_team = $report->results->[-1]->{bugs_by_team};
  my @sorted_team_names = sort { ## no critic qw(BuiltinFunctions::ProhibitReverseSortBlock
    @{$bugs_by_team->{$b}->{open}} <=> @{$bugs_by_team->{$a}->{open}}
      || $a cmp $b
  } keys %$teams;
  return \@sorted_team_names;
}
