# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::Project;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Error;
use Bugzilla::Util qw(trim);
use Bugzilla::Extension::PhabBugz::Util qw(
    request
    get_phab_bmo_ids
);

use Types::Standard -all;
use Type::Utils;

my $SearchResult = Dict[
    id     => Int,
    type   => Str,
    phid   => Str,
    fields => Dict[
        name         => Str,
        slug         => Str,
        depth        => Int,
        milestone    => Maybe[Str],
        parent       => Maybe[Str],
        icon         => Dict[ key => Str, name => Str, icon => Str ],
        color        => Dict[ key => Str, name => Str ],
        dateCreated  => Int,
        dateModified => Int,
        policy       => Dict[ view => Str, edit => Str, join => Str ],
        description  => Maybe[Str]
    ],
    attachments => Dict[
        members => Dict[
            members => ArrayRef[
                Dict[
                    phid => Str
                ],
            ],
        ],
    ],
];

# {
#   "data": [
#     {
#       "id": 1,
#       "type": "PROJ",
#       "phid": "PHID-PROJ-pfssn7lndryddv7hbx4i",
#       "fields": {
#         "name": "bmo-core-security",
#         "slug": "bmo-core-security",
#         "milestone": null,
#         "depth": 0,
#         "parent": null,
#         "icon": {
#           "key": "group",
#           "name": "Group",
#           "icon": "fa-users"
#         },
#         "color": {
#           "key": "red",
#           "name": "Red"
#         },
#         "dateCreated": 1500403964,
#         "dateModified": 1505248862,
#         "policy": {
#           "view": "admin",
#           "edit": "admin",
#           "join": "admin"
#         },
#         "description": "BMO Security Group for core-security"
#       },
#       "attachments": {
#         "members": {
#           "members": [
#             {
#               "phid": "PHID-USER-23ia7vewbjgcqahewncu"
#             },
#             {
#               "phid": "PHID-USER-uif2miph2poiehjeqn5q"
#             }
#           ]
#         }
#       }
#     }
#   ],
#   "maps": {
#     "slugMap": {}
#   },
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
#    Initialization     #
#########################

sub new {
    my ($class, $params) = @_;
    my $self = $params ? _load($params) : {};
    $SearchResult->assert_valid($self);
    return bless($self, $class);
}

sub _load {
    my ($params) = @_;

    my $data = {
        queryKey    => 'all',
        attachments => {
            members => 1
        },
        constraints => $params
    };

    my $result = request('project.search', $data);
    if (exists $result->{result}{data} && @{ $result->{result}{data} }) {
        return $result->{result}->{data}->[0];
    }

    return $result;
}

#########################
#     Modification      #
#########################

sub create {
    my ($class, $params) = @_;

    my $name = trim($params->{name});
    $name || ThrowCodeError('param_required', { param => 'name' });

    my $description = $params->{description} || 'Need description';
    my $view_policy = $params->{view_policy} || 'admin';
    my $edit_policy = $params->{edit_policy} || 'admin';
    my $join_policy = $params->{join_policy} || 'admin';

    my $data = {
        transactions => [
            { type => 'name',        value => $name        },
            { type => 'description', value => $description },
            { type => 'edit',        value => $edit_policy },
            { type => 'join',        value => $join_policy },
            { type => 'view',        value => $view_policy },
            { type => 'icon',        value => 'group'      },
            { type => 'color',       value => 'red'        }
        ]
    };

    my $result = request('project.edit', $data);

    return $class->new({ phids => $result->{result}{object}{phid} });
}

sub update {
    my ($self) = @_;

    my $data = {
        objectIdentifier => $self->phid,
        transactions     => []
    };

    if ($self->{set_name})  {
        push(@{ $data->{transactions} }, {
            type  => 'name',
            value => $self->{set_name}
        });
    }

    if ($self->{set_description})  {
        push(@{ $data->{transactions} }, {
            type  => 'description',
            value => $self->{set_description}
        });
    }

    if ($self->{set_members}) {
        push(@{ $data->{transactions} }, {
            type  => 'members.set',
            value => $self->{set_members}
        });
    }
    else {
        if ($self->{add_members}) {
            push(@{ $data->{transactions} }, {
                type  => 'members.add',
                value => $self->{add_members}
            });
        }

        if ($self->{remove_members}) {
            push(@{ $data->{transactions} }, {
                type  => 'members.remove',
                value => $self->{remove_members}
            });
        }
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

    my $result = request('project.edit', $data);

    return $result;
}

#########################
#      Accessors        #
#########################

sub id              { return $_[0]->{id};                          }
sub phid            { return $_[0]->{phid};                        }
sub type            { return $_[0]->{type};                        }
sub name            { return $_[0]->{fields}->{name};              }
sub description     { return $_[0]->{fields}->{description};       }
sub creation_ts     { return $_[0]->{fields}->{dateCreated};       }
sub modification_ts { return $_[0]->{fields}->{dateModified};      }

sub view_policy { return $_[0]->{fields}->{policy}->{view}; }
sub edit_policy { return $_[0]->{fields}->{policy}->{edit}; }
sub join_policy { return $_[0]->{fields}->{policy}->{join}; }

sub members_raw { return $_[0]->{attachments}->{members}->{members}; }

sub members {
    my ($self) = @_;
    return $self->{members} if $self->{members};

    my @phids;
    foreach my $member (@{ $self->members_raw }) {
        push(@phids, $member->{phid});
    }

    return [] if !@phids;

    my $users = get_phab_bmo_ids({ phids => \@phids });

    my @members;
    foreach my $user (@$users) {
        my $member = Bugzilla::User->new({ id => $user->{id}, cache => 1});
        $member->{phab_phid} = $user->{phid};
        push(@members, $member);
    }

    return \@members;
}

#########################
#       Mutators        #
#########################

sub set_name {
    my ($self, $name) = @_;
    $name = trim($name);
    $self->{set_name} = $name;
}

sub set_description {
    my ($self, $description) = @_;
    $description = trim($description);
    $self->{set_description} = $description;
}

sub add_member {
    my ($self, $member) = @_;
    $self->{add_members} ||= [];
    my $member_phid = blessed $member ? $member->phab_phid : $member;
    push(@{ $self->{add_members} }, $member_phid);
}

sub remove_member {
    my ($self, $member) = @_;
    $self->{remove_members} ||= [];
    my $member_phid = blessed $member ? $member->phab_phid : $member;
    push(@{ $self->{remove_members} }, $member_phid);
}

sub set_members {
    my ($self, $members) = @_;
    $self->{set_members} = [ map { $_->phab_phid } @$members ];
}

sub set_policy {
    my ($self, $name, $policy) = @_;
    $self->{set_policy} ||= {};
    $self->{set_policy}->{$name} = $policy;
}

1;