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
# Contributor(s): Erik Stambaugh <erik@dasbistro.com>
#                 Gervase Markham <gerv@gerv.net>

use strict;

BEGIN {
    use lib qw(lib .);
    use Bugzilla;
    Bugzilla->extensions;
}

use lib qw(. lib);

use Bugzilla;
use Bugzilla::User;
use Bugzilla::Mailer;
use Bugzilla::Extension::RequestWhiner::Constants;

my $dbh = Bugzilla->dbh;

my $sth_get_requests =
    $dbh->prepare("SELECT profiles.login_name,
                          flagtypes.name,
                          flags.attach_id,
                          bugs.bug_id, 
                          bugs.short_desc, " .
                          $dbh->sql_to_days('NOW()') . 
                            " - " .
                          $dbh->sql_to_days('flags.modification_date') . "
                       AS age_in_days
                     FROM flags 
                     JOIN bugs ON bugs.bug_id = flags.bug_id, 
                          flagtypes, 
                          profiles 
                    WHERE flags.status = '?' 
                      AND flags.requestee_id = profiles.userid 
                      AND flags.type_id = flagtypes.id 
                      AND " . $dbh->sql_to_days('NOW()') . 
                              " - " .
                              $dbh->sql_to_days('flags.modification_date') . 
                              " > " .
                              WHINE_AFTER_DAYS . "
                 ORDER BY flags.modification_date");

$sth_get_requests->execute();

# Build data structure
my $requests = {};
    
while (my ($login_name,
           $flag_name, 
           $attach_id,
           $bug_id, 
           $short_desc, 
           $age_in_days) = $sth_get_requests->fetchrow_array()) 
{
    if (!defined($requests->{$login_name})) {
        $requests->{$login_name} = {};
    }
    
    if (!defined($requests->{$login_name}->{$flag_name})) {
        $requests->{$login_name}->{$flag_name} = [];
    }
        
    push(@{ $requests->{$login_name}->{$flag_name} }, {
        bug_id    => $bug_id,
        attach_id => $attach_id,
        summary   => $short_desc,
        age       => $age_in_days
    });
}

$sth_get_requests->finish();

foreach my $recipient (keys %$requests) {
    my $user = new Bugzilla::User({ name => $recipient });

    next if $user->email_disabled;

    mail({
        from      => Bugzilla->params->{'mailfrom'},
        recipient => $user,
        subject   => "Your Outstanding Requests",
        requests  => $requests->{$recipient},
        threshold => WHINE_AFTER_DAYS
    });
}

exit;

###############################################################################
# Functions
#
# Note: this function is exactly the same as the one in whine.pl, just using
# different templates for the messages themselves.
###############################################################################
sub mail {
    my $args = shift;
    my $addressee = $args->{recipient};

    my $template = 
           Bugzilla->template_inner($addressee->settings->{'lang'}->{'value'});
    my $msg = ''; # it's a temporary variable to hold the template output
    $args->{'alternatives'} ||= [];

    # Put together the different multipart MIME segments
    $template->process("requestwhiner/mail.txt.tmpl", $args, \$msg)
        or die($template->error());
    push @{$args->{'alternatives'}},
        {
            'content' => $msg,
            'type'    => 'text/plain',
        };
    $msg = '';

    $template->process("requestwhiner/mail.html.tmpl", $args, \$msg)
        or die($template->error());
    push @{$args->{'alternatives'}},
        {
            'content' => $msg,
            'type'    => 'text/html',
        };
    $msg = '';

    # Now produce a ready-to-mail MIME-encoded message
    $args->{'boundary'} = "----------" . $$ . "--" . time() . "-----";

    $template->process("whine/multipart-mime.txt.tmpl", $args, \$msg)
        or die($template->error());

    MessageToMTA($msg);

    delete $args->{'boundary'};
    delete $args->{'alternatives'};
}
