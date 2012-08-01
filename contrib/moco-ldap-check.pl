#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/..";
use lib "$Bin/../lib";

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Group;
use Bugzilla::Mailer;
use Data::Dumper;
use File::Slurp;
use Getopt::Long;
use Net::LDAP;
use Safe;

#

use constant BUGZILLA_IGNORE => <<'EOF';
    infra+bot@mozilla.com    # Mozilla Infrastructure Bot
    qa-auto@mozilla.com      # QA Desktop Automation
    qualys@mozilla.com       # Qualys Security Scanner
    recruiting@mozilla.com   # Recruiting
    release@mozilla.com      # Mozilla RelEng Bot
    sumo-dev@mozilla.com     # SUMOdev [:sumodev]
    airmozilla@mozilla.com   # Air Mozilla
    ux-review@mozilla.com
    release-mgmt@mozilla.com
    reps@mozilla.com
    moz_bug_r_a4@mozilla.com # Security contractor
    nightwatch@mozilla.com   # Security distribution list for whines
EOF

use constant LDAP_IGNORE => <<'EOF';
    airmozilla@mozilla.com  # Air Mozilla
EOF

# REPORT_SENDER has to be a valid @mozilla.com LDAP account
use constant REPORT_SENDER => 'bjones@mozilla.com';

use constant BMO_RECIPIENTS => qw(
    glob@mozilla.com
    dkl@mozilla.com
);

use constant SUPPORT_RECIPIENTS => qw(
    desktop@mozilla.com
);

#

my ($ldap_host, $ldap_user, $ldap_pass, $debug, $no_update);
GetOptions('h=s' => \$ldap_host,
           'u=s' => \$ldap_user,
           'p=s' => \$ldap_pass,
           'd'   => \$debug,
           'n'   => \$no_update);
die "syntax: -h ldap_host -u ldap_user -p ldap_pass\n"
    unless $ldap_host && $ldap_user && $ldap_pass;

my $data_dir = bz_locations()->{'datadir'} . '/moco-ldap-check';
mkdir($data_dir) unless -d $data_dir;

if ($ldap_user !~ /,/) {
    $ldap_user = "mail=$ldap_user,o=com,dc=mozilla";
}

#
# group members
#

my @bugzilla_ignore;
foreach my $line (split(/\n/, BUGZILLA_IGNORE)) {
    $line =~ s/^([^#]+)#.*$/$1/;
    $line =~ s/(^\s+|\s+$)//g;
    push @bugzilla_ignore, clean_email($line);
}

my @bugzilla_moco;
if ($no_update && -s "$data_dir/bugzilla_moco.last") {
    $debug && print "Using cached user list from Bugzilla...\n";
    my $ra = deserialise("$data_dir/bugzilla_moco.last");
    @bugzilla_moco = @$ra;
} else {
    $debug && print "Getting user list from Bugzilla...\n";

    my $group = Bugzilla::Group->new({ name => 'mozilla-corporation' })
        or die "Failed to find group mozilla-corporation\n";

    foreach my $user (@{ $group->members_non_inherited }) {
        next unless $user->is_enabled;
        my $mail = clean_email($user->login);
        my $name = trim($user->name);
        $name =~ s/\s+/ /g;
        next if grep { $mail eq $_ } @bugzilla_ignore;
        push @bugzilla_moco, {
            mail => $user->login,
            canon => $mail,
            name => $name,
        };
    }

    @bugzilla_moco = sort { $a->{mail} cmp $b->{mail} } @bugzilla_moco;
    serialise("$data_dir/bugzilla_moco.last", \@bugzilla_moco);
}

#
# build list of current mo-co bugmail accounts
#

my @ldap_ignore;
foreach my $line (split(/\n/, LDAP_IGNORE)) {
    $line =~ s/^([^#]+)#.*$/$1/;
    $line =~ s/(^\s+|\s+$)//g;
    push @ldap_ignore, canon_email($line);
}

my %ldap;
if ($no_update && -s "$data_dir/ldap.last") {
    $debug && print "Using cached user list from LDAP...\n";
    my $rh = deserialise("$data_dir/ldap.last");
    %ldap = %$rh;
} else {
    $debug && print "Logging into LDAP as $ldap_user...\n";
    my $ldap = Net::LDAP->new($ldap_host,
        scheme => 'ldaps', onerror => 'die') or die "$@";
    $ldap->bind($ldap_user, password => $ldap_pass);
    foreach my $ldap_base ('o=com,dc=mozilla', 'o=org,dc=mozilla') {
        $debug && print "Getting user list from LDAP $ldap_base...\n";
        my $result = $ldap->search(
            base   => $ldap_base,
            scope  => 'sub',
            filter => '(mail=*)',
            attrs  => ['mail', 'bugzillaEmail', 'emailAlias', 'cn', 'employeeType'],
        );
        foreach my $entry ($result->entries) {
            my ($name, $bugMail, $mail, $type) =
                map { $entry->get_value($_) || '' }
                qw(cn bugzillaEmail mail employeeType);
            next if $type eq 'DISABLED';
            $mail = lc $mail;
            next if grep { $_ eq canon_email($mail) } @ldap_ignore;
            $bugMail = '' if $bugMail !~ /\@/;
            $bugMail =~ s/(^\s+|\s+$)//g;
            if ($bugMail =~ / /) {
                $bugMail = (grep { /\@/ } split / /, $bugMail)[0];
            }
            $name =~ s/\s+/ /g;
            $ldap{$mail}{name} = trim($name);
            $ldap{$mail}{bugmail} = $bugMail;
            $ldap{$mail}{bugmail_canon} = canon_email($bugMail);
            $ldap{$mail}{aliases} = [];
            foreach my $alias (
                @{$entry->get_value('emailAlias', asref => 1) || []}
            ) {
                push @{$ldap{$mail}{aliases}}, canon_email($alias);
            }
        }
        $debug && printf "Found %s entries\n", scalar($result->entries);
    }
    serialise("$data_dir/ldap.last", \%ldap);
}

#
# validate all bugmail entries from the phonebook
#

my %bugzilla_login;
if ($no_update && -s "$data_dir/bugzilla_login.last") {
    $debug && print "Using cached bugzilla checks...\n";
    my $rh = deserialise("$data_dir/bugzilla_login.last");
    %bugzilla_login = %$rh;
} else {
    my %logins;
    foreach my $mail (keys %ldap) {
        $logins{$mail} = 1;
        $logins{$ldap{$mail}{bugmail}} = 1 if $ldap{$mail}{bugmail};
    }
    my @logins = sort keys %logins;
    $debug && print "Checking " . scalar(@logins) . " bugmail accounts...\n";

    foreach my $login (@logins) {
        if (Bugzilla::User->new({ name => $login })) {
            $bugzilla_login{$login} = 1;
        }
    }
    serialise("$data_dir/bugzilla_login.last", \%bugzilla_login);
}

#
# load previous ldap list
#

my %ldap_old;
{
    my $rh = deserialise("$data_dir/ldap.data");
    %ldap_old = %$rh if $rh;
}

#
# save current ldap list
#

{
    serialise("$data_dir/ldap.data", \%ldap);
}

#
# new ldap accounts
#

my @new_ldap;
{
    foreach my $mail (sort keys %ldap) {
        next if exists $ldap_old{$mail};
        push @new_ldap, {
            mail => $mail,
            name => $ldap{$mail}{name},
            bugmail => $ldap{$mail}{bugmail},
        };
    }
}

#
# deleted ldap accounts
#

my @gone_ldap_bmo;
my @gone_ldap_no_bmo;
{
    foreach my $mail (sort keys %ldap_old) {
        next if exists $ldap{$mail};
        if ($ldap_old{$mail}{bugmail}) {
            push @gone_ldap_bmo, {
                mail => $mail,
                name => $ldap_old{$mail}{name},
                bugmail => $ldap_old{$mail}{bugmail},
            }
        } else {
            push @gone_ldap_no_bmo, {
                mail => $mail,
                name => $ldap_old{$mail}{name},
            }
        }
    }
}

#
# check bugmail entry for all users in bmo/moco group
#

my @suspect_bugzilla;
my @invalid_bugzilla;
foreach my $rh (@bugzilla_moco) {
    my @check = ($rh->{mail}, $rh->{canon});
    if ($rh->{mail} =~ /^([^\@]+)\@mozilla\.org$/) {
        push @check, "$1\@mozilla.com";
    }

    my $exists;
    foreach my $check (@check) {
        $exists = 0;

        # don't complain about deleted accounts
        if (grep { $_->{mail} eq $check } (@gone_ldap_bmo, @gone_ldap_no_bmo)) {
            $exists = 1;
            last;
        }

        # check for matching bugmail entry
        foreach my $mail (sort keys %ldap) {
            next unless $ldap{$mail}{bugmail_canon} eq $check;
            $exists = 1;
            last;
        }
        last if $exists;

        # check for matching mail
        $exists = 0;
        foreach my $mail (sort keys %ldap) {
            next unless $mail eq $check;
            $exists = 1;
            last;
        }
        last if $exists;

        # check for matching email alias
        $exists = 0;
        foreach my $mail (sort keys %ldap) {
            next unless grep { $check eq $_ } @{$ldap{$mail}{aliases}};
            $exists = 1;
            last;
        }
        last if $exists;
    }

    if (!$exists) {
        # flag the account
        if ($rh->{mail} =~ /\@mozilla\.(com|org)$/i) {
            push @invalid_bugzilla, {
                mail => $rh->{mail},
                name => $rh->{name},
            };
        } else {
            push @suspect_bugzilla, {
                mail => $rh->{mail},
                name => $rh->{name},
            };
        }
    }
}

#
# check bugmail entry for ldap users
#

my @ldap_unblessed;
my @invalid_ldap;
my @invalid_bugmail;
foreach my $mail (sort keys %ldap) {
    # try to find the bmo account
    my $found;
    foreach my $address ($ldap{$mail}{bugmail}, $ldap{$mail}{bugmail_canon}, $mail, @{$ldap{$mail}{aliases}}) {
        if (exists $bugzilla_login{$address}) {
            $found = $address;
            last;
        }
    }

    # not on bmo
    if (!$found) {
        # if they have specified a bugmail account, warn, otherwise ignore
        if ($ldap{$mail}{bugmail}) {
            if (grep { $_->{canon} eq $ldap{$mail}{bugmail_canon} } @bugzilla_moco) {
                push @invalid_bugmail, {
                    mail => $mail,
                    name => $ldap{$mail}{name},
                    bugmail => $ldap{$mail}{bugmail},
                };
            } else {
                push @invalid_ldap, {
                    mail => $mail,
                    name => $ldap{$mail}{name},
                    bugmail => $ldap{$mail}{bugmail},
                };
            }
        }
        next;
    }

    # warn about mismatches
    if ($ldap{$mail}{bugmail} && $found ne $ldap{$mail}{bugmail}) {
        push @invalid_bugmail, {
            mail => $mail,
            name => $ldap{$mail}{name},
            bugmail => $ldap{$mail}{bugmail},
        };
    }

    # warn about unblessed accounts
    if ($mail =~ /\@mozilla\.com$/) {
        unless (grep { $_->{mail} eq $found || $_->{canon} eq canon_email($found) } @bugzilla_moco) {
            push @ldap_unblessed, {
                mail => $mail,
                name => $ldap{$mail}{name},
                bugmail => $ldap{$mail}{bugmail} || $mail,
            };
        }
    }
}

#
# reports
#

my @bmo_report;
push @bmo_report, generate_report(
    'new ldap accounts',
    'no action required',
    @new_ldap);

push @bmo_report, generate_report(
    'deleted ldap accounts',
    'disable bmo account',
    @gone_ldap_bmo);

push @bmo_report, generate_report(
    'deleted ldap accounts',
    'no action required (no bmo account)',
    @gone_ldap_no_bmo);

push @bmo_report, generate_report(
    'suspect bugzilla accounts',
    'remove from mo-co if required',
    @suspect_bugzilla);

push @bmo_report, generate_report(
    'miss-configured bugzilla accounts',
    'ask owner to update phonebook, disable if not on phonebook',
    @invalid_bugzilla);

push @bmo_report, generate_report(
    'ldap accounts without mo-co group',
    'verify, and add mo-co group to bmo account',
    @ldap_unblessed);

push @bmo_report, generate_report(
    'missmatched bugmail entries on ldap accounts',
    'ask owner to update phonebook',
    @invalid_bugmail);

push @bmo_report, generate_report(
    'invalid bugmail entries on ldap accounts',
    'ask owner to update phonebook',
    @invalid_ldap);

if (!scalar @bmo_report) {
    push @bmo_report, '**';
    push @bmo_report, '** nothing to report \o/';
    push @bmo_report, '**';
}

email_report(\@bmo_report, 'moco-ldap-check', BMO_RECIPIENTS);

my @support_report;

push @support_report, generate_report(
    'Missmatched "Bugzilla Email" entries on LDAP accounts',
    'Ask owner to update phonebook, or update directly',
    @invalid_bugmail);

push @support_report, generate_report(
    'Invalid "Bugzilla Email" entries on LDAP accounts',
    'Ask owner to update phonebook',
    @invalid_ldap);

if (scalar @support_report) {
    email_report(\@support_report, 'Invalid "Bugzilla Email" entries in LDAP', SUPPORT_RECIPIENTS);
}

#
#
#

sub generate_report {
    my ($title, $action, @lines) = @_;

    my $count = scalar @lines;
    return unless $count;

    my @report;
    push @report, '';
    push @report, '**';
    push @report, "** $title ($count)";
    push @report, "** [ $action ]";
    push @report, '**';
    push @report, '';

    my $max_length = 0;
    foreach my $rh (@lines) {
        $max_length = length($rh->{mail}) if length($rh->{mail}) > $max_length;
    }

    foreach my $rh (@lines) {
        my $template = "%-${max_length}s  %s";
        my @fields = ($rh->{mail}, $rh->{name});

        if ($rh->{bugmail}) {
            $template .= ' (%s)';
            push @fields, $rh->{bugmail};
        };

        push @report, sprintf($template, @fields);
    }

    return @report;
}

sub email_report {
    my ($report, $subject, @recipients) = @_;
    unshift @$report, (
        "Subject: $subject",
        'X-Bugzilla-Type: moco-ldap-check',
        'From: ' . REPORT_SENDER,
        'To: ' . join(',', @recipients),
    );
    if ($debug) {
        print "\n", join("\n", @$report), "\n";
    } else {
        MessageToMTA(join("\n", @$report));
    }
}

sub clean_email {
    my $email = shift;
    $email = trim($email);
    $email = $1 if $email =~ /^(\S+)/;
    $email =~ s/&#64;/@/;
    $email = lc $email;
    return $email;
}

sub canon_email {
    my $email = shift;
    $email = clean_email($email);
    $email =~ s/^([^\+]+)\+[^\@]+(\@.+)$/$1$2/;
    return $email;
}

sub trim {
    my $value = shift;
    $value =~ s/(^\s+|\s+$)//g;
    return $value;
}

sub serialise {
    my ($filename, $ref) = @_;
    local $Data::Dumper::Purity = 1;
    local $Data::Dumper::Deepcopy = 1;
    local $Data::Dumper::Sortkeys = 1;
    write_file($filename, Dumper($ref));
}

sub deserialise {
    my ($filename) = @_;
    return unless -s $filename;
    my $cpt = Safe->new();
    $cpt->reval('our ' . read_file($filename))
        || die "$!";
    return ${$cpt->varglob('VAR1')};
}

