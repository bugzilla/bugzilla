# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use utf8;
use strict;
use warnings;
use 5.10.1;
use lib qw( . lib local/lib/perl5 );
use Bugzilla::Util qw(extract_nicks);
use Test::More;
binmode STDOUT, ':encoding(utf-8)';

my @expect = (
    ['dhanesh95'],
    ['kentuckyfriedtakahe', 'k17e'],
    ['emceeaich'],
    ['seban'],
    ['emceeaich'],
    ['glob'],
    ['briansmith', 'bsmith'],
    ['bz'],
    ['dkl-test'],
    ['dylan'],
    ['7'],
    ['bwinton'],
    ['canuckistani'],
    ['GaryChen', 'PYChen', 'gchen', '陳柏宇'],
    ['gfx'],
    ['ted.mielczarek'],
    [],
    ['tb-l10n'],
    ['Gavin'],
    ['прозвище'],

);

while (<DATA>) {
    my @nicks = extract_nicks($_);
    is_deeply(\@nicks, shift @expect);
}

done_testing;

__DATA__
Dhanesh Sabane [:dhanesh95] (UTC+5:30)
Anthony Jones (:kentuckyfriedtakahe, :k17e)
Emma Humphries' Possibly Evil Twin (don't assign me bugs or needinfo, send those to :emceeaich, I'm just here for testing bmo)
Sebastin Santy [:seban]
Emma Humphries ☕️ (she/her) [:emceeaich] (UTC-8) +needinfo me
Byron Jones ‹:glob›
Brian Smith (:briansmith, :bsmith, use NEEDINFO?)
Boris Zbarsky [:bz]
Dave Lawrence (not real account) [:dkl-test]
Dylan Hardison [:dylan] (he/him)
[:7]
Blake Winton (:bwinton) (:☕️)
Jeff Griffiths (:canuckistani) (:⚡︎)
GaryChen [:GaryChen][:PYChen][:gchen][:陳柏宇]
Mozilla Graphics [:gfx] [:#gfx]
Ted Mielczarek [:ted.mielczarek]
Michiel van Leeuwen (email: mvl+moz@)
Thunderbird Localization Community [:tb-l10n]
:Gavin Sharp [email: censored@censored.com]
Ошибка монстра (:прозвище)
