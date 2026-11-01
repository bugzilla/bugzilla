#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use 5.14.0;
use strict;
use warnings;
use lib qw(. lib local/lib/perl5);

use File::Spec;
use Template;
use Test::More;

my $template_dir = File::Spec->catdir(
  'extensions', 'BugzillaDonationBanner', 'template', 'en', 'default'
);
my $template = Template->new({
  INCLUDE_PATH => $template_dir,
  FILTERS      => {
    html => sub {
      my $text = shift;
      $text =~ s/&/&amp;/g;
      $text =~ s/</&lt;/g;
      $text =~ s/>/&gt;/g;
      $text =~ s/"/&quot;/g;
      $text =~ s/'/&#39;/g;
      return $text;
    },
    none => sub { return $_[0] },
  },
});

sub render {
  my (%vars) = @_;
  my $output = '';
  ok($template->process('donation/banner.html.tmpl', \%vars, \$output),
    'template renders');
  return $output;
}

subtest 'no banner data produces no markup' => sub {
  my $output = render(donation => undef, show_dismissal => 1);
  unlike($output, qr/donation_banner|<form|<script/, 'no banner elements');
};

subtest 'home page renders controls and secure link' => sub {
  my $output = render(
    donation => {
      url     => 'https://bugzilla.org/donate',
      message => 'Support Bugzilla',
      token   => 'test-token',
      today   => '2026-11-01',
    },
    show_dismissal => 1,
  );

  like($output, qr/class="donation_banner home_banner"/, 'banner classes');
  like($output, qr/rel="noreferrer"/, 'donation link uses noreferrer');
  like($output, qr/method="post"/, 'dismissal uses POST');
  like($output, qr/name="token" value="test-token"/, 'includes token');
  like($output, qr/value="next_upgrade"/, 'offers next upgrade');
  like($output, qr/value="week"/, 'offers a week');
  like($output, qr/value="month"/, 'offers a month');
  like($output, qr/value="date"/, 'offers a date');
  like($output, qr/value="never"/, 'offers never');
};

subtest 'preferences context omits dismissal controls and escapes values' => sub {
  my $output = render(
    donation => {
      url     => 'https://example.test/?a=1&b="<bad>',
      message => '<script>alert(1)</script>',
      token   => 'unused',
      today   => '2026-11-01',
    },
    show_dismissal => 0,
  );

  like($output, qr/donation_banner_preferences/, 'preferences-page class');
  unlike($output, qr/<form|<script type="text\/javascript"/, 'no dismissal controls');
  like($output, qr/&lt;script&gt;alert\(1\)&lt;\/script&gt;/, 'message is escaped');
  like($output, qr/&amp;b=&quot;&lt;bad&gt;/, 'URL attribute is escaped');
};

done_testing;