#!/usr/bin/perl -T
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use strict;
use warnings;
use lib qw( . lib );

use Test::More;
use Bugzilla;
use Bugzilla::Extension;

my $class = Bugzilla::Extension->load('extensions/BMO/Extension.pm',
                                      'extensions/BMO/Config.pm');

my $parse  = $class->can('parse_bounty_attachment_description');
my $format = $class->can('format_bounty_attachment_description');

ok($parse, "got the function");

my $bughunter = $parse->('bughunter@hacker.org, , 2014-06-25, , ,false');
is_deeply({ reporter_email => 'bughunter@hacker.org',
            amount_paid    => '',
            reported_date  => '2014-06-25',
            fixed_date     => '',
            awarded_date   => '',
            publish        => 0,
            credit         => []}, $bughunter);

my $hfli = $parse->('hfli@fortinet.com, 1000, 2010-07-16, 2010-08-04, 2011-06-15, true, Fortiguard Labs');
is_deeply({  reporter_email => 'hfli@fortinet.com',
             amount_paid    => '1000',
             reported_date  => '2010-07-16',
             fixed_date     => '2010-08-04',
             awarded_date   => '2011-06-15',
             publish        => 1,
             credit         => ['Fortiguard Labs']}, $hfli);

is('batman@justiceleague.america,1000,2015-01-01,2015-02-02,2015-03-03,true,JLA,Wayne Industries,Test',
   $format->({ reporter_email => 'batman@justiceleague.america',
               amount_paid    => 1000,
               reported_date  => '2015-01-01',
               fixed_date     => '2015-02-02',
               awarded_date   => '2015-03-03',
               publish        => 1,
               credit         => ['JLA', 'Wayne Industries', 'Test'] }));

my $dylan = $parse->('dylan@hardison.net,2,2014-09-23,2014-09-24,2014-09-25,true,Foo bar,Bork,');
is_deeply({ reporter_email => 'dylan@hardison.net',
            amount_paid    => 2,
            reported_date  => '2014-09-23',
            fixed_date     => '2014-09-24',
            awarded_date   => '2014-09-25',
            publish        => 1,
            credit         => ['Foo bar', 'Bork']}, $dylan);

done_testing;
