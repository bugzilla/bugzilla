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
# The Initial Developer of the Original Code is the Mozilla
# Foundation. Portions created by Mozilla are
# Copyright (C) 2011 Mozilla Foundation. All Rights Reserved.
#
# Contributor(s): Byron Jones <glob@mozilla.com>

use strict;

use lib qw(.);

use Net::LDAP;
use XMLRPC::Lite;
use HTTP::Cookies;
use LWP::UserAgent;
use Term::ReadKey;
$| = 1;

#
#
#

print STDERR <<EOF;
This script cross-checks members of the Bugzilla mozilla-corporation group
with Mozilla's LDAP repository.

To run this script you need:
  - a bugzilla.mozilla.org admin account
  - a Mozilla LDAP account

EOF

my $bugzillaLogin = get_text('bl', 'Bugzilla Login: ');
my $bugzillaPassword = get_text('bp', 'Bugzilla Password: ', 1);
my $ldapLogin = get_text('ll', 'LDAP Login: ');
my $ldapPassword = get_text('lp', 'LDAP Password: ', 1);

sub get_text {
    my($switch, $prompt, $password) = @_;

    for (my $i = 0; $i <= $#ARGV; $i++) {
        if ($ARGV[$i] eq "-$switch") {
            return $ARGV[$i + 1];
        }
    }

    print STDERR $prompt;
    my $response = '';
    ReadMode 4;
    my $ch;
    while(1) {
        1 while (not defined ($ch = ReadKey(-1)));
        exit if $ch eq "\3";
        last if $ch =~ /[\r\n]/;
        if ($ch =~ /[\b\x7F]/) {
            next if $response eq '';
            chop $response;
            print "\b \b";
            next;
        }
        if ($ch eq "\025") {
            my $len = length($response);
            print(("\b" x $len) . (" " x $len) . ("\b" x $len));
            $response = '';
            next;
        }
        next if ord($ch) < 32;
        $response .= $ch;
        print STDERR $password ? '*' : $ch;
    }
    ReadMode 0;
    print STDERR "\n";
    return $response;
}
END {
    ReadMode 0;
}

#
# get list of users in mo-co group
#

my %bugzilla;
{
    my $cookie_jar = HTTP::Cookies->new(file => "cookies.txt", autosave => 1);
    my $proxy = XMLRPC::Lite->proxy(
        'https://bugzilla.mozilla.org/xmlrpc.cgi',
        'cookie_jar' => $cookie_jar);
    my $response;

    print STDERR "Logging in to Bugzilla...\n";
    $response = $proxy->call(
        'User.login',
        {
            login => $bugzillaLogin,
            password => $bugzillaPassword,
            remember => 1,
        }
    );
    if ($response->fault) {
        my ($package, $filename, $line) = caller;
        die $response->faultstring . "\n";
    }

    my $ua = LWP::UserAgent->new();
    $ua->cookie_jar($cookie_jar);
    $response = $ua->get('https://bugzilla.mozilla.org/editusers.cgi?' .
        'action=list&matchvalue=login_name&matchstr=&matchtype=substr&' .
        'grouprestrict=1&groupid=42');
    if (!$response->is_success) {
        die $response->status_line;
    }

    print STDERR "Getting user list from Bugzilla...\n";
    my $content = $response->content;
    while (
        $content =~ m#
            <td([^>]*)>[^<]+
            <a\shref="editusers[^"]+">([^<]+)</a>[^<]+
            </td>[^<]+
            <td[^>]*>([^<]+)</td>
        #gx
    ) {
        my ($class, $email, $name) = ($1, $2, $3);
        next if $class =~ /bz_inactive/;
        $email =~ s/(^\s+|\s+$)//g;
        $email =~ s/&#64;/@/;
        next unless $email =~ /@/;
        $name =~ s/(^\s+|\s+$)//g;
        $bugzilla{lc $email} = $name;
    }
}

#
# build list of current mo-co bugmail accounts
#

my %ldap;
{
    print STDERR "Logging into LDAP...\n";
    my $ldap = Net::LDAP->new('addressbook.mozilla.com',
        scheme => 'ldaps', onerror => 'die') or die "$@";
    $ldap->bind("mail=$ldapLogin,o=com,dc=mozilla", password => $ldapPassword);
    my $result = $ldap->search(
        base => 'o=com,dc=mozilla',
        scope => 'sub',
        filter => '(mail=*)',
        attrs => ['mail', 'bugzillaEmail', 'emailAlias', 'cn', 'employeeType'],
    );
    print STDERR "Getting user list from LDAP...\n";
    foreach my $entry ($result->entries) {
        my ($name, $bugMail, $mail, $type) =
            map { $entry->get_value($_) || '' }
            qw(cn bugzillaEmail mail employeeType);
        next if $type eq 'DISABLED';
        $mail = lc $mail;
        $ldap{$mail}{name} = $name;
        $ldap{$mail}{bugMail} = lc $bugMail;
        $ldap{$mail}{alias} = {};
        foreach my $alias (
            @{$entry->get_value('emailAlias', asref => 1) || []}
        ) {
            $ldap{$mail}{alias}{lc $alias} = 1;
        }
    }
}

#
# cross-check
#

my @invalid;
foreach my $bugzilla (sort keys %bugzilla) {
    # check for matching bugmail entry
    my $exists = 0;
    foreach my $mail (sort keys %ldap) {
        next unless $ldap{$mail}{bugMail} eq $bugzilla;
        $exists = 1;
        last;
    }
    next if $exists;

    # check for matching mail
    $exists = 0;
    foreach my $mail (sort keys %ldap) {
        next unless $mail eq $bugzilla;
        $exists = 1;
        last;
    }
    next if $exists;

    # check for matching email alias
    $exists = 0;
    foreach my $mail (sort keys %ldap) {
        next unless exists $ldap{$mail}{alias}{$bugzilla};
        $exists = 1;
        last;
    }
    next if $exists;

    push @invalid, $bugzilla;
}

my $max_length = 0;
foreach my $email (@invalid) {
    $max_length = length($email) if length($email) > $max_length;
}
foreach my $email (@invalid) {
    printf "%-${max_length}s %s\n", $email, $bugzilla{$email};
}
