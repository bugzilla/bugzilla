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
# The Original Code is the InlineImages Bugzilla Extension.
#
# The Initial Developer of the Original Code is Guy Pyrzak
# Portions created by the Initial Developer are Copyright (C) 2010 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Guy Pyrzak <guy.pyrzak@gmail.com>
#   Gervase Markham <gerv@gerv.net>

package Bugzilla::Extension::InlineImages;
use strict;
use base qw(Bugzilla::Extension);
use Bugzilla::Template;

use constant NAME => 'InlineImages';

our $VERSION = '0.2';

sub bug_format_comment {
    my ($self, $args) = @_;
    my $regexes = $args->{'regexes'};
    
    push(@$regexes, {    
        match   => qr~\b(attachment\s*\#?\s*(\d+))~,
        replace => \&_inlineAttachments
    });
}

sub _inlineAttachments {
    my $args = shift @_;
    my $attachment_id = $args->{matches}->[1];
    my $attachment_string = $args->{matches}->[0];
    
    # We need to call get_attachment_link because otherwise it will be skipped
    my $msg = Bugzilla::Template::get_attachment_link($attachment_id, 
                                                      $attachment_string);
    
    my $dbh = Bugzilla->dbh;
    my ($mimetype) =
        $dbh->selectrow_array('SELECT mimetype
                               FROM attachments WHERE attach_id = ?',
                               undef, $attachment_id);
    if ($mimetype =~ /^image\/(gif|png|jpeg)$/) {
        $msg =~ s/(?=name="attach_)/ class="is_image" /;
    }
    
    return $msg;
};

__PACKAGE__->NAME;
