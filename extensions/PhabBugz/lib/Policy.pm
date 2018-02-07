# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::Policy;

use 5.10.1;
use Moo;

use Bugzilla::Error;
use Bugzilla::Extension::PhabBugz::Util qw(request);
use Bugzilla::Extension::PhabBugz::Project;

use List::Util qw(first);

use Types::Standard -all;
use Type::Utils;

has 'phid'      => ( is => 'ro', isa => Str );
has 'type'      => ( is => 'ro', isa => Str );
has 'name'      => ( is => 'ro', isa => Str );
has 'shortName' => ( is => 'ro', isa => Str );
has 'fullName'  => ( is => 'ro', isa => Str );
has 'href'      => ( is => 'ro', isa => Maybe[Str] );
has 'workflow'  => ( is => 'ro', isa => Maybe[Str] );
has 'icon'      => ( is => 'ro', isa => Str );
has 'default'   => ( is => 'ro', isa => Str );
has 'rules' => (
    is  => 'ro',
    isa => ArrayRef[
        Dict[
            action => Str,
            rule   => Str,
            value  => Maybe[ArrayRef[Str]]
        ]
    ]
);

has 'rule_projects' => (
    is => 'lazy',
    isa => ArrayRef[Str],
);

# {
#   "data": [
#     {
#       "phid": "PHID-PLCY-l2mt4yeq4byqgcot7x4j",
#       "type": "custom",
#       "name": "Custom Policy",
#       "shortName": "Custom Policy",
#       "fullName": "Custom Policy",
#       "href": null,
#       "workflow": null,
#       "icon": "fa-certificate",
#       "default": "deny",
#       "rules": [
#         {
#           "action": "allow",
#           "rule": "PhabricatorSubscriptionsSubscribersPolicyRule",
#           "value": null
#         },
#         {
#           "action": "allow",
#           "rule": "PhabricatorProjectsPolicyRule",
#           "value": [
#             "PHID-PROJ-cvurjiwfvh756mv2vhvi"
#           ]
#         }
#       ]
#     }
#   ],
#   "cursor": {
#     "limit": 100,
#     "after": null,
#     "before": null
#   }
# }

sub new_from_query {
    my ($class, $params) = @_;
    my $result = request('policy.query', $params);
    if (exists $result->{result}{data} && @{ $result->{result}{data} }) {
        return $result->{result}->{data}->[0];
    }
    return $class->new($result);
}

sub create {
    my ($class, $project_names) = @_;

    my $data = {
        objectType => 'DREV',
        default    => 'deny',
        policy     => [
            {
                action => 'allow',
                rule   => 'PhabricatorSubscriptionsSubscribersPolicyRule',
            }
        ]
    };

    if (@$project_names) {
        my $project_phids = [];
        foreach my $project_name (@$project_names) {
            my $project = Bugzilla::Extension::PhabBugz::Project->new({ name => $project_name });
            push @$project_phids, $project->phid if $project;
        }

        ThrowUserError('invalid_phabricator_sync_groups') unless @$project_phids;

        push @{ $data->{policy} }, {
            action => 'allow',
            rule   => 'PhabricatorProjectsPolicyRule',
            value  => $project_phids,
        };
    }
    else {
        push @{ $data->{policy} }, { action => 'allow', value  => 'admin' };
    }

    my $result = request('policy.create', $data);
    return $class->new_from_query({ phids => [ $result->{result}{phid} ] });
}

sub _build_rule_projects {
    my ($self) = @_;

    return [] unless $self->rules;
    my $rule = first { $_->{rule} eq 'PhabricatorProjectsPolicyRule'} @{ $self->rules };
    return [] unless $rule;
    return [
        map  { $_->name }
        grep { $_ }
        map  { Bugzilla::Extension::PhabBugz::Project->new( { phids => [$_] } ) }
        @{ $rule->{value} }
    ];
}

1;