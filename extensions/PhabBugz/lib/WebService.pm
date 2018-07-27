# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::WebService;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::WebService);

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::User;
use Bugzilla::Util qw(detaint_natural datetime_from time_ago trick_taint);
use Bugzilla::WebService::Constants;

use Bugzilla::Extension::PhabBugz::Constants;
use Bugzilla::Extension::PhabBugz::Util qw(
    get_needs_review
);

use DateTime ();
use List::Util qw(first uniq);
use List::MoreUtils qw(any);
use MIME::Base64 qw(decode_base64);

use constant READ_ONLY => qw(
    check_user_enter_bug_permission
    check_user_permission_for_bug
    needs_review
);

use constant PUBLIC_METHODS => qw(
    check_user_enter_bug_permission
    check_user_permission_for_bug
    needs_review
    set_build_target
);

sub _check_phabricator {
    # Ensure PhabBugz is on
    ThrowUserError('phabricator_not_enabled')
        unless Bugzilla->params->{phabricator_enabled};
}

sub _validate_phab_user {
    my ($self, $user) = @_;

    $self->_check_phabricator();

    # Validate that the requesting user's email matches phab-bot
    ThrowUserError('phabricator_unauthorized_user')
        unless $user->login eq PHAB_AUTOMATION_USER;
}

sub check_user_permission_for_bug {
    my ($self, $params) = @_;

    my $user = Bugzilla->login(LOGIN_REQUIRED);

    $self->_validate_phab_user($user);

    # Validate that a bug id and user id are provided
    ThrowUserError('phabricator_invalid_request_params')
        unless ($params->{bug_id} && $params->{user_id});

    # Validate that the user exists
    my $target_user = Bugzilla::User->check({ id => $params->{user_id}, cache => 1 });

    # Send back an object which says { "result": 1|0 }
    return {
        result => $target_user->can_see_bug($params->{bug_id})
    };
}

sub check_user_enter_bug_permission {
    my ($self, $params) = @_;

    my $user = Bugzilla->login(LOGIN_REQUIRED);

    $self->_validate_phab_user($user);

    # Validate that a product name and user id are provided
    ThrowUserError('phabricator_invalid_request_params')
        unless ($params->{product} && $params->{user_id});

    # Validate that the user exists
    my $target_user = Bugzilla::User->check({ id => $params->{user_id}, cache => 1 });

    # Send back an object with the attribute "result" set to 1 if the user
    # can enter bugs into the given product, or 0 if not.
    return {
        result => $target_user->can_enter_product($params->{product}) ? 1 : 0
    };
}

sub needs_review {
    my ($self, $params) = @_;

    $self->_check_phabricator();

    my $user = Bugzilla->login(LOGIN_REQUIRED);
    my $dbh  = Bugzilla->dbh;

    my $reviews = get_needs_review();

    my $authors = Bugzilla::Extension::PhabBugz::User->match({
        phids => [
            uniq
            grep { defined }
            map { $_->{fields}{authorPHID} }
            @$reviews
        ]
    });

    my %author_phab_to_id = map { $_->phid => $_->bugzilla_user->id } @$authors;
    my %author_id_to_user = map { $_->bugzilla_user->id => $_->bugzilla_user } @$authors;

    # bug data
    my $visible_bugs = $user->visible_bugs([
        uniq
        grep { $_ }
        map { $_->{fields}{'bugzilla.bug-id'} }
        @$reviews
    ]);

    # get all bug statuses and summaries in a single query to avoid creation of
    # many bug objects
    my %bugs;
    if (@$visible_bugs) {
        #<<<
        my $bug_rows =$dbh->selectall_arrayref(
            'SELECT bug_id, bug_status, short_desc ' .
            '  FROM bugs ' .
            ' WHERE bug_id IN (' . join(',', ('?') x @$visible_bugs) . ')',
            { Slice => {} },
            @$visible_bugs
        );
        #>>>
        %bugs = map { $_->{bug_id} => $_ } @$bug_rows;
    }

    # build result
    my $datetime_now = DateTime->now(time_zone => $user->timezone);
    my @result;
    foreach my $review (@$reviews) {
        my $review_flat = {
            id     => $review->{id},
            title  => $review->{fields}{title},
            url    => Bugzilla->params->{phabricator_base_uri} . 'D' . $review->{id},
        };

        # show date in user's timezone
        my $datetime = DateTime->from_epoch(
            epoch     => $review->{fields}{dateModified},
            time_zone => 'UTC'
        );
        $datetime->set_time_zone($user->timezone);
        $review_flat->{updated}       = $datetime->strftime('%Y-%m-%d %T %Z');
        $review_flat->{updated_fancy} = time_ago($datetime, $datetime_now);

        # review requester
        if (my $author = $author_id_to_user{$author_phab_to_id{ $review->{fields}{authorPHID} }}) {
            $review_flat->{author_name}  = $author->name;
            $review_flat->{author_email} = $author->email;
        }
        else {
            $review_flat->{author_name}  = 'anonymous';
            $review_flat->{author_email} = 'anonymous';
        }

        # referenced bug
        if (my $bug_id = $review->{fields}{'bugzilla.bug-id'}) {
            my $bug = $bugs{$bug_id};
            $review_flat->{bug_id}      = $bug_id;
            $review_flat->{bug_status}  = $bug->{bug_status};
            $review_flat->{bug_summary} = $bug->{short_desc};
        }

        push @result, $review_flat;
    }

    return { result => \@result };
}

sub set_build_target {
    my ( $self, $params ) = @_;

    # Phabricator only supports sending credentials via HTTP Basic Auth
    # so we exploit that function to pass in an API key as the password
    # of basic auth. BMO does not support basic auth but does support
    # use of API keys.
    my $http_auth = Bugzilla->cgi->http('Authorization');
    $http_auth =~ s/^Basic\s+//;
    $http_auth = decode_base64($http_auth);
    my ($login, $api_key) = split(':', $http_auth);
    $params->{'Bugzilla_login'}   = $login;
    $params->{'Bugzilla_api_key'} = $api_key;

    my $user = Bugzilla->login(LOGIN_REQUIRED);

    $self->_validate_phab_user($user);

    my $revision_id  = $params->{revision_id};
    my $build_target = $params->{build_target};

    ThrowUserError('invalid_phabricator_revision_id')
      unless detaint_natural($revision_id);

    ThrowUserError('invalid_phabricator_build_target')
      unless $build_target =~ /^PHID-HMBT-[a-zA-Z0-9]+$/;
    trick_taint($build_target);

    Bugzilla->dbh->do(
        "INSERT INTO phabbugz (name, value) VALUES (?, ?)",
        undef,
        'build_target_' . $revision_id,
        $build_target
    );

    return { result => 1 };
}

sub rest_resources {
    return [
        # Set build target in Phabricator
        qr{^/phabbugz/build_target/(\d+)/(PHID-HMBT-.*)$}, {
            POST => {
                method => 'set_build_target',
                params => sub {
                    return {
                        revision_id  => $_[0],
                        build_target => $_[1]
                    };
                }
            }
        },
        # Bug permission checks
        qr{^/phabbugz/check_bug/(\d+)/(\d+)$}, {
            GET => {
                method => 'check_user_permission_for_bug',
                params => sub {
                    return { bug_id => $_[0], user_id => $_[1] };
                }
            }
        },
        qr{^/phabbugz/check_enter_bug/([^/]+)/(\d+)$}, {
            GET => {
                method => 'check_user_enter_bug_permission',
                params => sub {
                    return { product => $_[0], user_id => $_[1] };
                },
            },
        },
        # Review requests
        qw{^/phabbugz/needs_review$}, {
            GET => {
                method => 'needs_review',
            },
        }
    ];
}

1;
