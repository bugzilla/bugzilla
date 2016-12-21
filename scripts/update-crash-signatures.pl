#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(. lib local/lib/perl5);
$| = 1;




use constant BATCH_SIZE => 100;

use Bugzilla;
use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Util qw( trim );
use List::MoreUtils qw( any );
use Text::Balanced qw( extract_bracketed extract_multiple );

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $user = Bugzilla::User->check({ name => 'automation@bmo.tld' });
$user->{groups} = [ Bugzilla::Group->get_all ];
$user->{bless_groups} = [ Bugzilla::Group->get_all ];
Bugzilla->set_user($user);

my $dbh = Bugzilla->dbh;

# find the bugs

my $bugs = $dbh->selectall_arrayref(
    "SELECT bug_id,cf_crash_signature FROM bugs WHERE resolution = '' AND cf_crash_signature != ''",
    { Slice => {} }
);
my $count = scalar @$bugs;

# update

die "No bugs found\n" unless $count;
print "Found $count open bug(s) with crash signatures\nPress <Ctrl-C> to stop or <Enter> to continue..\n";
getc();

my $updated = 0;
foreach my $rh_bug (@$bugs) {
    my $bug_id    = $rh_bug->{bug_id};
    my $signature = $rh_bug->{cf_crash_signature};

    # check for updated signature
    my $collapsed = collapse($signature);
    next if is_same($signature, $collapsed);

    # ignore signatures malformed in a way that would result in updating on each pass
    next if $collapsed ne collapse($collapsed);

    # update the bug, preventing bugmail
    print "$bug_id\n";
    $dbh->bz_start_transaction;
    my $bug = Bugzilla::Bug->check($bug_id);
    $bug->set_all({ cf_crash_signature => $collapsed });
    $bug->update();
    $dbh->do("UPDATE bugs SET lastdiffed = delta_ts WHERE bug_id = ?", undef, $bug_id);
    $dbh->bz_commit_transaction;

    # object caching causes us to consume a lot of memory
    # process in batches
    last if ++$updated == BATCH_SIZE;
}
print "Updated $updated bugs(s)\n";

sub is_same {
    my ($old, $new) = @_;
    $old =~ s/[\015\012]+/ /g;
    $new =~ s/[\015\012]+/ /g;
    return trim($old) eq trim($new);
}

sub collapse {
    my ($crash_signature) = @_;

    # ignore completely invalid signatures
    return $crash_signature unless $crash_signature =~ /\[/ && $crash_signature =~ /\]/;

    # split
    my @signatures =
        grep { /\S/ }
        extract_multiple($crash_signature, [ sub { extract_bracketed($_[0], '[]') } ]);
    my @unbracketed = map { unbracketed($_) } @signatures;

    foreach my $signature (@signatures) {
        # ignore invalid signatures
        next unless $signature =~ /^\s*\[/;
        next if unbracketed($signature) =~ /\.\.\.$/;

        # collpase
        my $collapsed = collapse_crash_sig({
            signature         => $signature,
            open              => '<',
            replacement_open  => '<',
            close             => '>',
            replacement_close => 'T>',
            exceptions        => [],
        });
        $collapsed = collapse_crash_sig({
            signature         => $collapsed,
            open              => '(',
            replacement_open  => '',
            close             => ')',
            replacement_close => '',
            exceptions        => ['anonymous namespace', 'operator'],
        });
        $collapsed =~ s/\s+/ /g;

        # ignore sigs that collapse down to nothing
        next if $collapsed eq '[@ ]';

        # don't create duplicates
        my $unbracketed = unbracketed($collapsed);
        next if any { $unbracketed eq $_ } @unbracketed;

        push @signatures, $collapsed;
        push @unbracketed, $unbracketed;
    }

    return join("\015\012", map { trim($_) } @signatures);
}

sub unbracketed {
    my ($signature) = @_;
    $signature =~ s/(^\s*\[\s*|\s*\]\s*$)//g;
    return $signature;
}

# collapsing code lifted from socorro:
# https://github.com/mozilla/socorro/blob/master/socorro/processor/signature_utilities.py#L110

my ($target_counter, $exception_mode, @collapsed);

sub append_if_not_in_collapse_mode {
    my ($character) = @_;
    if (!$target_counter) {
        push @collapsed, $character;
    }
}

sub is_exception {
    my ($exceptions, $remaining_original_line, $line_up_to_current_position) = @_;
    foreach my $exception (@$exceptions) {
        if (substr($remaining_original_line, 0, length($exception)) eq $exception) {
            return 1;
        }
        if (substr($line_up_to_current_position, -length($exception)) eq $exception) {
            return 1;
        }
    }
    return 0;
}

sub collapse_crash_sig {
    my ($params) = @_;

    $target_counter = 0;
    @collapsed      = ();
    $exception_mode = 0;
    my $signature = $params->{signature};

    for (my $i = 0; $i < length($signature); $i++) {
        my $character = substr($signature, $i, 1);
        if ($character eq $params->{open}) {
            if (is_exception($params->{exceptions}, substr($signature, $i + 1), substr($signature, 0, $i))) {
                $exception_mode = 1;
                append_if_not_in_collapse_mode($character);
                next;
            }
            append_if_not_in_collapse_mode($params->{replacement_open});
            $target_counter++;
        }
        elsif ($character eq $params->{close}) {
            if ($exception_mode) {
                append_if_not_in_collapse_mode($character);
                $exception_mode = 0;
            }
            else {
                $target_counter--;
                append_if_not_in_collapse_mode($params->{replacement_close});
            }
        }
        else {
            append_if_not_in_collapse_mode($character);
        }
    }

    return join '', @collapsed;
}
