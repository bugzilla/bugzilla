# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::EditComments::WebService;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::WebService);

use Bugzilla;
use Bugzilla::Comment;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Template;
use Bugzilla::Util qw(trim);
use Bugzilla::WebService::Util qw(validate);

use constant PUBLIC_METHODS => qw(
  comments
  update_comment
  modify_revision
);

sub comments {
  my ($self, $params) = validate(@_, 'comment_ids');
  my $dbh  = Bugzilla->switch_to_shadow_db();
  my $user = Bugzilla->user;

  if (!defined $params->{comment_ids}) {
    ThrowCodeError('param_required',
      {function => 'Bug.comments', param => 'comment_ids'});
  }

  my @ids = map { trim($_) } @{$params->{comment_ids} || []};
  my $comment_data = Bugzilla::Comment->new_from_list(\@ids);

  # See if we were passed any invalid comment ids.
  my %got_ids = map { $_->id => 1 } @$comment_data;
  foreach my $comment_id (@ids) {
    if (!$got_ids{$comment_id}) {
      ThrowUserError('comment_id_invalid', {id => $comment_id});
    }
  }

  # Now make sure that we can see all the associated bugs.
  my %got_bug_ids = map { $_->bug_id => 1 } @$comment_data;
  $user->visible_bugs([keys %got_bug_ids]);   # preload cache for visibility check
  Bugzilla::Bug->check($_) foreach (keys %got_bug_ids);

  my %comments;
  foreach my $comment (@$comment_data) {
    if ($comment->is_private && !$user->is_insider) {
      ThrowUserError('comment_is_private', {id => $comment->id});
    }
    $comments{$comment->id} = $comment->body;
  }

  return {comments => \%comments};
}

# See Bugzilla::Extension::EditComments->bug_end_of_update for the original implementation.
# This should be migrated to the standard API method at /rest/bug/comment/(comment_id)
sub update_comment {
  my ($self, $params) = @_;
  my $user                = Bugzilla->login(LOGIN_REQUIRED);
  my $edit_comments_group = Bugzilla->params->{edit_comments_group};

  # Validate group membership
  ThrowUserError('auth_failure',
    {group => $edit_comments_group, action => 'view', object => 'editcomments'})
    unless $user->is_insider
    || $edit_comments_group && $user->in_group($edit_comments_group);

  my $comment_id
    = (defined $params->{comment_id} && $params->{comment_id} =~ /^(\d+)$/)
    ? $1
    : undef;

  # Validate parameters
  ThrowCodeError('param_required',
    {function => 'EditComments.update_comment', param => 'comment_id'})
    unless defined $comment_id;
  ThrowCodeError('param_required',
    {function => 'EditComments.update_comment', param => 'new_comment'})
    unless defined $params->{new_comment} && trim($params->{new_comment}) ne '';

  my $comment = Bugzilla::Comment->new($comment_id);

  # Validate comment visibility
  ThrowUserError('comment_id_invalid', {id => $comment_id}) unless $comment;
  ThrowUserError('comment_is_private', {id => $comment->id})
    unless $user->is_insider || !$comment->is_private;

# Insiders can edit any comment while unprivileged users can only edit their own comments
  ThrowUserError('auth_failure',
    {group => 'insidergroup', action => 'view', object => 'editcomments'})
    unless $user->is_insider || $comment->author->id == $user->id;

  my $bug         = $comment->bug;
  my $old_comment = $comment->body;
  my $new_comment = $comment->_check_thetext($params->{new_comment});

  # Validate bug visibility
  $bug->check_is_visible();

  # Make sure there is any change in the comment
  ThrowCodeError('param_no_changes',
    {function => 'EditComments.update_comment', param => 'new_comment'})
    if $old_comment eq $new_comment;

  my $dbh         = Bugzilla->dbh;
  my $change_when = $dbh->selectrow_array('SELECT NOW()');

  # Insiders can hide comment revisions where needed
  my $is_hidden
    = (  $user->is_insider
      && defined $params->{is_hidden}
      && $params->{is_hidden} == 1) ? 1 : 0;

  # Update the `longdescs` (comments) table
  $dbh->do(
    'UPDATE longdescs SET thetext = ?, edit_count = edit_count + 1 WHERE comment_id = ?',
    undef, $new_comment, $comment_id
  );
  Bugzilla->memcached->clear({table => 'longdescs', id => $comment_id});

  # Log old comment to the `longdescs_activity` (comment revisions) table
  $dbh->do(
    'INSERT INTO longdescs_activity (comment_id, who, change_when, old_comment, is_hidden)
              VALUES (?, ?, ?, ?, ?)', undef,
    ($comment_id, $user->id, $change_when, $old_comment, $is_hidden)
  );

  $comment->{thetext} = $new_comment;
  $bug->_sync_fulltext(update_comments => 1);

  my $html
    = $comment->is_markdown && Bugzilla->params->{use_markdown}
    ? Bugzilla->markdown->render_html($new_comment, $bug)
    : Bugzilla::Template::quoteUrls($new_comment, $bug);

  # Respond with the updated comment and number of revisions
  return {
    text  => $self->type('string', $new_comment),
    html  => $self->type('string', $html),
    count => $self->type(
      'int',
      $dbh->selectrow_array(
        'SELECT COUNT(*) FROM longdescs_activity
                                                           WHERE comment_id = ?',
        undef, ($comment_id)
      )
    ),
  };
}

sub modify_revision {
  my ($self, $params) = @_;
  my $user = Bugzilla->login(LOGIN_REQUIRED);

  # Only allow insiders to modify revisions
  ThrowUserError('auth_failure',
    {group => 'insidergroup', action => 'view', object => 'editcomments'})
    unless $user->is_insider;

  my $comment_id
    = (defined $params->{comment_id} && $params->{comment_id} =~ /^(\d+)$/)
    ? $1
    : undef;
  my $change_when
    = (defined $params->{change_when}
      && $params->{change_when} =~ /^(\d{4}-\d{2}-\d{2}\ \d{2}:\d{2}:\d{2})$/)
    ? $1
    : undef;
  my $is_hidden
    = defined $params->{is_hidden} && $params->{is_hidden} == 1 ? 1 : 0;

  # Validate parameters
  ThrowCodeError('param_required',
    {function => 'EditComments.modify_revision', param => 'comment_id'})
    unless defined $comment_id;
  ThrowCodeError('param_required',
    {function => 'EditComments.modify_revision', param => 'change_when'})
    unless defined $change_when;

  my $dbh = Bugzilla->dbh;

  # Update revision visibility
  $dbh->do(
    'UPDATE longdescs_activity SET is_hidden = ? WHERE comment_id = ? AND change_when = ?',
    undef,
    ($is_hidden, $comment_id, $change_when)
  );

  # Respond with updated revision info
  return {
    change_when => $self->type('dateTime', $change_when),
    is_hidden   => $self->type('boolean',  $is_hidden),
  };
}

sub rest_resources {
  return [
    qr{^/editcomments/comment/(\d+)$},
    {
      GET => {
        method => 'comments',
        params => sub {
          return {comment_ids => $_[0]};
        },
      },
      PUT => {
        method => 'update_comment',
        params => sub {
          return {comment_id => $_[0]};
        },
      },
    },
    qr{^/editcomments/comment$},
    {GET => {method => 'comments',},},
    qr{^/editcomments/revision$},
    {PUT => {method => 'modify_revision',},},
  ];
}


1;

__END__

=head1 NAME

Bugzilla::Extension::EditComments::Webservice - The EditComments WebServices API

=head1 DESCRIPTION

This module contains API methods that are useful to user's of bugzilla.mozilla.org.

=head1 METHODS

=head2 comments

B<EXPERIMENTAL>

=over

=item B<Description>

This allows you to get the raw comment text about comments, given a list of comment ids.

=item B<REST>

To get all comment text for a list of comment ids:

GET /bug/editcomments/comment?comment_ids=1234&comment_ids=5678...

To get comment text for a specific comment based on the comment ID:

GET /bug/editcomments/comment/<comment_id>

The returned data format is the same as below.

=item B<Params>

=over

=item C<comment_ids> (required)

C<array> An array of integer comment_ids. These comments will be
returned individually, separate from any other comments in their
respective bugs.

=item B<Returns>

1 item is returned:

=over

=item C<comments>

Each individual comment requested in C<comment_ids> is returned here,
in a hash where the numeric comment id is the key, and the value
is the comment's raw text.

=back

=item B<Errors>

In addition to standard Bug.get type errors, this method can throw the
following additional errors:

=over

=item 110 (Comment Is Private)

You specified the id of a private comment in the C<comment_ids>
argument, and you are not in the "insider group" that can see
private comments.

=item 111 (Invalid Comment ID)

You specified an id in the C<comment_ids> argument that is invalid--either
you specified something that wasn't a number, or there is no comment with
that id.

=back

=item B<History>

=over

=item Added in BMO Bugzilla B<4.2>.

=back

=back

=back

See L<Bugzilla::WebService> for a description of how parameters are passed,
and what B<STABLE>, B<UNSTABLE>, and B<EXPERIMENTAL> mean.
