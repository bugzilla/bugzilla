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
# The Initial Developer of the Original Code is Frédéric Buclin.
# Portions created by Frédéric Buclin are Copyright (C) 2007
# Frédéric Buclin. All Rights Reserved.
#
# Contributor(s): Frédéric Buclin <LpSolit@gmail.com>

use strict;

use lib qw(.);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Token;

my $cgi = Bugzilla->cgi;
my $dbh = Bugzilla->dbh;
my $user = Bugzilla->login(LOGIN_REQUIRED);

print $cgi->header();

$user->in_group('admin')
  || ThrowUserError('auth_failure', {group  => 'admin',
                                     action => 'modify',
                                     object => 'workflow'});

my $action = $cgi->param('action') || 'edit';
my $token = $cgi->param('token');

sub get_statuses {
    my $statuses = $dbh->selectall_arrayref('SELECT id, value, is_open FROM bug_status
                                             ORDER BY sortkey, value', { Slice => {} });
    return $statuses;
}

sub get_workflow {
    my $workflow = $dbh->selectall_arrayref('SELECT old_status, new_status, require_comment
                                             FROM status_workflow');
    my %workflow;
    foreach my $row (@$workflow) {
        my ($old, $new, $type) = @$row;
        $workflow{$old || 0}{$new} = $type;
    }
    return \%workflow;
}

sub load_template {
    my ($filename, $message) = @_;
    my $template = Bugzilla->template;
    my $vars = {};

    $vars->{'statuses'} = get_statuses();
    $vars->{'workflow'} = get_workflow();
    $vars->{'token'} = issue_session_token("workflow_$filename");
    $vars->{'message'} = $message;

    $template->process("admin/workflow/$filename.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
    exit;
}

if ($action eq 'edit') {
    load_template('edit');
}
elsif ($action eq 'update') {
    check_token_data($token, 'workflow_edit');
    my $statuses = get_statuses;
    my $workflow = get_workflow();
    my $initial_state = {id => 0};

    my $sth_insert = $dbh->prepare('INSERT INTO status_workflow (old_status, new_status)
                                    VALUES (?, ?)');
    my $sth_delete = $dbh->prepare('DELETE FROM status_workflow
                                    WHERE old_status = ? AND new_status = ?');
    my $sth_delnul = $dbh->prepare('DELETE FROM status_workflow
                                    WHERE old_status IS NULL AND new_status = ?');

    foreach my $old ($initial_state, @$statuses) {
        # Hashes cannot have undef as a key, so we use 0. But the DB
        # must store undef, for referential integrity.
        my $old_id_for_db = $old->{'id'} || undef;
        foreach my $new (@$statuses) {
            next if $old->{'id'} == $new->{'id'};

            if ($cgi->param('w_' . $old->{'id'} . '_' . $new->{'id'})) {
                $sth_insert->execute($old_id_for_db, $new->{'id'})
                  unless defined $workflow->{$old->{'id'}}->{$new->{'id'}};
            }
            elsif ($old_id_for_db) {
                $sth_delete->execute($old_id_for_db, $new->{'id'});
            }
            else {
                $sth_delnul->execute($new->{'id'});
            }
        }
    }
    delete_token($token);
    load_template('edit', 'workflow_updated');
}
elsif ($action eq 'edit_comment') {
    load_template('comment');
}
elsif ($action eq 'update_comment') {
    check_token_data($token, 'workflow_comment');
    my $workflow = get_workflow();

    my $sth_update = $dbh->prepare('UPDATE status_workflow SET require_comment = ?
                                    WHERE old_status = ? AND new_status = ?');
    my $sth_updnul = $dbh->prepare('UPDATE status_workflow SET require_comment = ?
                                    WHERE old_status IS NULL AND new_status = ?');

    foreach my $old (keys %$workflow) {
        # Hashes cannot have undef as a key, so we use 0. But the DB
        # must store undef, for referential integrity.
        my $old_id_for_db = $old || undef;
        foreach my $new (keys %{$workflow->{$old}}) {
            my $comment_required = $cgi->param("c_${old}_$new") ? 1 : 0;
            next if ($workflow->{$old}->{$new} == $comment_required);
            if ($old_id_for_db) {
                $sth_update->execute($comment_required, $old_id_for_db, $new);
            }
            else {
                $sth_updnul->execute($comment_required, $new);
            }
        }
    }
    delete_token($token);
    load_template('comment', 'workflow_updated');
}
else {
    ThrowCodeError("action_unrecognized", {action => $action});
}
