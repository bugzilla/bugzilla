#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;
use lib qw(. lib local/lib/perl5);




use Bugzilla;
use Bugzilla::Component;
use Bugzilla::Constants;
use Bugzilla::Product;
use Bugzilla::User;

use Text::CSV_XS;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $auto_user = Bugzilla::User->check({ name => 'automation@bmo.tld' });
Bugzilla->set_user($auto_user);

my $dbh = Bugzilla->dbh;

my $filename = shift;
$filename || die "No CSV file provided.\n";

open(CSV, $filename) || die "Could not open CSV file: $!\n";

# Original Email,LDAP,Bugmail,Product,Component
my $csv = Text::CSV_XS->new();
while (my $line = <CSV>) {
    $csv->parse($line);
    my @values = $csv->fields();
    next if !@values;
    my ($email, $product_name, $component_name) = @values[2..4];
    print "Updating triage owner for '$product_name :: $component_name' ";
    my $product = Bugzilla::Product->new({ name => $product_name, cache => 1 });
    if (!$product) {
        print "product '$product_name' does not exist ... skipping.\n";
        next;
    }
    my $component = Bugzilla::Component->new({ name => $component_name, product => $product, cache => 1 });
    if (!$component) {
        print "component '$component_name' does not exist ... skipping.\n";
        next;
    }
    if (!$email) {
        print "... no email ... skipped.\n";
        next;
    }
    my $user = Bugzilla::User->new({ name => $email, cached => 1 });
    if (!$user) {
        print "... email '$email' does not exist ... skipping.\n";
        next;
    }
    print "to '$email' ... ";
    # HACK: See extensions/ComponentWatching/Extension.pm line 175
    Bugzilla->input_params->{watch_user} = $component->watch_user->login;
    $component->set_triage_owner($email);
    $component->update();
    print "done.\n";
}

close(CSV) || die "Could not close CSV file: $!\n";
