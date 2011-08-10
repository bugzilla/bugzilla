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
# The Original Code is the Profanivore Bugzilla Extension.
#
# The Initial Developer of the Original Code is the Mozilla Foundation.
# Portions created by the Initial Developer are Copyright (C) 2010 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Gervase Markham <gerv@gerv.net>

package Bugzilla::Extension::Profanivore;
use strict;
use base qw(Bugzilla::Extension);

use Regexp::Common 'RE_ALL';

our $VERSION = '0.01';

sub bug_format_comment {
    my ($self, $args) = @_;
    my $regexes = $args->{'regexes'};
    my $comment = $args->{'comment'};
  
    # Censor profanities if the comment author is not reasonably trusted.
    # However, allow people to see their own profanities, which might stop
    # them immediately noticing and trying to go around the filter. (I.e.
    # it tries to stop an arms race starting.)
    if ($comment &&
        !$comment->author->in_group('editbugs') &&
        $comment->author->id != Bugzilla->user->id) 
    {
        push (@$regexes, {
            match => RE_profanity(),
            replace => \&_replace_profanity
        });
    }
}

sub _replace_profanity {
    # We don't have access to the actual profanity.
    return "****";
}

sub mailer_before_send {
    my ($self, $args) = @_;
    my $email = $args->{'email'};
    
    my $author    = $email->header("X-Bugzilla-Who");
    my $recipient = $email->header("To");
    
    if ($author && $recipient) {
        my $email_suffix = Bugzilla->params->{'emailsuffix'};
        if ($email_suffix ne '') {
            $recipient =~ s/\Q$email_suffix\E$//;
            $author    =~ s/\Q$email_suffix\E$//;
        }
        
        $author    = new Bugzilla::User({ name => $author });
        $recipient = new Bugzilla::User({ name => $recipient });
    
        if ($author->id && 
            !$author->in_group('editbugs') &&
            $author->id ne $recipient->id) 
        {
            my $body = $email->body_str();

            my $offensive = RE_profanity();
            $body =~ s/$offensive/****/g;

            $email->body_str_set($body);
        }
    }
}

__PACKAGE__->NAME;
