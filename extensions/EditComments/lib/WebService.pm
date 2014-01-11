# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::EditComments::WebService;

use strict;
use warnings;

use base qw(Bugzilla::WebService);

use Bugzilla::Error;
use Bugzilla::Util qw(trim);
use Bugzilla::WebService::Util qw(validate);

sub comments {
    my ($self, $params) = validate(@_, 'comment_ids');
    my $dbh  = Bugzilla->switch_to_shadow_db();
    my $user = Bugzilla->user;

    if (!defined $params->{comment_ids}) {
        ThrowCodeError('param_required',
                       { function => 'Bug.comments',
                         param    => 'comment_ids' });
    }

    my @ids = map { trim($_) } @{ $params->{comment_ids} || [] };
    my $comment_data = Bugzilla::Comment->new_from_list(\@ids);

    # See if we were passed any invalid comment ids.
    my %got_ids = map { $_->id => 1 } @$comment_data;
    foreach my $comment_id (@ids) {
        if (!$got_ids{$comment_id}) {
            ThrowUserError('comment_id_invalid', { id => $comment_id });
        }
    }

    # Now make sure that we can see all the associated bugs.
    my %got_bug_ids = map { $_->bug_id => 1 } @$comment_data;
    $user->visible_bugs([ keys %got_bug_ids ]); # preload cache for visibility check
    Bugzilla::Bug->check($_) foreach (keys %got_bug_ids);

    my %comments;
    foreach my $comment (@$comment_data) {
        if ($comment->is_private && !$user->is_insider) {
            ThrowUserError('comment_is_private', { id => $comment->id });
        }
        $comments{$comment->id} = $comment->body;
    }

    return { comments => \%comments };
}

sub rest_resources {
    return [
        qr{^/editcomments/comment/(\d+)$}, {
            GET => {
                method => 'comments',
                params => sub {
                    return { comment_ids => $_[0] };
                },
            },
        },
        qr{^/editcomments/comment$}, {
            GET => {
                method => 'comments',
            },
        },
    ];
};


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
