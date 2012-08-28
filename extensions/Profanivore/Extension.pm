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

use Bugzilla::Util qw(is_7bit_clean);

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

    if ($author && $recipient && lc($author) ne lc($recipient)) {
        my $email_suffix = Bugzilla->params->{'emailsuffix'};
        if ($email_suffix ne '') {
            $recipient =~ s/\Q$email_suffix\E$//;
            $author    =~ s/\Q$email_suffix\E$//;
        }

        $author = new Bugzilla::User({ name => $author });

        if ($author &&
            $author->id && 
            !$author->in_group('editbugs'))
        {
            # Multipart emails
            if (scalar $email->parts > 1) {
                $email->walk_parts(sub {
                    my ($part) = @_;
                    return if $part->parts > 1; # Top-level
                    # do not filter attachments such as patches, etc.
                    if ($part->header('Content-Disposition')
                        && $part->header('Content-Disposition') =~ /attachment/)
                    {
                        return;
                    }
                    _fix_encoding($part);
                    my $body = $part->body_str;
                    if ($part->content_type =~ /^text\/html/) {
                        $body = _filter_html($body);
                    }
                    elsif ($part->content_type =~ /^text\/plain/) {
                        $body = _filter_text($body);
                    }
                    $part->body_str_set($body);
                });
            }
            # Single part email
            else {
                _fix_encoding($email);
                $email->body_str_set(_filter_text($email->body_str));
            }
        }
    }
}

sub _fix_encoding {
    my $part = shift;
    my $body = $part->body;
    if (Bugzilla->params->{'utf8'}) {
        $part->charset_set('UTF-8');
        # encoding_set works only with bytes, not with utf8 strings.
        my $raw = $part->body_raw;
        if (utf8::is_utf8($raw)) {
            utf8::encode($raw);
            $part->body_set($raw);
        }
    }
    $part->encoding_set('quoted-printable') if !is_7bit_clean($body);
}

sub _filter_text {
    my $text = shift;
    my $offensive = RE_profanity();
    $text =~ s/$offensive/****/g;
    return $text;
}

sub _filter_html {
    my $html = shift;
    my $tree = HTML::Tree->new->parse_content($html);
    my $comments_div = $tree->look_down( _tag => 'div', id => 'comments' );
    return $html if !$comments_div;
    my @comments = $comments_div->look_down( _tag => 'pre' );
    foreach my $comment (@comments) {
        _filter_html_node($comment);
    }
    return $tree->as_HTML;
}

sub _filter_html_node {
    my $node = shift;
    my $content = [ $node->content_list ];
    foreach my $item_r ($node->content_refs_list) {
        if (ref $$item_r) {
            _filter_html_node($$item_r);
        } else {
            $$item_r = _filter_text($$item_r);
        }
    }
    return $node;
}

__PACKAGE__->NAME;
