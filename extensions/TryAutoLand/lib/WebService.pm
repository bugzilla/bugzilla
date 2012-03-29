# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::TryAutoLand::WebService;

use strict;
use warnings;

use base qw(Bugzilla::WebService);

use Bugzilla::Error;
use Bugzilla::Util qw(trick_taint);

use Bugzilla::Extension::TryAutoLand::Constants;

use constant READ_ONLY => qw(
    getBugs 
);

# TryAutoLand.getBugs
# Params: status - List of statuses to filter attachments (only 'waiting' is default)
# Returns: List of bugs, each being a hash of data needed by the AutoLand polling server
# Params
# [ { bug_id => $bug_id1, attachments => [ $attach_id1, $attach_id2 ] }, branches => $branchListFromTextField ... ]

sub getBugs { 
    my ($self, $params) = @_;
    my $user = Bugzilla->user;
    my $dbh  = Bugzilla->dbh;
    my %bugs;

    if ($user->login ne WEBSERVICE_USER) {
        ThrowUserError("auth_failure", { action => "access",
                                         object => "autoland_attachments" });
    }

    my $status_where  = "AND status = 'waiting'";
    my $status_values = [];
    if (exists $params->{'status'}) {
        my $statuses = ref $params->{'status'}
                       ? $params->{'status'}
                       : [ $params->{'status'} ];
        foreach my $status (@$statuses) {
            if (grep($_ eq $status, VALID_STATUSES)) {
                trick_taint($status);
                push(@$status_values, $status);
            }
        }
        if (@$status_values) {
            my @qmarks = ("?") x @$status_values;
            $status_where = "AND " . $dbh->sql_in('status', \@qmarks);
        }
        
    }

    my $attachments = $dbh->selectall_arrayref("
        SELECT attachments.bug_id, 
               attachments.attach_id, 
               autoland_attachments.who, 
               autoland_attachments.status,
               autoland_attachments.status_when 
          FROM attachments, autoland_attachments 
         WHERE attachments.attach_id = autoland_attachments.attach_id
               $status_where
      ORDER BY attachments.bug_id",
        undef, @$status_values);

    foreach my $row (@$attachments) {
        my ($bug_id, $attach_id, $al_who, $al_status, $al_status_when) = @$row;

        my $al_user = Bugzilla::User->new($al_who);

        # Silent Permission checks
        next if !$user->can_see_bug($bug_id);
        my $attachment = Bugzilla::Attachment->new($attach_id);
        next if !$attachment 
                || $attachment->isobsolete 
                || ($attachment->isprivate && !$user->is_insider);

        $bugs{$bug_id} = {} if !exists $bugs{$bug_id};

        if (!$bugs{$bug_id}{'branches'}) {
            my $bug_result = $dbh->selectrow_hashref("SELECT branches, try_syntax
                                                        FROM autoland_branches 
                                                       WHERE bug_id = ?", 
                                                     undef, $bug_id);
            $bugs{$bug_id}{'branches'}   = $bug_result->{'branches'};
            $bugs{$bug_id}{'try_syntax'} = $bug_result->{'try_syntax'};
        }
      
        $bugs{$bug_id}{'attachments'} = [] if !exists $bugs{$bug_id}{'attachments'};

        push(@{$bugs{$bug_id}{'attachments'}}, {
            id          => $self->type('int', $attach_id),  
            who         => $self->type('string', $al_user->login), 
            status      => $self->type('string', $al_status), 
            status_when => $self->type('dateTime', $al_status_when), 
        });
    }

    return [ 
        map 
        { { bug_id => $_, attachments => $bugs{$_}{'attachments'}, 
            branches => $bugs{$_}{'branches'}, try_syntax => $bugs{$_}{'try_syntax'} } }
        keys %bugs 
    ];
}

# TryAutoLand.update({ attach_id => $attach_id, action => $action, status => $status })
# Let's BMO know if a patch has landed or not and BMO will update the auto_land table accordingly
# If $action eq 'status', $status will be a predetermined set of status values -- when waiting, 
# the UI for submitting autoland will be locked and once complete status update occurs or the 
# mapping is removed, the UI can be unlocked for the $attach_id
# Allowed statuses: waiting, running, failed, or success
#
# If $action eq 'remove', the attach_id will be removed from the mapping table and the UI
# will be unlocked for the $attach_id.

sub update { 
    my ($self, $params) = @_;
    my $user = Bugzilla->user;
    my $dbh  = Bugzilla->dbh;

    if ($user->login ne WEBSERVICE_USER) {
        ThrowUserError("auth_failure", { action => "modify",
                                         object => "autoland_attachments" });
    }

    foreach my $param ('attach_id', 'action') {
        defined $params->{$param}
            || ThrowCodeError('param_required', 
                              { param => $param });
    }

    my $action    = delete $params->{'action'};
    my $attach_id = delete $params->{'attach_id'};
    my $status    = delete $params->{'status'};

    if ($action eq 'status' && !$status) {
        ThrowCodeError('param_required', { param => 'status' });
    }

    grep($_ eq $action, ('remove', 'status'))
        || ThrowUserError('autoland_update_invalid_action',  
                          { action => $action, 
                            valid  => ["remove", "status"] });

    my $attachment = Bugzilla::Attachment->new($attach_id);
    $attachment
        || ThrowUserError('autoland_invalid_attach_id',
                          { attach_id => $attach_id });
   
    # Loud Permission checks
    if (!$user->can_see_bug($attachment->bug_id)) {
        ThrowUserError("bug_access_denied", { bug_id => $attachment->bug_id });
    }
    if ($attachment->isprivate && !$user->is_insider) {
        ThrowUserError('auth_failure', { action    => 'access',
                                         object    => 'attachment',
                                         attach_id => $attachment->id });
    }

    $attachment->autoland_checked 
        || ThrowUserError('autoland_invalid_attach_id',
                          { attach_id => $attach_id });

    if ($action eq 'status') {
        # Update the status
        $attachment->autoland_update_status($status);

        return { 
            id          => $self->type('int', $attachment->id),
            who         => $self->type('string', $attachment->autoland_who->login),
            status      => $self->type('string', $attachment->autoland_status),
            status_when => $self->type('dateTime', $attachment->autoland_status_when),
        };
    }
    elsif ($action eq 'remove') {
        $attachment->autoland_remove();    
    }

    return {};
}

1;
