# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::Project;

use 5.10.1;
use Moo;
use Types::Standard -all;
use Type::Utils;

use Bugzilla::Error;
use Bugzilla::Util qw(trim);
use Bugzilla::Extension::PhabBugz::Util qw(
  request
  get_phab_bmo_ids
);

#########################
#    Initialization     #
#########################

has id              => ( is => 'ro', isa => Int );
has phid            => ( is => 'ro', isa => Str );
has type            => ( is => 'ro', isa => Str );
has name            => ( is => 'ro', isa => Str );
has description     => ( is => 'ro', isa => Str );
has creation_ts     => ( is => 'ro', isa => Str );
has modification_ts => ( is => 'ro', isa => Str );
has view_policy     => ( is => 'ro', isa => Str );
has edit_policy     => ( is => 'ro', isa => Str );
has join_policy     => ( is => 'ro', isa => Str );
has members_raw     => ( is => 'ro', isa => ArrayRef [ Dict [ phid => Str ] ] );
has members => ( is => 'lazy', isa => ArrayRef [Object] );

sub new_from_query {
    my ( $class, $params ) = @_;

    my $data = {
        queryKey    => 'all',
        attachments => { members => 1 },
        constraints => $params
    };

    my $result = request( 'project.search', $data );
    if ( exists $result->{result}{data} && @{ $result->{result}{data} } ) {
        # If name is used as a query param, we need to loop through and look
        # for exact match as Conduit will tokenize the name instead of doing
        # exact string match :( If name is not used, then return first one.
        if ( exists $params->{name} ) {
            foreach my $item ( @{ $result->{result}{data} } ) {
                next if $item->{fields}{name} ne $params->{name};
                return $class->new($item);
            }
        }
        else {
            return $class->new( $result->{result}{data}[0] );
        }
    }
}

sub BUILDARGS {
    my ( $class, $params ) = @_;

    $params->{name}            = $params->{fields}->{name};
    $params->{description}     = $params->{fields}->{description};
    $params->{creation_ts}     = $params->{fields}->{dateCreated};
    $params->{modification_ts} = $params->{fields}->{dateModified};
    $params->{view_policy}     = $params->{fields}->{policy}->{view};
    $params->{edit_policy}     = $params->{fields}->{policy}->{edit};
    $params->{join_policy}     = $params->{fields}->{policy}->{join};
    $params->{members_raw}     = $params->{attachments}->{members}->{members};

    delete $params->{fields};
    delete $params->{attachments};

    return $params;
}

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
#           "view": "secure-revision",
#           "edit": "secure-revision",
#           "join": "secure-revision"
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
#     Modification      #
#########################

sub create {
    my ( $class, $params ) = @_;

    my $name = trim( $params->{name} );
    $name || ThrowCodeError( 'param_required', { param => 'name' } );

    my $description = $params->{description} || 'Need description';
    my $view_policy = $params->{view_policy};
    my $edit_policy = $params->{edit_policy};
    my $join_policy = $params->{join_policy};

    my $data = {
        transactions => [
            { type => 'name',        value => $name },
            { type => 'description', value => $description },
            { type => 'edit',        value => $edit_policy },
            { type => 'join',        value => $join_policy },
            { type => 'view',        value => $view_policy },
            { type => 'icon',        value => 'group' },
            { type => 'color',       value => 'red' }
        ]
    };

    my $result = request( 'project.edit', $data );

    return $class->new_from_query(
        { phids => [ $result->{result}{object}{phid} ] } );
}

sub update {
    my ($self) = @_;

    my $data = {
        objectIdentifier => $self->phid,
        transactions     => []
    };

    if ( $self->{set_name} ) {
        push(
            @{ $data->{transactions} },
            {
                type  => 'name',
                value => $self->{set_name}
            }
        );
    }

    if ( $self->{set_description} ) {
        push(
            @{ $data->{transactions} },
            {
                type  => 'description',
                value => $self->{set_description}
            }
        );
    }

    if ( $self->{set_members} ) {
        push(
            @{ $data->{transactions} },
            {
                type  => 'members.set',
                value => $self->{set_members}
            }
        );
    }
    else {
        if ( $self->{add_members} ) {
            push(
                @{ $data->{transactions} },
                {
                    type  => 'members.add',
                    value => $self->{add_members}
                }
            );
        }

        if ( $self->{remove_members} ) {
            push(
                @{ $data->{transactions} },
                {
                    type  => 'members.remove',
                    value => $self->{remove_members}
                }
            );
        }
    }

    if ( $self->{set_policy} ) {
        foreach my $name ( "view", "edit" ) {
            next unless $self->{set_policy}->{$name};
            push(
                @{ $data->{transactions} },
                {
                    type  => $name,
                    value => $self->{set_policy}->{$name}
                }
            );
        }
    }

    if ($self->{add_projects}) {
        push(@{ $data->{transactions} }, {
            type => 'projects.add',
            value => $self->{add_projects}
        });
    }

    if ($self->{remove_projects}) {
        push(@{ $data->{transactions} }, {
            type => 'projects.remove',
            value => $self->{remove_projects}
        });
    }

    my $result = request( 'project.edit', $data );

    return $result;
}

#########################
#       Mutators        #
#########################

sub set_name {
    my ( $self, $name ) = @_;
    $name = trim($name);
    $self->{set_name} = $name;
}

sub set_description {
    my ( $self, $description ) = @_;
    $description = trim($description);
    $self->{set_description} = $description;
}

sub add_member {
    my ( $self, $member ) = @_;
    $self->{add_members} ||= [];
    my $member_phid = blessed $member ? $member->phab_phid : $member;
    push( @{ $self->{add_members} }, $member_phid );
}

sub remove_member {
    my ( $self, $member ) = @_;
    $self->{remove_members} ||= [];
    my $member_phid = blessed $member ? $member->phab_phid : $member;
    push( @{ $self->{remove_members} }, $member_phid );
}

sub set_members {
    my ( $self, $members ) = @_;
    $self->{set_members} = [ map { $_->phab_phid } @$members ];
}

sub set_policy {
    my ( $self, $name, $policy ) = @_;
    $self->{set_policy} ||= {};
    $self->{set_policy}->{$name} = $policy;
}

############
# Builders #
############

sub _build_members {
    my ($self) = @_;
    return [] unless $self->members_raw;

    my @phids;
    foreach my $member ( @{ $self->members_raw } ) {
        push( @phids, $member->{phid} );
    }

    return [] if !@phids;

    my $users = get_phab_bmo_ids( { phids => \@phids } );

    my @members;
    foreach my $user (@$users) {
        my $member = Bugzilla::User->new( { id => $user->{id}, cache => 1 } );
        $member->{phab_phid} = $user->{phid};
        push( @members, $member );
    }

    return \@members;
}

1;

