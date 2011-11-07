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
# The Original Code is the REMO Bugzilla Extension.
#
# The Initial Developer of the Original Code is Mozilla Foundation 
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Byron Jones <glob@mozilla.com>
#   David Lawrence <dkl@mozilla.com>

package Bugzilla::Extension::REMO;
use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::Constants;
use Bugzilla::Util qw(trick_taint trim detaint_natural);
use Bugzilla::Token;
use Bugzilla::Error;

our $VERSION = '0.01';

sub page_before_template {
    my ($self, $args) = @_;
    my $page = $args->{'page_id'};
    my $vars = $args->{'vars'};

    if ($page eq 'remo-form-payment.html') {
        _remo_form_payment($vars);
    }
}

sub _remo_form_payment {
    my ($vars) = @_;
    my $input = Bugzilla->input_params;

    my $user = Bugzilla->login(LOGIN_REQUIRED);

    if ($input->{'action'} eq 'commit') {
        my $template = Bugzilla->template;
        my $cgi      = Bugzilla->cgi;
        my $dbh      = Bugzilla->dbh;

        my $bug_id = $input->{'bug_id'};
        detaint_natural($bug_id);
        my $bug = Bugzilla::Bug->check($bug_id);

        # Detect if the user already used the same form to submit again
        my $token = trim($input->{'token'});
        if ($token) {
            my ($creator_id, $date, $old_attach_id) = Bugzilla::Token::GetTokenData($token);
            if (!$creator_id 
                || $creator_id != $user->id 
                || $old_attach_id !~ "^remo_form_payment:")
            {
                # The token is invalid.
                ThrowUserError('token_does_not_exist');
            }

            $old_attach_id =~ s/^remo_form_payment://;
            if ($old_attach_id) {
                ThrowUserError('remo_payment_cancel_dupe', 
                               { bugid => $bug_id, attachid => $old_attach_id });
            }
        }

        # Make sure the user can attach to this bug
        if (!$bug->user->{'canedit'}) {
            ThrowUserError("remo_payment_bug_edit_denied", 
                           { bug_id => $bug->id });
        }

        # Make sure the bug is under the correct product/component
        if ($bug->product ne 'Mozilla Reps' 
            || $bug->component ne 'Budget Requests') 
        {
            ThrowUserError('remo_payment_invalid_product');    
        }

        my ($timestamp) = $dbh->selectrow_array("SELECT NOW()");

        $dbh->bz_start_transaction;
    
        # Create the comment to be added based on the form fields from rep-payment-form
        my $comment;
        $template->process("pages/comment-remo-form-payment.txt.tmpl", $vars, \$comment)
            || ThrowTemplateError($template->error());
        $bug->add_comment($comment, { isprivate => 0 });

        # Attach expense report
        # FIXME: Would be nice to be able to have the above prefilled comment and
        # the following attachments all show up under a single comment. But the longdescs
        # table can only handle one attach_id per comment currently. At least only one
        # email is sent the way it is done below.
        my $attachment;
        if (defined $cgi->upload('expenseform')) {
            # Determine content-type
            my $content_type = $cgi->uploadInfo($cgi->param('expenseform'))->{'Content-Type'};
 
            $attachment = Bugzilla::Attachment->create(
                { bug           => $bug, 
                  creation_ts   => $timestamp, 
                  data          => $cgi->upload('expenseform'), 
                  description   => 'Expense Form', 
                  filename      => scalar $cgi->upload('expenseform'), 
                  ispatch       => 0, 
                  isprivate     => 0, 
                  isurl         => 0, 
                  mimetype      => $content_type, 
                  store_in_file => 0, 
            });

            # Insert comment for attachment
            $bug->add_comment('', { isprivate  => 0, 
                                    type       => CMT_ATTACHMENT_CREATED, 
                                    extra_data => $attachment->id });
        }

        # Attach receipts file
        if (defined $cgi->upload("receipts")) {
            # Determine content-type
            my $content_type = $cgi->uploadInfo($cgi->param("receipts"))->{'Content-Type'};

            $attachment = Bugzilla::Attachment->create(
                { bug           => $bug, 
                  creation_ts   => $timestamp, 
                  data          => $cgi->upload('receipts'), 
                  description   => "Receipts", 
                  filename      => scalar $cgi->upload("receipts"), 
                  ispatch       => 0, 
                  isprivate     => 0, 
                  isurl         => 0, 
                  mimetype      => $content_type, 
                  store_in_file => 0, 
            });

            # Insert comment for attachment
            $bug->add_comment('', { isprivate  => 0, 
                                    type       => CMT_ATTACHMENT_CREATED, 
                                    extra_data => $attachment->id });
        }

        $bug->update($timestamp);

        if ($token) {
            trick_taint($token);
            $dbh->do('UPDATE tokens SET eventdata = ? WHERE token = ?', undef,
                     ("remo_form_payment:" . $attachment->id, $token));
        }

        $dbh->bz_commit_transaction;
    
        # Define the variables and functions that will be passed to the UI template.
        $vars->{'attachment'} = $attachment;
        $vars->{'bugs'} = [ new Bugzilla::Bug($bug_id) ];
        $vars->{'header_done'} = 1;
        $vars->{'contenttypemethod'} = 'autodetect';
 
        my $recipients = { 'changer' => $user };
        $vars->{'sent_bugmail'} = Bugzilla::BugMail::Send($bug_id, $recipients);
        
        print $cgi->header();
        # Generate and return the UI (HTML page) from the appropriate template.
        $template->process("attachment/created.html.tmpl", $vars)
            || ThrowTemplateError($template->error()); 
        exit;
    }
    else {
        $vars->{'token'} = issue_session_token('remo_form_payment:');
    }
}

sub post_bug_after_creation {
    my ($self, $args) = @_;
    my $vars = $args->{vars};
    my $bug = $vars->{bug};
    my $template = Bugzilla->template;

    if (Bugzilla->input_params->{format}
        && Bugzilla->input_params->{format} eq 'remo-swag') 
    {
        # If the attachment cannot be successfully added to the bug,
        # we notify the user, but we don't interrupt the bug creation process.
        my $error_mode_cache = Bugzilla->error_mode;
        Bugzilla->error_mode(ERROR_MODE_DIE);
        
        my $attachment;
        eval {
            my $xml;
            $template->process("bug/create/create-remo-swag.xml.tmpl", {}, \$xml)
                || ThrowTemplateError($template->error());

            $attachment = Bugzilla::Attachment->create(
                { bug           => $bug, 
                  creation_ts   => $bug->creation_ts, 
                  data          => $xml,
                  description   => 'Remo Swag Request (XML)', 
                  filename      => 'remo-swag.xml',
                  ispatch       => 0, 
                  isprivate     => 0, 
                  isurl         => 0, 
                  mimetype      => 'text/xml',
                  store_in_file => 0, 
            });
        };

        if ($attachment) {
            # Insert comment for attachment
            $bug->add_comment('', { isprivate  => 0, 
                                    type       => CMT_ATTACHMENT_CREATED, 
                                    extra_data => $attachment->id });
            $bug->update($bug->creation_ts);
        }
        else {
            $vars->{'message'} = 'attachment_creation_failed';
        }
       
        Bugzilla->error_mode($error_mode_cache);
    }
}

__PACKAGE__->NAME;
