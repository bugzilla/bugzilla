#!/usr/bin/perl -T

use 5.14.0;
use strict;
use warnings;

use lib qw(../../.. ../../../lib ../../../local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Token qw(check_hash_token);
use Bugzilla::Util qw(correct_urlbase);
use Bugzilla::Extension::BugzillaDonationBanner::Donation;

my $cgi = Bugzilla->cgi;

if ($cgi->request_method ne 'POST') {
  print $cgi->header(-status => '405 Method Not Allowed', -allow => 'POST');
  exit;
}

Bugzilla->login(LOGIN_REQUIRED);
check_hash_token($cgi->param('token'), ['donation_banner']);

Bugzilla::Extension::BugzillaDonationBanner::Donation::dismiss(
  scalar $cgi->param('donate_action'),
  scalar $cgi->param('donate_banner_reminder_date'),
);

print $cgi->redirect(-location => correct_urlbase() . 'index.cgi');
