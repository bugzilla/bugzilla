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
# The Initial Developer of the Original Code is Netscape Communications
# Corporation. Portions created by Netscape are
# Copyright (C) 1998 Netscape Communications Corporation. All
# Rights Reserved.
#
# Contributor(s): Dave Miller <justdave@syndicomm.com>
#                 Joel Peshkin <bugreport@peshkin.net>
#                 Jacob Steenhagen <jake@bugzilla.org>
#                 Vlad Dascalu <jocuri@softhome.net>
#                 Frédéric Buclin <LpSolit@gmail.com>

# Code derived from editowners.cgi and editusers.cgi

use strict;
use lib ".";

use Bugzilla;
use Bugzilla::Constants;
require "CGI.pl";

my $dbh = Bugzilla->dbh;

use vars qw($template $vars);

Bugzilla->login(LOGIN_REQUIRED);

print Bugzilla->cgi->header();

if (!UserInGroup("creategroups")) {
    PutHeader("Not Authorized","Edit Groups","","Not Authorized for this function!");
    print "<H1>Sorry, you aren't a member of the 'creategroups' group.</H1>\n";
    print "And so, you aren't allowed to edit the groups.\n";
    print "<p>\n";
    PutFooter();
    exit;
}

my $action  = trim($::FORM{action} || '');
my $back = "<BR>Click the <b>Back</b> button and try again.";

# RederiveRegexp: update user_group_map with regexp-based grants
sub RederiveRegexp ($$)
{
    my $regexp = shift;
    my $gid = shift;
    my $dbh = Bugzilla->dbh;
    my $sth = $dbh->prepare("SELECT userid, login_name FROM profiles");
    my $sthadd = $dbh->prepare("INSERT IGNORE INTO user_group_map
                               (user_id, group_id, grant_type, isbless)
                               VALUES (?, ?, ?, 0)");
    my $sthdel = $dbh->prepare("DELETE FROM user_group_map
                                WHERE user_id = ? AND group_id = ?
                                AND grant_type = ? and isbless = 0");
    $sth->execute();
    while (my ($uid, $login) = $sth->fetchrow_array()) {
        if (($regexp =~ /\S+/) && ($login =~ m/$regexp/i))
        {
            $sthadd->execute($uid, $gid, GRANT_REGEXP);
        } else {
            $sthdel->execute($uid, $gid, GRANT_REGEXP);
        }
    }
}

sub ShowError ($)
{
    my $msgtext = shift;
    print "<TABLE BGCOLOR=\"#FF0000\" CELLPADDING=15><TR><TD>";
    print "<B>$msgtext</B>";
    print "</TD></TR></TABLE><P>";
    return 1;
}

#
# Displays a text like "a.", "a or b.", "a, b or c.", "a, b, c or d."
#

sub PutTrailer (@)
{
    my (@links) = ("Back to the <a href=\"./\">index</a>", @_);
    SendSQL("UNLOCK TABLES");

    my $count = $#links;
    my $num = 0;
    print "<P>\n";
    foreach (@links) {
        print $_;
        if ($num == $count) {
            print ".\n";
        }
        elsif ($num == $count-1) {
            print " or ";
        }
        else {
            print ", ";
        }
        $num++;
    }
    PutFooter();
}

# CheckGroupID checks that a positive integer is given and is
# actually a valid group ID. If all tests are successful, the
# trimmed group ID is returned.

sub CheckGroupID {
    my ($group_id) = @_;
    $group_id = trim($group_id || 0);
    if (!$group_id) {
        ShowError("No group was specified." . $back);
        PutFooter();
        exit;
    }
    unless (detaint_natural($group_id)
              && Bugzilla->dbh->selectrow_array("SELECT id FROM groups WHERE id = ?",
                                                undef, $group_id))
    {
        ShowError("The group you specified does not exist." . $back);
        PutFooter();
        exit;
    }
    return $group_id;
}

# This subroutine is called when:
# - a new group is created. CheckGroupName checks that its name
#   is not empty and is not already used by any existing group.
# - an existing group is edited. CheckGroupName checks that its
#   name has not been deleted or renamed to another existing
#   group name (whose group ID is different from $group_id).
# In both cases, an error message is returned to the user if any
# test fails! Else, the trimmed group name is returned.

sub CheckGroupName {
    my ($name, $group_id) = @_;
    $name = trim($name || '');
    trick_taint($name);
    if (!$name) {
        ShowError("Please enter a group name." . $back);
        PutFooter();
        exit;
    }
    my $excludeself = (defined $group_id) ? " AND id != $group_id" : "";
    my $name_exists = Bugzilla->dbh->selectrow_array("SELECT name FROM groups " .
                                                     "WHERE name = ? $excludeself",
                                                     undef, $name);
    if ($name_exists) {
        ShowError("The <em>" . html_quote($name) . "</em> group already exists." . $back);
        PutFooter();
        exit;
    }
    return $name;
}

# CheckGroupDesc checks that a non empty description is given. The
# trimmed description is returned.

sub CheckGroupDesc {
    my ($desc) = @_;
    $desc = trim($desc || '');
    trick_taint($desc);
    if (!$desc) {
        ShowError("Please enter a group description." . $back);
        PutFooter();
        exit;
    }
    return $desc;
}

# CheckGroupRegexp checks that the regular expression is valid
# (the regular expression being optional, the test is successful
# if none is given, as expected). The trimmed regular expression
# is returned.

sub CheckGroupRegexp {
    my ($regexp) = @_;
    $regexp = trim($regexp || '');
    trick_taint($regexp);
    if (!eval {qr/$regexp/}) {
        ShowError("The regular expression you entered is invalid." . $back);
        PutFooter();
        exit;
    }
    return $regexp;
}

# If no action is specified, get a list of all groups available.

unless ($action) {
    PutHeader("Edit Groups","Edit Groups","This lets you edit the groups available to put users in.");

    print "<table border=1>\n";
    print "<tr>";
    print "<th>Name</th>";
    print "<th>Description</th>";
    print "<th>User RegExp</th>";
    print "<th>Use For Bugs</th>";
    print "<th>Type</th>";
    print "<th>Action</th>";
    print "</tr>\n";

    SendSQL("SELECT id,name,description,userregexp,isactive,isbuggroup " .
            "FROM groups " .
            "ORDER BY isbuggroup, name");

    while (MoreSQLData()) {
        my ($groupid, $name, $desc, $regexp, $isactive, $isbuggroup) = FetchSQLData();
        print "<tr>\n";
        print "<td>" . html_quote($name) . "</td>\n";
        print "<td>" . html_quote($desc) . "</td>\n";
        print "<td>" . html_quote($regexp) . "&nbsp</td>\n";
        print "<td align=center>";
        print "X" if (($isactive != 0) && ($isbuggroup != 0));
        print "&nbsp</td>\n";
        print "<td> &nbsp ";
        print (($isbuggroup == 0 ) ? "system" : "user"); 
        print "&nbsp</td>\n";
        print "<td align=center valign=middle>
               <a href=\"editgroups.cgi?action=changeform&group=$groupid\">Edit</a>";
        print " | <a href=\"editgroups.cgi?action=del&group=$groupid\">Delete</a>" if ($isbuggroup != 0);
        print "</td></tr>\n";
    }

    print "<tr>\n";
    print "<td colspan=5></td>\n";
    print "<td><a href=\"editgroups.cgi?action=add\">Add Group</a></td>\n";
    print "</tr>\n";
    print "</table>\n";
    print "<p>";
    print "<b>Name</b> is what is used with the UserInGroup() function in any
customized cgi files you write that use a given group.  It can also be used by
people submitting bugs by email to limit a bug to a certain set of groups. <p>";
    print "<b>Description</b> is what will be shown in the bug reports to
members of the group where they can choose whether the bug will be restricted
to others in the same group.<p>";
    print "<b>User RegExp</b> is optional, and if filled in, will automatically
grant membership to this group to anyone with an
email address that matches this perl regular expression. Do not forget the trailing \'\$\'.  Example \'\@mycompany\\.com\$\'<p>";
    print "The <b>Use For Bugs</b> flag determines whether or not the group is eligible to be used for bugs.
If you remove this flag, it will no longer be possible for users to add bugs
to this group, although bugs already in the group will remain in the group.
Doing so is a much less drastic way to stop a group from growing
than deleting the group as well as a way to maintain lists of users without cluttering the lists of groups used for bug restrictions.<p>";
    print "The <b>Type</b> field identifies system groups.<p>";  

    PutFooter();
    exit;
}

#
#
# action='changeform' -> present form for altering an existing group
#
# (next action will be 'postchanges')
#

if ($action eq 'changeform') {
    PutHeader("Change Group");

    # Check that an existing group ID is given
    my $group_id = CheckGroupID($::FORM{'group'});
    my ($name, $description, $rexp, $isactive, $isbuggroup) =
        $dbh->selectrow_array("SELECT name, description, userregexp, " .
                              "isactive, isbuggroup " .
                              "FROM groups WHERE id = ?", undef, $group_id);

    print "<FORM METHOD=POST ACTION=editgroups.cgi>\n";
    print "<TABLE BORDER=1 CELLPADDING=4>";
    print "<TR><TH>Group:</TH><TD>";
    if ($isbuggroup == 0) {
        print html_quote($name);
    } else {
        print "<INPUT TYPE=HIDDEN NAME=\"oldname\" VALUE=\"" . 
        html_quote($name) . "\">
        <INPUT SIZE=60 NAME=\"name\" VALUE=\"" . html_quote($name) . "\">";
    }
    print "</TD></TR><TR><TH>Description:</TH><TD>";
    if ($isbuggroup == 0) {
        print html_quote($description);
    } else {
        print "<INPUT TYPE=HIDDEN NAME=\"olddesc\" VALUE=\"" .
        html_quote($description) . "\">
        <INPUT SIZE=70 NAME=\"desc\" VALUE=\"" . 
            html_quote($description) . "\">";
    }
    print "</TD></TR><TR>
           <TH>User Regexp:</TH><TD>";
    print "<INPUT TYPE=HIDDEN NAME=\"oldrexp\" VALUE=\"" . 
           html_quote($rexp) . "\">
           <INPUT SIZE=40 NAME=\"rexp\" VALUE=\"" . 
           html_quote($rexp) . "\"></TD></TR>";
    if ($isbuggroup == 1) {
        print "<TR><TH>Use For Bugs:</TH><TD>
        <INPUT TYPE=checkbox NAME =\"isactive\" VALUE=1 " . (($isactive == 1) ? "CHECKED" : "") . ">
        <INPUT TYPE=HIDDEN NAME=\"oldisactive\" VALUE=$isactive>
        </TD>
        </TR>";
    }
    print "</TABLE>
           <BR>
           Users become members of this group in one of three ways:
           <BR>
           - by being explicity included when the user is edited
           <BR>
           - by matching the user regexp above
           <BR>
           - by being a member of one of the groups included in this group
           by checking the boxes  
           below. <P>\n";

    print "<TABLE>";
    print "<TR><TD COLSPAN=4>Members of these groups can grant membership to this group</TD></TR>";
    print "<TR><TD ALIGN=CENTER>|</TD><TD COLSPAN=3>Members of these groups are included in this group</TD></TR>";
    print "<TR><TD ALIGN=CENTER>|</TD><TD ALIGN=CENTER>|</TD><TD COLSPAN=2></TD><TR>";

    # For each group, we use left joins to establish the existence of
    # a record making that group a member of this group
    # and the existence of a record permitting that group to bless
    # this one
    SendSQL("SELECT groups.id, groups.name, groups.description," .
             " group_group_map.member_id IS NOT NULL," .
             " B.member_id IS NOT NULL" .
             " FROM groups" .
             " LEFT JOIN group_group_map" .
             " ON group_group_map.member_id = groups.id" .
             " AND group_group_map.grantor_id = $group_id" .
             " AND group_group_map.isbless = 0" .
             " LEFT JOIN group_group_map as B" .
             " ON B.member_id = groups.id" .
             " AND B.grantor_id = $group_id" .
             " AND B.isbless = 1" .
             " WHERE groups.id != $group_id ORDER by name");

    while (MoreSQLData()) {
        my ($grpid, $grpnam, $grpdesc, $grpmember, $blessmember) = FetchSQLData();
        my $grpchecked = $grpmember ? "CHECKED" : "";
        my $blesschecked = $blessmember ? "CHECKED" : "";
        print "<TR>";
        print "<TD><INPUT TYPE=checkbox NAME=\"bless-$grpid\" $blesschecked VALUE=1>";
        print "<INPUT TYPE=HIDDEN NAME=\"oldbless-$grpid\" VALUE=$blessmember></TD>";
        print "<TD><INPUT TYPE=checkbox NAME=\"grp-$grpid\" $grpchecked VALUE=1>";
        print "<INPUT TYPE=HIDDEN NAME=\"oldgrp-$grpid\" VALUE=$grpmember></TD>";
        print "<TD><B>" . html_quote($grpnam) . "</B></TD>";
        print "<TD>" . html_quote($grpdesc) . "</TD>";
        print "</TR>\n";
    }

    print "</TABLE><BR>";
    print "<INPUT TYPE=SUBMIT VALUE=\"Submit\">\n";
    print <<EOF;
<table width="76%" border="1">
  <tr>
    <td><p><strong>Conversion of groups created with Bugzilla versions 2.16 and
        prior:</strong></p>
          <ul>
            <li>Remove all explicit memberships from this group: 
              <input name="remove_explicit_members" type="submit" id="remove_explicit_members" value="Remove Memberships">
</li>
            <li>Remove all explicit memberships that are included in the above
            regular expression: 
              <input name="remove_explicit_members_regexp" type="submit" id="remove_explicit_members_regexp" value="Remove memberships included in regular expression"> 
            </li>
          </ul>          <p><br>            
              </p>
      </p></td>
  </tr>
</table>
<BR>
EOF
    print "<INPUT TYPE=HIDDEN NAME=\"action\" VALUE=\"postchanges\">\n";
    print "<INPUT TYPE=HIDDEN NAME=\"group\" VALUE=$group_id>\n";
    print "</FORM>";



    PutTrailer("back to the <a href=\"editgroups.cgi\">group list</a>");
    exit;
}

#
# action='add' -> present form for parameters for new group
#
# (next action will be 'new')
#

if ($action eq 'add') {
    print Bugzilla->cgi->header();

    $template->process("admin/groups/create.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
    
    exit;
}



#
# action='new' -> add group entered in the 'action=add' screen
#

if ($action eq 'new') {
    PutHeader("Adding new group");

    # Check that a not already used group name is given, that
    # a description is also given and check if the regular
    # expression is valid (if any).
    my $name = CheckGroupName($::FORM{'name'});
    my $desc = CheckGroupDesc($::FORM{'desc'});
    my $regexp = CheckGroupRegexp($::FORM{'regexp'});
    my $isactive = $::FORM{isactive} ? 1 : 0;

    # Add the new group
    SendSQL("INSERT INTO groups ( " .
            "name, description, isbuggroup, userregexp, isactive, last_changed " .
            " ) VALUES ( " .
            SqlQuote($name) . ", " .
            SqlQuote($desc) . ", " .
            "1," .
            SqlQuote($regexp) . ", " . 
            $isactive . ", NOW())" );
    SendSQL("SELECT last_insert_id()");
    my $gid = FetchOneColumn();
    my $admin = GroupNameToId('admin');
    SendSQL("INSERT INTO group_group_map (member_id, grantor_id, isbless)
             VALUES ($admin, $gid, 0)");
    SendSQL("INSERT INTO group_group_map (member_id, grantor_id, isbless)
             VALUES ($admin, $gid, 1)");
    # Permit all existing products to use the new group if makeproductgroups.
    if ($::FORM{insertnew}) {
        SendSQL("INSERT INTO group_control_map " .
                "(group_id, product_id, entry, membercontrol, " .
                "othercontrol, canedit) " .
                "SELECT $gid, products.id, 0, " .
                CONTROLMAPSHOWN . ", " .
                CONTROLMAPNA . ", 0 " .
                "FROM products");
    }
    RederiveRegexp($regexp, $gid);
    print "OK, done.<p>\n";
    PutTrailer("<a href=\"editgroups.cgi?action=add\">add</a> another group",
               "back to the <a href=\"editgroups.cgi\">group list</a>");
    exit;
}

#
# action='del' -> ask if user really wants to delete
#
# (next action would be 'delete')
#

if ($action eq 'del') {
    PutHeader("Delete group");
    # Check that an existing group ID is given
    my $gid = CheckGroupID($::FORM{'group'});
    my ($name, $desc, $isbuggroup) =
        $dbh->selectrow_array("SELECT name, description, isbuggroup " .
                              "FROM groups WHERE id = ?", undef, $gid);

    # System groups cannot be deleted!
    if (!$isbuggroup) {
        ShowError("<em>" . html_quote($name) . "</em> is a system group.
                   This group cannot be deleted." . $back);
        PutFooter();
        exit;
    }

    print "<table border=1>\n";
    print "<tr>";
    print "<th>Id</th>";
    print "<th>Name</th>";
    print "<th>Description</th>";
    print "</tr>\n";
    print "<tr>\n";
    print "<td>$gid</td>\n";
    print "<td>$name</td>\n";
    print "<td>$desc</td>\n";
    print "</tr>\n";
    print "</table>\n";

    print "<FORM METHOD=POST ACTION=editgroups.cgi>\n";
    my $cantdelete = 0;
    SendSQL("SELECT user_id FROM user_group_map 
             WHERE group_id = $gid AND isbless = 0");
    if (!FetchOneColumn()) {} else {
       $cantdelete = 1;
       print "
<B>One or more users belong to this group. You cannot delete this group while
there are users in it.</B><BR>
<A HREF=\"editusers.cgi?action=list&group=$gid\">Show me which users.</A> - <INPUT TYPE=CHECKBOX NAME=\"removeusers\">Remove all users from
this group for me<P>
";
    }
    SendSQL("SELECT bug_id FROM bug_group_map WHERE group_id = $gid");
    my $buglist="";
    if (MoreSQLData()) {
        $cantdelete = 1;
        my $buglist = "0";
        while (MoreSQLData()) {
            my ($bug) = FetchSQLData();
            $buglist .= "," . $bug;
        }
       print "
<B>One or more bug reports are visible only to this group.
You cannot delete this group while any bugs are using it.</B><BR>
<A HREF=\"buglist.cgi?bug_id=$buglist\">Show me which bugs.</A> -
<INPUT TYPE=CHECKBOX NAME=\"removebugs\">Remove all bugs from this group
restriction for me<BR>
<B>NOTE:</B> It's quite possible to make confidential bugs public by checking
this box.  It is <B>strongly</B> suggested that you review the bugs in this
group before checking the box.<P>
";
    }
    SendSQL("SELECT name FROM products WHERE name=" . SqlQuote($name));
    if (MoreSQLData()) {
       $cantdelete = 1;
       print "
<B>This group is tied to the <U>$name</U> product.
You cannot delete this group while it is tied to a product.</B><BR>
<INPUT TYPE=CHECKBOX NAME=\"unbind\">Delete this group anyway, and make the
<U>$name</U> product publicly visible.<BR>
";
    }

    print "<H2>Confirmation</H2>\n";
    print "<P>Do you really want to delete this group?\n";
    if ($cantdelete) {
      print "<BR><B>You must check all of the above boxes or correct the " .
            "indicated problems first before you can proceed.</B>";
    }
    print "<P><INPUT TYPE=SUBMIT VALUE=\"Yes, delete\">\n";
    print "<INPUT TYPE=HIDDEN NAME=\"action\" VALUE=\"delete\">\n";
    print "<INPUT TYPE=HIDDEN NAME=\"group\" VALUE=\"$gid\">\n";
    print "</FORM>";

    PutTrailer("<a href=editgroups.cgi>No, go back to the group list</a>");
    exit;
}

#
# action='delete' -> really delete the group
#

if ($action eq 'delete') {
    PutHeader("Deleting group");
    # Check that an existing group ID is given
    my $gid = CheckGroupID($::FORM{'group'});
    my ($name, $isbuggroup) =
        $dbh->selectrow_array("SELECT name, isbuggroup FROM groups " .
                              "WHERE id = ?", undef, $gid);

    # System groups cannot be deleted!
    if (!$isbuggroup) {
        ShowError("<em>" . html_quote($name) . "</em> is a system group.
                   This group cannot be deleted." . $back);
        PutFooter();
        exit;
    }

    my $cantdelete = 0;

    SendSQL("SELECT user_id FROM user_group_map 
             WHERE group_id = $gid AND isbless = 0");
    if (FetchOneColumn()) {
      if (!defined $::FORM{'removeusers'}) {
        $cantdelete = 1;
      }
    }
    SendSQL("SELECT bug_id FROM bug_group_map WHERE group_id = $gid");
    if (FetchOneColumn()) {
      if (!defined $::FORM{'removebugs'}) {
        $cantdelete = 1;
      }
    }
    SendSQL("SELECT name FROM products WHERE name=" . SqlQuote($name));
    if (FetchOneColumn()) {
      if (!defined $::FORM{'unbind'}) {
        $cantdelete = 1;
      }
    }

    if ($cantdelete == 1) {
      ShowError("This group cannot be deleted because there are " .
          "records in the database which refer to it.  All such records " .
          "must be removed or altered to remove the reference to this " .
          "group before the group can be deleted.");
      print "<a href=\"editgroups.cgi?action=del&group=$gid\">" .
            "View</a> the list of which records are affected.<br>";
      PutTrailer("back to the <a href=\"editgroups.cgi\">group list</a>");
      exit;
    }

    SendSQL("DELETE FROM user_group_map WHERE group_id = $gid");
    SendSQL("DELETE FROM group_group_map WHERE grantor_id = $gid");
    SendSQL("DELETE FROM bug_group_map WHERE group_id = $gid");
    SendSQL("DELETE FROM group_control_map WHERE group_id = $gid");
    SendSQL("DELETE FROM groups WHERE id = $gid");
    print "<B>Group $gid has been deleted.</B><BR>";


    PutTrailer("back to the <a href=\"editgroups.cgi\">group list</a>");
    exit;
}

#
# action='postchanges' -> update the groups
#

if ($action eq 'postchanges') {

    # ZLL: Bug 181589: we need to have something to remove explictly listed users from
    # groups in order for the conversion to 2.18 groups to work
    if ($::FORM{remove_explicit_members}) {
        PutHeader("Confirm: Remove All Explicit Members?");
        my ($gid, $chgs) = doGroupChanges();
        print "<br><br>\n";
        if ($chgs) {
            print "Group updated, please confirm removal:<p>\n";
        }
        confirmRemove(0,$gid);
        PutFooter();
        exit;
    } elsif ($::FORM{remove_explicit_members_regexp}) {
        PutHeader("Confirm: Remove Explicit Members in the Regular Expression?");
        my ($gid, $chgs, $rexp) = doGroupChanges();
        print "<br><br>\n";
        if ($chgs) {
            print "Group updated, please confirm removal:<p>\n";
        }
        confirmRemove(1, $gid, $rexp);
        PutFooter();
        exit;
    }
    
   # if we got this far, the admin doesn't want to convert, so just save their changes
   
    PutHeader("Updating group hierarchy");
    my ($gid, $chgs) = doGroupChanges();
    
    if (!$chgs) {
        print "You didn't change anything!<BR>\n";
        print "If you really meant it, hit the <B>Back</B> button and try again.<p>\n";
    } else {
        print "Done.<p>\n";
    }
    PutTrailer("back to the <a href=\"editgroups.cgi\">group list</a>");
    exit;
}

if (($action eq 'remove_all_regexp') || ($action eq 'remove_all')) {
    # remove all explicit users from the group with gid = $::FORM{group} 
    # that match the regexp stored in the db for that group 
    # or all of them period
    my $gid = CheckGroupID($::FORM{'group'});

    my $sth = $dbh->prepare("SELECT name, userregexp FROM groups
                             WHERE id = ?");
    $sth->execute($gid);
    my ($name, $regexp) = $sth->fetchrow_array();
    if ($action eq 'remove_all_regexp') {
        PutHeader("Removing All Explicit Group Memberships Matching "
                . "Group RegExp from \'" . html_quote($name) . "\'");
    } else {
        PutHeader("Removing All Explicit Group Memberships from \'"
                . html_quote($name) . "\'");
    }
    $dbh->do("LOCK TABLES
                  groups WRITE,
                  profiles READ,
                  user_group_map WRITE");
    $sth = $dbh->prepare("SELECT user_group_map.user_id, profiles.login_name
                             FROM user_group_map, profiles
                             WHERE user_group_map.user_id = profiles.userid
                             AND user_group_map.group_id = ?
                             AND grant_type = ?
                             AND isbless = 0");
    $sth->execute($gid, GRANT_DIRECT);
    my $sth2 = $dbh->prepare("DELETE FROM user_group_map
                              WHERE user_id = ?
                              AND isbless = 0
                              AND group_id = ?");
    if ($action eq 'remove_all_regexp') {
        print "<br><b>Removing explicit memberships of users matching \'"
              . html_quote($regexp) . "\'...</b><br>\n";
    } else {
        print "<br><b>Removing explicit membership</b><br>\n";
    }
    while ( my ($userid, $userlogin) = $sth->fetchrow_array() ) {
        if ((($regexp =~ /\S/) && ($userlogin =~ m/$regexp/i))
            || ($action eq 'remove_all'))
        {
            $sth2->execute($userid,$gid);
            print html_quote($userlogin) . " removed<br>\n";
        }
    }
    print "<br><b>Done</b><br>";

    $sth = $dbh->prepare("UPDATE groups
             SET last_changed = NOW()
             WHERE id = ?");
    $sth->execute($gid);
    PutTrailer("back to the <a href=\"editgroups.cgi\">group list</a>");
    exit;
}




#
# No valid action found
#

PutHeader("Error");
print "I don't have a clue what you want.<BR>\n";

PutTrailer("<a href=editgroups.cgi>Try the group list</a>");

# confirm if the user wants to remove the explicit users
sub confirmRemove {
    my ($remove_regexp_only, $group, $regexp) = @_;
    
    if (!$remove_regexp_only) { 
        print "This option will remove ";
        print "all explicitly defined users ";
    } elsif ($regexp =~ /\S/) { 
        print "This option will remove ";
        print "all users included in the regular expression: " . 
              html_quote($regexp) . " ";
    } else {
        print "<b>There is no regular expression defined.</b>\n";
        print "No users will be removed<p>\n";
        print "<a href=\"editgroups.cgi\">return to the Edit Groups page</a>\n";
        return;
    }
    print "from group $::FORM{name}.<p>\n";
    print "Generally, you will only need to do this when upgrading groups ";
    print "created with Bugzilla versions 2.16 and prior. Use this option ";
    print "with <b>extreme care</b> and consult the Bugzilla Guide for ";
    print "further information.<p>\n";
    
    print "<FORM METHOD=POST ACTION=editgroups.cgi>\n";
    print "<INPUT TYPE=HIDDEN NAME=\"group\" VALUE=$group>\n";
    
    if ($remove_regexp_only) {
        print "<INPUT TYPE=HIDDEN NAME=\"action\" VALUE=\"remove_all_regexp\">\n";
    } else {
        print "<INPUT TYPE=HIDDEN NAME=\"action\" VALUE=\"remove_all\">\n";
    }
    
    print "<INPUT NAME=\"confirm\" TYPE=SUBMIT VALUE=\"Confirm\">\n";
    print "<p>Or <a href=\"editgroups.cgi\">return to the Edit Groups page</a>\n";
    print "</FORM>";
}

# Helper sub to handle the making of changes to a group
sub doGroupChanges {
    my $dbh = Bugzilla->dbh;
    my $sth;

    $dbh->do("LOCK TABLES groups WRITE, group_group_map WRITE,
              user_group_map WRITE, profiles READ");

    # Check that the given group ID and regular expression are valid.
    # If tests are successful, trimmed values are returned by CheckGroup*.
    my $gid = CheckGroupID($::FORM{'group'});
    my $regexp = CheckGroupRegexp($::FORM{'rexp'});

    # The name and the description of system groups cannot be edited.
    # We then need to know if the group being edited is a system group.
    SendSQL("SELECT isbuggroup FROM groups WHERE id = $gid");
    my ($isbuggroup) = FetchSQLData();
    my $name;
    my $desc;
    my $isactive;
    my $chgs = 0;

    # We trust old values given by the template. If they are hacked
    # in a way that some of the tests below become negative, the
    # corresponding attributes are not updated in the DB, which does
    # not hurt.
    if ($isbuggroup) {
        # Check that the group name and its description are valid
        # and return trimmed values if tests are successful.
        $name = CheckGroupName($::FORM{'name'}, $gid);
        $desc = CheckGroupDesc($::FORM{'desc'});
        $isactive = $::FORM{'isactive'} ? 1 : 0;

        if ($name ne $::FORM{"oldname"}) {
            $chgs = 1;
            $sth = $dbh->do("UPDATE groups SET name = ? WHERE id = ?",
                            undef, $name, $gid);
        }
        if ($desc ne $::FORM{"olddesc"}) {
            $chgs = 1;
            $sth = $dbh->do("UPDATE groups SET description = ? WHERE id = ?",
                            undef, $desc, $gid);
        }
        if ($isactive ne $::FORM{"oldisactive"}) {
            $chgs = 1;
            $sth = $dbh->do("UPDATE groups SET isactive = ? WHERE id = ?",
                            undef, $isactive, $gid);
        }
    }
    if ($regexp ne $::FORM{"oldrexp"}) {
        $chgs = 1;
        $sth = $dbh->do("UPDATE groups SET userregexp = ? WHERE id = ?",
                        undef, $regexp, $gid);
        RederiveRegexp($regexp, $gid);
    }

    print "Checking....";
    foreach my $b (grep(/^oldgrp-\d*$/, keys %::FORM)) {
        if (defined($::FORM{$b})) {
            my $v = substr($b, 7);
            my $grp = $::FORM{"grp-$v"} || 0;
            if ($::FORM{"oldgrp-$v"} != $grp) {
                $chgs = 1;
                print "changed";
                if ($grp != 0) {
                    print " set ";
                    SendSQL("INSERT INTO group_group_map 
                             (member_id, grantor_id, isbless)
                             VALUES ($v, $gid, 0)");
                } else {
                    print " cleared ";
                    SendSQL("DELETE FROM group_group_map
                             WHERE member_id = $v AND grantor_id = $gid
                             AND isbless = 0");
                }
            }

            my $bless = $::FORM{"bless-$v"} || 0;
            if ($::FORM{"oldbless-$v"} != $bless) {
                $chgs = 1;
                print "changed";
                if ($bless != 0) {
                    print " set ";
                    SendSQL("INSERT INTO group_group_map 
                             (member_id, grantor_id, isbless)
                             VALUES ($v, $gid, 1)");
                } else {
                    print " cleared ";
                    SendSQL("DELETE FROM group_group_map
                             WHERE member_id = $v AND grantor_id = $gid
                             AND isbless = 1");
                }
            }

        }
    }
    
    if ($chgs) {
        # mark the changes
        SendSQL("UPDATE groups SET last_changed = NOW() WHERE id = $gid");
    }
    $dbh->do("UNLOCK TABLES");
    return $gid, $chgs, $regexp;
}
