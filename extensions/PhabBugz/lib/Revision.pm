# This Source Code Form is hasject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::Revision;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Bug;
use Bugzilla::Error;
use Bugzilla::Util qw(trim);
use Bugzilla::Extension::PhabBugz::Util qw(
    get_phab_bmo_ids
    request
);

use Types::Standard -all;

my $SearchResult = Dict[
    id     => Int,
    type   => Str,
    phid   => Str,
    fields => Dict[
        title             => Str,
        authorPHID        => Str,
        dateCreated       => Int,
        dateModified      => Int,
        diffPHID          => Str,
        policy            => Dict[ view => Str, edit => Str ],
        repositoryPHID    => Maybe[Str],
        status            => HashRef,
        summary           => Str,
        "bugzilla.bug-id" => Int,
    ],
    attachments => Dict[
        reviewers => Dict[
            reviewers => ArrayRef[
                Dict[
                    reviewerPHID => Str,
                    status       => Str,
                    isBlocking   => Bool,
                    actorPHID    => Maybe[Str],
                ],
            ],
        ],
        subscribers => Dict[
            subscriberPHIDs => ArrayRef[Str],
            subscriberCount => Int,
            viewerIsSubscribed => Bool,
        ],
        projects => Dict[ projectPHIDs => ArrayRef[Str] ],
    ],
];

my $NewParams    = Dict[ phids => ArrayRef[Str] ];

#########################
#    Initialization     #
#########################

sub new {
    my ($class, $params) = @_;
    $NewParams->assert_valid($params);
    my $self = _load($params);
    $SearchResult->assert_valid($self);

    return bless($self, $class);
}

sub _load {
    my ($params) = @_;

    my $data = {
        queryKey    => 'all',
        attachments => {
            projects    => 1,
            reviewers   => 1,
            subscribers => 1
        },
        constraints => $params
    };

    my $result = request('differential.revision.search', $data);
    if (exists $result->{result}{data} && @{ $result->{result}{data} }) {
        return $result->{result}->{data}->[0];
    }

    return $result;
}

# {
#   "data": [
#     {
#       "id": 25,
#       "type": "DREV",
#       "phid": "PHID-DREV-uozm3ggfp7e7uoqegmc3",
#       "fields": {
#         "title": "Added .arcconfig",
#         "authorPHID": "PHID-USER-4wigy3sh5fc5t74vapwm",
#         "dateCreated": 1507666113,
#         "dateModified": 1508514027,
#         "policy": {
#           "view": "public",
#           "edit": "admin"
#         },
#         "bugzilla.bug-id": "1154784"
#       },
#       "attachments": {
#         "reviewers": {
#           "reviewers": [
#             {
#               "reviewerPHID": "PHID-USER-2gjdpu7thmpjxxnp7tjq",
#               "status": "added",
#               "isBlocking": false,
#               "actorPHID": null
#             },
#             {
#               "reviewerPHID": "PHID-USER-o5dnet6dp4dkxkg5b3ox",
#               "status": "rejected",
#               "isBlocking": false,
#               "actorPHID": "PHID-USER-o5dnet6dp4dkxkg5b3ox"
#             }
#           ]
#         },
#         "subscribers": {
#           "subscriberPHIDs": [],
#           "subscriberCount": 0,
#           "viewerIsSubscribed": true
#         },
#         "projects": {
#           "projectPHIDs": []
#         }
#       }
#     }
#   ],
#   "maps": {},
#   "query": {
#     "queryKey": null
#   },
#   "cursor": {
#     "limit": 100,
#     "after": null,
#     "before": null,
#     "order": null
#   }
# }

#########################
#     Modification      #
#########################

sub update {
    my ($self) = @_;

    my $data = {
        objectIdentifier => $self->phid,
        transactions     => []
    };

    if ($self->{added_comments}) {
        foreach my $comment (@{ $self->{added_comments} }) {
            push(@{ $data->{transactions} }, {
                type  => 'comment',
                value => $comment
            });
        }
    }

    if ($self->{set_subscribers}) {
        push(@{ $data->{transactions} }, {
            type  => 'subscribers.set',
            value => $self->{set_subscribers}
        });
    }

    if ($self->{add_subscribers}) {
        push(@{ $data->{transactions} }, {
            type  => 'subscribers.add',
            value => $self->{add_subscribers}
        });
    }

    if ($self->{remove_subscribers}) {
        push(@{ $data->{transactions} }, {
            type  => 'subscribers.remove',
            value => $self->{remove_subscribers}
        });
    }

    if ($self->{set_reviewers}) {
        push(@{ $data->{transactions} }, {
            type  => 'reviewers.set',
            value => $self->{set_reviewers}
        });
    }

    if ($self->{add_reviewers}) {
        push(@{ $data->{transactions} }, {
            type  => 'reviewers.add',
            value => $self->{add_reviewers}
        });
    }

    if ($self->{remove_reviewers}) {
        push(@{ $data->{transactions} }, {
            type  => 'reviewers.remove',
            value => $self->{remove_reviewers}
        });
    }

    if ($self->{set_policy}) {
        foreach my $name ("view", "edit") {
            next unless $self->{set_policy}->{$name};
            push(@{ $data->{transactions} }, {
                type  => $name,
                value => $self->{set_policy}->{$name}
            });
        }
    }

    my $result = request('differential.revision.edit', $data);

    return $result;
}

#########################
#      Accessors        #
#########################

sub id              { $_[0]->{id};                          }
sub phid            { $_[0]->{phid};                        }
sub title           { $_[0]->{fields}->{title};             }
sub status          { $_[0]->{fields}->{status}->{value};   }
sub creation_ts     { $_[0]->{fields}->{dateCreated};       }
sub modification_ts { $_[0]->{fields}->{dateModified};      }
sub author_phid     { $_[0]->{fields}->{authorPHID};        }
sub bug_id          { $_[0]->{fields}->{'bugzilla.bug-id'}; }

sub view_policy { $_[0]->{fields}->{policy}->{view}; }
sub edit_policy { $_[0]->{fields}->{policy}->{edit}; }

sub reviewers_raw    { $_[0]->{attachments}->{reviewers}->{reviewers};         }
sub subscribers_raw  { $_[0]->{attachments}->{subscribers};                    }
sub projects_raw     { $_[0]->{attachments}->{projects};                       }
sub subscriber_count { $_[0]->{attachments}->{subscribers}->{subscriberCount}; }

sub bug {
    my ($self) = @_;
    return $self->{bug} ||= Bugzilla::Bug->new({ id => $self->bug_id, cache => 1 });
}

sub author {
    my ($self) = @_;
    return $self->{author} if $self->{author};
    my $users = get_phab_bmo_ids({ phids => [$self->author_phid] });
    if (@$users) {
        $self->{author} = new Bugzilla::User({ id => $users->[0]->{id}, cache => 1 });
        $self->{author}->{phab_phid} = $self->author_phid;
        return $self->{author};
    }
    return undef;
}

sub reviewers {
    my ($self) = @_;
    return $self->{reviewers} if $self->{reviewers};

    my @phids;
    foreach my $reviewer (@{ $self->reviewers_raw }) {
        push(@phids, $reviewer->{reviewerPHID});
    }

    return [] if !@phids;

    my $users = get_phab_bmo_ids({ phids => \@phids });

    my @reviewers;
    foreach my $user (@$users) {
        my $reviewer = Bugzilla::User->new({ id => $user->{id}, cache => 1});
        $reviewer->{phab_phid} = $user->{phid};
        foreach my $reviewer_data (@{ $self->reviewers_raw }) {
            if ($reviewer_data->{reviewerPHID} eq $user->{phid}) {
                $reviewer->{phab_review_status} = $reviewer_data->{status};
                last;
            }
        }
        push(@reviewers, $reviewer);
    }

    return \@reviewers;
}

sub subscribers {
    my ($self) = @_;
    return $self->{subscribers} if $self->{subscribers};

    my @phids;
    foreach my $phid (@{ $self->subscribers_raw->{subscriberPHIDs} }) {
        push(@phids, $phid);
    }

    my $users = get_phab_bmo_ids({ phids => \@phids });

    return [] if !@phids;

    my @subscribers;
    foreach my $user (@$users) {
        my $subscriber = Bugzilla::User->new({ id => $user->{id}, cache => 1});
        $subscriber->{phab_phid} = $user->{phid};
        push(@subscribers, $subscriber);
    }

    return \@subscribers;
}

#########################
#       Mutators        #
#########################

sub add_comment {
    my ($self, $comment) = @_;
    $comment = trim($comment);
    $self->{added_comments} ||= [];
    push(@{ $self->{added_comments} }, $comment);
}

sub add_reviewer {
    my ($self, $reviewer) = @_;
    $self->{add_reviewers} ||= [];
    my $reviewer_phid = blessed $reviewer ? $reviewer->phab_phid : $reviewer;
    push(@{ $self->{add_reviewers} }, $reviewer_phid);
}

sub remove_reviewer {
    my ($self, $reviewer) = @_;
    $self->{remove_reviewers} ||= [];
    my $reviewer_phid = blessed $reviewer ? $reviewer->phab_phid : $reviewer;
    push(@{ $self->{remove_reviewers} }, $reviewer_phid);
}

sub set_reviewers {
    my ($self, $reviewers) = @_;
    $self->{set_reviewers} = [ map { $_->phab_phid } @$reviewers ];
}

sub add_subscriber {
    my ($self, $subscriber) = @_;
    $self->{add_subscribers} ||= [];
    my $subscriber_phid = blessed $subscriber ? $subscriber->phab_phid : $subscriber;
    push(@{ $self->{add_subscribers} }, $subscriber_phid);
}

sub remove_subscriber {
    my ($self, $subscriber) = @_;
    $self->{remove_subscribers} ||= [];
    my $subscriber_phid = blessed $subscriber ? $subscriber->phab_phid : $subscriber;
    push(@{ $self->{remove_subscribers} }, $subscriber_phid);
}

sub set_subscribers {
    my ($self, $subscribers) = @_;
    $self->{set_subscribers} = $subscribers;
}

sub set_policy {
    my ($self, $name, $policy) = @_;
    $self->{set_policy} ||= {};
    $self->{set_policy}->{$name} = $policy;
}

1;