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

use FindBin;
use lib "$FindBin::Bin/..", "$FindBin::Bin/../lib", "$FindBin::Bin/../local/lib/perl5";

use Bugzilla;
use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Group;
use Bugzilla::Search;

use constant QUERY => {
    short_desc      => '[B2G]',
    resolution      => '---',
    short_desc_type => 'allwordssubstr',
    product         => 'Mozilla Localizations'
};

use constant COMMENT => "We've stopped shipping Firefox OS for phones. Thus resolving this as WONTFIX.";

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $dbh = Bugzilla->dbh;

# Make all changes as the automation user
my $auto_user = Bugzilla::User->check({ name => 'automation@bmo.tld' });
$auto_user->{groups} = [ Bugzilla::Group->get_all ];
$auto_user->{bless_groups} = [ Bugzilla::Group->get_all ];
Bugzilla->set_user($auto_user);

my $search = new Bugzilla::Search(fields => ['bug_id'], params => QUERY);
my ($data) = $search->data;

my $bug_count = @$data;
if ($bug_count == 0) {
    warn "There are no bugs to close.\n";
    exit 1;
}

print STDERR <<EOF;
About to close $bug_count bugs as WONTFIX.

Press <Ctrl-C> to stop or <Enter> to continue...
EOF
getc();

my $timestamp = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');

$dbh->bz_start_transaction;
foreach my $row (@$data) {
    my $bug_id = shift @$row;
    warn "Updating bug $bug_id\n";
    my $bug = Bugzilla::Bug->new($bug_id);
    $bug->set_bug_status('RESOLVED', { resolution => 'WONTFIX' });
    $bug->add_comment(COMMENT);
    $bug->update($timestamp);
    $dbh->do("UPDATE bugs SET lastdiffed = ? WHERE bug_id = ?",
             undef, $timestamp, $bug_id);
}
$dbh->bz_commit_transaction;

Bugzilla->memcached->clear_all();

__END__

=head1 NAME

close_bugs_wontfix.pl - close bugs matching query as RESOLVED/WONTFIX.

=head1 SYNOPSIS

    close_bugs_wontfix.pl
