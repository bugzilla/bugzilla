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
# Corporation. Portions created by Mozilla are
# Copyright (C) 2006 Mozilla Foundation. All Rights Reserved.
#
# Contributor(s): Myk Melez <myk@mozilla.org>
#                 Alex Brugh <alex@cs.umn.edu>
#                 Dave Miller <justdave@mozilla.com>
#                 Byron Jones <glob@mozilla.com>

use strict;

use lib qw(.);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Util;

use Getopt::Long;

my $dbh = Bugzilla->dbh;

# This SQL is designed to sanitize a copy of a Bugzilla database so that it
# doesn't contain any information that can't be viewed from a web browser by
# a user who is not logged in.

# Last validated against Bugzilla version 4.0

my ($dry_run, $from_cron, $keep_attachments, $keep_groups,
    $keep_passwords, $keep_insider, $trace, $enable_email) = (0, 0, 0, '', 0, 0, 0, 0);
my $keep_groups_sql = '';

GetOptions(
    "dry-run" => \$dry_run,
    "from-cron" => \$from_cron,
    "keep-attachments" => \$keep_attachments,
    "keep-passwords" => \$keep_passwords,
    "keep-insider" => \$keep_insider,
    "keep-groups:s" => \$keep_groups,
    "trace" => \$trace,
    "enable-email" => \$enable_email,
) or exit;

if ($keep_groups ne '') {
    my @groups;
    foreach my $group_id (split(/\s*,\s*/, $keep_groups)) {
        my $group;
        if ($group_id =~ /\D/) {
            $group = Bugzilla::Group->new({ name => $group_id });
        } else {
            $group = Bugzilla::Group->new($group_id);
        }
        die "Invalid group '$group_id'\n" unless $group;
        push @groups, $group->id;
    }
    $keep_groups_sql = "NOT IN (" . join(",", @groups) . ")";
}

$dbh->{TraceLevel} = 1 if $trace;

if ($dry_run) {
    print "** dry run : no changes to the database will be made **\n";
    $dbh->bz_start_transaction();
}
eval {
    delete_non_public_products();
    delete_secure_bugs();
    delete_insider_comments() unless $keep_insider;
    delete_security_groups();
    delete_sensitive_user_data();
    delete_attachment_data() unless $keep_attachments;
    disable_email_delivery() unless $enable_email;
    print "All done!\n";
    $dbh->bz_rollback_transaction() if $dry_run;
};
if ($@) {
    $dbh->bz_rollback_transaction() if $dry_run;
    die "$@" if $@;
}

sub delete_non_public_products {
    # Delete all non-public products, and all data associated with them
    my @products = Bugzilla::Product->get_all();
    my $mandatory = CONTROLMAPMANDATORY;
    foreach my $product (@products) {
        # if there are any mandatory groups on the product, nuke it and
        # everything associated with it (including the bugs)
        Bugzilla->params->{'allowbugdeletion'} = 1; # override this in memory for now
        my $mandatorygroups = $dbh->selectcol_arrayref("SELECT group_id FROM group_control_map WHERE product_id = ? AND (membercontrol = $mandatory)", undef, $product->id);
        if (0 < scalar(@$mandatorygroups)) {
            print "Deleting product '" . $product->name . "'...\n";
            $product->remove_from_db();
        }
    }
}

sub delete_secure_bugs {
    # Delete all data for bugs in security groups.
    my $buglist = $dbh->selectall_arrayref(
        $keep_groups
        ? "SELECT DISTINCT bug_id FROM bug_group_map  WHERE group_id $keep_groups_sql"
        : "SELECT DISTINCT bug_id FROM bug_group_map"
    );
    $|=1; # disable buffering so the bug progress counter works
    my $numbugs = scalar(@$buglist);
    my $bugnum = 0;
    print "Deleting $numbugs bugs in " . ($keep_groups ? 'non-' : '') . "security groups...\n";
    foreach my $row (@$buglist) {
        my $bug_id = $row->[0];
        $bugnum++;
        print "\r$bugnum/$numbugs" unless $from_cron;
        my $bug = new Bugzilla::Bug($bug_id);
        $bug->remove_from_db();
    }
    print "\rDone            \n" unless $from_cron;
}

sub delete_insider_comments {
    # Delete all 'insidergroup' comments and attachments
    print "Deleting 'insidergroup' comments and attachments...\n";
    $dbh->do("DELETE FROM longdescs WHERE isprivate = 1");
    $dbh->do("DELETE attach_data FROM attachments JOIN attach_data ON attachments.attach_id = attach_data.id WHERE attachments.isprivate = 1");
    $dbh->do("DELETE FROM attachments WHERE isprivate = 1");
    $dbh->do("UPDATE bugs_fulltext SET comments = comments_noprivate");
}

sub delete_security_groups {
    # Delete all security groups.
    print "Deleting " . ($keep_groups ? 'non-' : '') . "security groups...\n";
    $dbh->do("DELETE user_group_map FROM groups JOIN user_group_map ON groups.id = user_group_map.group_id WHERE groups.isbuggroup = 1");
    $dbh->do("DELETE group_group_map FROM groups JOIN group_group_map ON (groups.id = group_group_map.member_id OR groups.id = group_group_map.grantor_id) WHERE groups.isbuggroup = 1");
    $dbh->do("DELETE group_control_map FROM groups JOIN group_control_map ON groups.id = group_control_map.group_id WHERE groups.isbuggroup = 1");
    $dbh->do("UPDATE flagtypes LEFT JOIN groups ON flagtypes.grant_group_id = groups.id SET grant_group_id = NULL WHERE groups.isbuggroup = 1");
    $dbh->do("UPDATE flagtypes LEFT JOIN groups ON flagtypes.request_group_id = groups.id SET request_group_id = NULL WHERE groups.isbuggroup = 1");
    if ($keep_groups) {
        $dbh->do("DELETE FROM groups WHERE isbuggroup = 1 AND id $keep_groups_sql");
    } else {
        $dbh->do("DELETE FROM groups WHERE isbuggroup = 1");
    }
}

sub delete_sensitive_user_data {
    # Remove sensitive user account data.
    print "Deleting sensitive user account data...\n";
    $dbh->do("UPDATE profiles SET cryptpassword = 'deleted'") unless $keep_passwords;
    $dbh->do("DELETE FROM profiles_activity");
    $dbh->do("DELETE FROM profile_search");
    $dbh->do("DELETE FROM namedqueries");
    $dbh->do("DELETE FROM tokens");
    $dbh->do("DELETE FROM logincookies");
    $dbh->do("DELETE FROM login_failure");
    $dbh->do("DELETE FROM audit_log");
    # queued bugmail
    $dbh->do("DELETE FROM ts_error");
    $dbh->do("DELETE FROM ts_exitstatus");
    $dbh->do("DELETE FROM ts_funcmap");
    $dbh->do("DELETE FROM ts_job");
    $dbh->do("DELETE FROM ts_note");
    # push extension messages
    $dbh->do("DELETE FROM push");
    $dbh->do("DELETE FROM push_backlog");
    $dbh->do("DELETE FROM push_backoff");
    $dbh->do("DELETE FROM push_log");
    $dbh->do("DELETE FROM push_options");
}

sub delete_attachment_data {
    # Delete unnecessary attachment data.
    print "Removing attachment data to preserve disk space...\n";
    $dbh->do("UPDATE attach_data SET thedata = ''");
}

sub disable_email_delivery {
    # turn off email delivery for all users.
    print "Turning off email delivery...\n";
    $dbh->do("UPDATE profiles SET disable_mail = 1");

    # Also clear out the default flag cc as well since they do not
    # have to be in the profiles table
    $dbh->do("UPDATE flagtypes SET cc_list = NULL");
}
