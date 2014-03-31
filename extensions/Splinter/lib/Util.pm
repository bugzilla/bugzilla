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
# The Original Code is the Splinter Bugzilla Extension.
#
# The Initial Developer of the Original Code is Red Hat, Inc.
# Portions created by Red Hat, Inc. are Copyright (C) 2009
# Red Hat Inc. All Rights Reserved.
#
# Contributor(s):
#   Owen Taylor <otaylor@fishsoup.net>

package Bugzilla::Extension::Splinter::Util;

use strict;

use Bugzilla;
use Bugzilla::Util;

use base qw(Exporter);

@Bugzilla::Extension::Splinter::Util::EXPORT = qw(
    attachment_is_visible
    attachment_id_is_patch
    get_review_base
    get_review_url
    get_review_link
    add_review_links_to_email
);

# Validates an attachment ID.
# Takes a parameter containing the ID to be validated.
# If the second parameter is true, the attachment ID will be validated,
# however the current user's access to the attachment will not be checked.
# Will return false if 1) attachment ID is not a valid number,
# 2) attachment does not exist, or 3) user isn't allowed to access the
# attachment.
#
# Returns an attachment object.
# Based on code from attachment.cgi
sub attachment_id_is_valid {
    my ($attach_id, $dont_validate_access) = @_;

    # Validate the specified attachment id. 
    detaint_natural($attach_id) || return 0;

    # Make sure the attachment exists in the database.
    my $attachment = new Bugzilla::Attachment({ id => $attach_id, cache => 1 })
      || return 0;

    return $attachment 
        if ($dont_validate_access || attachment_is_visible($attachment));
}

# Checks if the current user can see an attachment
# Based on code from attachment.cgi
sub attachment_is_visible {
    my $attachment = shift;

    $attachment->isa('Bugzilla::Attachment') || return 0;

    return (Bugzilla->user->can_see_bug($attachment->bug->id) 
            && (!$attachment->isprivate 
                || Bugzilla->user->id == $attachment->attacher->id 
                || Bugzilla->user->is_insider));
}

sub attachment_id_is_patch {
    my $attach_id = shift;
    my $attachment = attachment_id_is_valid($attach_id);

    return ($attachment && $attachment->ispatch);
}

sub get_review_base {
    my $base = Bugzilla->params->{'splinter_base'};
    $base =~ s!/$!!;
    my $urlbase = correct_urlbase();
    $urlbase =~ s!/$!! if $base =~ "^/";
    $base = $urlbase . $base;
    return $base;
}

sub get_review_url {
    my ($bug, $attach_id) = @_;
    my $base = get_review_base();
    my $bug_id = $bug->id;
    return $base . ($base =~ /\?/ ? '&' : '?') . "bug=$bug_id&attachment=$attach_id";
}

sub get_review_link {
    my ($attach_id, $link_text) = @_;

    my $attachment = attachment_id_is_valid($attach_id);

    if ($attachment && $attachment->ispatch) {
        return "<a href='" . html_quote(get_review_url($attachment->bug, $attach_id)) . 
               "'>$link_text</a>";
    }
    else {
        return $link_text;
    }
}

sub munge_create_attachment {
    my ($bug, $intro_text, $attach_id, $view_link) = @_;

    if (attachment_id_is_patch($attach_id)) {
        return ("$intro_text" .
                " View: $view_link\015\012" .
                " Review: " . get_review_url($bug, $attach_id, 1) . "\015\012");
    } 
    else {
        return ("$intro_text --> ($view_link)");
    }
}

# This adds review links into a bug mail before we send it out.
# Since this is happening after newlines have been converted into
# RFC-2822 style \r\n, we need handle line ends carefully.
# (\015 and \012 are used because Perl \n is platform-dependent)
sub add_review_links_to_email {
    my $email = shift;
    my $body = $email->body;
    my $new_body = 0;
    my $bug;

    if ($email->header('Subject') =~ /^\[Bug\s+(\d+)\]/ 
        && Bugzilla->user->can_see_bug($1))
    {
        $bug = Bugzilla::Bug->new({ id => $1, cache => 1 });
    }

    return unless defined $bug;

    if ($body =~ /Review\s+of\s+attachment\s+\d+\s*:/) {
        $body =~ s~(Review\s+of\s+attachment\s+(\d+)\s*:)
                  ~"$1\015\012 --> (" . get_review_url($bug, $2, 1) . ")"
                  ~egx;
        $new_body = 1;
    }

    if ($body =~ /Created attachment \d+\015\012 --> /) {
        $body =~ s~(Created\ attachment\ (\d+)\015\012)
                   \ -->\ \(([^\015\012]*)\)[^\015\012]*
                  ~munge_create_attachment($bug, $1, $2, $3)
                  ~egx;
        $new_body = 1;
    }

    $email->body_set($body) if $new_body;
}

1;
