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
# The Initial Developer of the Original Code is James Robson.
# Portions created by James Robson are Copyright (c) 2009 James Robson.
# All rights reserved.
#
# Contributor(s): James Robson <arbingersys@gmail.com> 

use strict;

package Bugzilla::Comment;

use base qw(Bugzilla::Object);

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Util;

###############################
####    Initialization     ####
###############################

use constant DB_COLUMNS => qw(
    comment_id
    bug_id
    who
    bug_when
    work_time
    thetext
    isprivate
    already_wrapped
    type
    extra_data
);

use constant DB_TABLE => 'longdescs';
use constant ID_FIELD => 'comment_id';
use constant LIST_ORDER => 'bug_when';

###############################
####      Accessors      ######
###############################

sub already_wrapped { return $_[0]->{'already_wrapped'}; }
sub body        { return $_[0]->{'thetext'}; }
sub bug_id      { return $_[0]->{'bug_id'}; }
sub creation_ts { return $_[0]->{'bug_when'}; }
sub is_private  { return $_[0]->{'isprivate'}; }
sub work_time   { return $_[0]->{'work_time'}; }

sub author { 
    my $self = shift;
    $self->{'author'} ||= new Bugzilla::User($self->{'who'});
    return $self->{'author'};
}

sub body_full {
    my ($self, $params) = @_;
    $params ||= {};
    my $template = Bugzilla->template_inner;
    my $body;
    $template->process("bug/format_comment.txt.tmpl", 
                       { comment => $self, %$params }, \$body)
        || ThrowTemplateError($template->error());
    $body =~ s/^X//;
    if ($params->{wrap} and !$self->already_wrapped) {
        $body = wrap_comment($body);
    }
    return $body;
}

1;

__END__

=head1 NAME

Bugzilla::Comment - A Comment for a given bug 

=head1 SYNOPSIS

 use Bugzilla::Comment;

 my $comment = Bugzilla::Comment->new($comment_id);
 my $comments = Bugzilla::Comment->new_from_list($comment_ids);

=head1 DESCRIPTION

Bugzilla::Comment represents a comment attached to a bug.

This implements all standard C<Bugzilla::Object> methods. See 
L<Bugzilla::Object> for more details.

=head2 Accessors

=over

=item C<bug_id>

C<int> The ID of the bug to which the comment belongs.

=item C<creation_ts>

C<string> The comment creation timestamp.

=item C<body>

C<string> The body without any special additional text.

=item C<work_time>

C<string> Time spent as related to this comment.

=item C<is_private>

C<boolean> Comment is marked as private

=item C<already_wrapped>

If this comment is stored in the database word-wrapped, this will be C<1>.
C<0> otherwise.

=item C<author>

L<Bugzilla::User> who created the comment.

=item C<body_full>

=over

=item B<Description>

C<string> Body of the comment, including any special text (such as
"this bug was marked as a duplicate of...").

=item B<Params>

=over

=item C<is_bugmail>

C<boolean>. C<1> if this comment should be formatted specifically for
bugmail.

=item C<wrap>

C<boolean>. C<1> if the comment should be returned word-wrapped.

=back

=item B<Returns>

A string, the full text of the comment as it would be displayed to an end-user.

=back



=back

=cut
