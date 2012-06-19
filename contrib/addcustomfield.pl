#!/usr/bin/perl -wT
# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# Contributor(s): Frédéric Buclin <LpSolit@gmail.com>
#                 David Miller <justdave@mozilla.com>

use strict;
use lib qw(. lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Field;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my %types = (
  'freetext' => FIELD_TYPE_FREETEXT,
  'single_select' => FIELD_TYPE_SINGLE_SELECT,
  'multi_select' => FIELD_TYPE_MULTI_SELECT,
  'textarea' => FIELD_TYPE_TEXTAREA,
  'datetime' => FIELD_TYPE_DATETIME,
  'bug_id' => FIELD_TYPE_BUG_ID,
  'bug_urls' => FIELD_TYPE_BUG_URLS,
  'keywords' => FIELD_TYPE_KEYWORDS,
);

my $syntax = 
    "syntax: addcustomfield.pl <field name> [field type]\n\n" .
    "valid field types:\n  " . join("\n  ", sort keys %types) . "\n\n" .
    "the default field type is single_select\n";

my $name = shift || die $syntax;
my $type = lc(shift || 'single_select');
exists $types{$type} || die "Invalid field type '$type'.\n\n$syntax";
$type = $types{$type};

Bugzilla::Field->create({
    name        => $name,
    description => 'Please give me a description!',
    type        => $type,
    mailhead    => 0,
    enter_bug   => 0,
    obsolete    => 1,
    custom      => 1,
    buglist     => 1,
});
print "Done!\n";

my $urlbase = Bugzilla->params->{urlbase};
print "Please visit ${urlbase}editfields.cgi?action=edit&name=$name to finish setting up this field.\n";
