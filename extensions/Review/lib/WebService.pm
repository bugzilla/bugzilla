# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Review::WebService;

use strict;
use warnings;

use base qw(Bugzilla::WebService);

use Bugzilla::Bug;
use Bugzilla::Component;
use Bugzilla::Error;
use Bugzilla::Util qw(detaint_natural trick_taint);
use Bugzilla::WebService::Util 'filter';

sub suggestions {
    my ($self, $params) = @_;
    my $dbh = Bugzilla->switch_to_shadow_db();

    my ($bug, $product, $component);
    if (exists $params->{bug_id}) {
        $bug = Bugzilla::Bug->check($params->{bug_id});
        $product = $bug->product_obj;
        $component = $bug->component_obj;
    }
    elsif (exists $params->{product}) {
        $product = Bugzilla::Product->check($params->{product});
        if (exists $params->{component}) {
            $component = Bugzilla::Component->check({
                product => $product, name => $params->{component}
            });
        }
    }
    else {
        ThrowUserError("reviewer_suggestions_param_required");
    }

    my @reviewers;
    if ($bug) {
        # we always need to be authentiated to perform user matching
        my $user = Bugzilla->user;
        if (!$user->id) {
            Bugzilla->set_user(Bugzilla::User->check({ name => 'nobody@mozilla.org' }));
            push @reviewers, @{ $bug->mentors };
            Bugzilla->set_user($user);
        } else {
            push @reviewers, @{ $bug->mentors };
        }
    }
    if ($component) {
        push @reviewers, @{ $component->reviewers_objs };
    }
    if (!@{ $component->reviewers_objs }) {
        push @reviewers, @{ $product->reviewers_objs };
    }

    my @result;
    foreach my $reviewer (@reviewers) {
        push @result, {
            id    => $self->type('int', $reviewer->id),
            email => $self->type('email', $reviewer->login),
            name  => $self->type('string', $reviewer->name),
            review_count => $self->type('int', $reviewer->review_count),
        };
    }
    return \@result;
}

sub flag_activity {
    my ($self, $params) = @_;
    my $dbh = Bugzilla->switch_to_shadow_db();
    my %match_criteria;

    if (my $flag_id = $params->{flag_id}) {
        detaint_natural($flag_id)
          or ThrowUserError('invalid_flag_id', { flag_id => $flag_id });

        $match_criteria{flag_id} = $flag_id;
    }

    if (my $flag_ids = $params->{flag_ids}) {
        foreach my $flag_id (@$flag_ids) {
            detaint_natural($flag_id)
              or ThrowUserError('invalid_flag_id', { flag_id => $flag_id });
        }

        $match_criteria{flag_id} = $flag_ids;
    }

    if (my $type_id = $params->{type_id}) {
        detaint_natural($type_id)
          or ThrowUserError('invalid_flag_type_id', { type_id => $type_id });

        $match_criteria{type_id} = $type_id;
    }

    if (my $type_name = $params->{type_name}) {
        trick_taint($type_name);
        my $flag_types = Bugzilla::FlagType::match({ name => $type_name });
        $match_criteria{type_id} = [map { $_->id } @$flag_types];
    }

    for my $user_field (qw( requestee setter )) {
        if (my $user_name = $params->{$user_field}) {
            my $user = Bugzilla::User->check({ name => $user_name, cache => 1, _error => 'invalid_username' });

            $match_criteria{ $user_field . "_id" } = $user->id;
        }
    }

    ThrowCodeError('param_required', { param => 'limit', function => 'Review.flag_activity()' })
      if defined $params->{offset} && !defined $params->{limit};

    my $limit       = delete $params->{limit};
    my $offset      = delete $params->{offset};
    my $max_results = Bugzilla->params->{max_search_results};

    if (!$limit || $limit > $max_results) {
        $limit = $max_results;
    }

    $match_criteria{LIMIT} = $limit;
    $match_criteria{OFFSET} = $offset if defined $offset;

    # Throw error if no other parameters have been passed other than limit and offset
    if (!grep(!/^(LIMIT|OFFSET)$/, keys %match_criteria)) {
        ThrowUserError('flag_activity_parameters_required');
    }

    my $matches = Bugzilla::Extension::Review::FlagStateActivity->match(\%match_criteria);
    my $user    = Bugzilla->user;
    $user->visible_bugs([ map { $_->bug_id } @$matches ]);
    my @results = map  { $self->_flag_state_activity_to_hash($_, $params) }
                  grep { $user->can_see_bug($_->bug_id) && _can_see_attachment($user, $_) }
                  @$matches;
    return \@results;
}

sub _can_see_attachment {
    my ($user, $flag_state_activity) = @_;

    return 1 if !$flag_state_activity->attachment_id;
    return 0 if $flag_state_activity->attachment->isprivate && !$user->is_insider;
    return 1;
}

sub rest_resources {
    return [
        # bug-id
        qr{^/review/suggestions/(\d+)$}, {
            GET => {
                method => 'suggestions',
                params => sub {
                    return { bug_id => $_[0] };
                },
            },
        },
        # product/component
        qr{^/review/suggestions/([^/]+)/(.+)$}, {
            GET => {
                method => 'suggestions',
                params => sub {
                    return { product => $_[0], component => $_[1] };
                },
            },
        },
        # just product
        qr{^/review/suggestions/([^/]+)$}, {
            GET => {
                method => 'suggestions',
                params => sub {
                    return { product => $_[0] };
                },
            },
        },
        # named parameters
        qr{^/review/suggestions$}, {
            GET => {
                method => 'suggestions',
            },
        },
        # flag activity by flag id
        qr{^/review/flag_activity/(\d+)$}, {
            GET => {
                method => 'flag_activity',
                params => sub {
                    return { flag_id => $_[0] }
                },
            },
        },
        qr{^/review/flag_activity/type_name/(\w+)$}, {
            GET => {
                method => 'flag_activity',
                params => sub {
                    return { type_name => $_[0] }
                },
            },
        },
        # flag activity by user
        qr{^/review/flag_activity/(requestee|setter|type_id)/(.*)$}, {
            GET => {
                method => 'flag_activity',
                params => sub {
                    return { $_[0] => $_[1] };
                },
            },
        },
        # flag activity with only query strings
        qr{^/review/flag_activity$}, {
            GET => { method => 'flag_activity' },
        },
    ];
}

sub _flag_state_activity_to_hash {
    my ($self, $fsa, $params) = @_;

    my %flag = (
        id            => $self->type('int', $fsa->id),
        creation_time => $self->type('string', $fsa->flag_when),
        type          => $self->_flagtype_to_hash($fsa->type),
        setter        => $self->_user_to_hash($fsa->setter),
        bug_id        => $self->type('int',    $fsa->bug_id),
        attachment_id => $self->type('int',    $fsa->attachment_id),
        status        => $self->type('string', $fsa->status),
    );

    $flag{requestee} = $self->_user_to_hash($fsa->requestee) if $fsa->requestee;
    $flag{flag_id}   = $self->type('int', $fsa->flag_id) unless $params->{flag_id};

    return filter($params, \%flag);
}

sub _flagtype_to_hash {
    my ($self, $flagtype) = @_;
    my $user = Bugzilla->user;

    return {
        id               => $self->type('int',     $flagtype->id),
        name             => $self->type('string',  $flagtype->name),
        description      => $self->type('string',  $flagtype->description),
        type             => $self->type('string',  $flagtype->target_type),
        is_active        => $self->type('boolean', $flagtype->is_active),
        is_requesteeble  => $self->type('boolean', $flagtype->is_requesteeble),
        is_multiplicable => $self->type('boolean', $flagtype->is_multiplicable),
    };
}

sub _user_to_hash {
    my ($self, $user) = @_;

    return {
        id        => $self->type('int',    $user->id),
        real_name => $self->type('string', $user->name),
        name      => $self->type('email',  $user->login),
    };
}

1;
__END__
=head1 NAME

Bugzilla::Extension::Review::WebService - Functions for the Mozilla specific
'review' flag optimisations.

=head1 METHODS

See L<Bugzilla::WebService> for a description of how parameters are passed,
and what B<STABLE>, B<UNSTABLE>, and B<EXPERIMENTAL> mean.

Although the data input and output is the same for JSONRPC, XMLRPC and REST,
the directions for how to access the data via REST is noted in each method
where applicable.

=head2 suggestions

B<EXPERIMENTAL>

=over

=item B<Description>

Returns the list of suggestions for reviewers.

=item B<REST>

GET /rest/review/suggestions/C<bug-id>

GET /rest/review/suggestions/C<product-name>

GET /rest/review/suggestions/C<product-name>/C<component-name>

GET /rest/review/suggestions?product=C<product-name>

GET /rest/review/suggestions?product=C<product-name>&component=C<component-name>

The returned data format is the same as below.

=item B<Params>

Query by Bug:

=over

=over

=item C<bug_id> (integer) - The bug ID.

=back

=back

Query by Product or Component:

=over

=over

=item C<product> (string) - The product name.

=item C<component> (string) - The component name (optional).  If providing a C<component>, a C<product> must also be provided.

=back

=back

=item B<Returns>

An array of hashes with the following keys/values:

=over

=item C<id> (integer) - The user's ID.

=item C<email> (string) - The user's email address (aka login).

=item C<name> (string) - The user's display name (may not match the Bugzilla "real name").

=item C<review_count> (string) - The number of "review" and "feedback" requests in the user's queue.

=back

=back

=head2 flag_activity

B<EXPERIMENTAL>

=over

=item B<Description>

Returns the history of flag status changes based on requestee, setter, flag_id, type_id, or all.

=item B<REST>

GET /rest/review/flag_activity/C<flag_id>

GET /rest/review/flag_activity/requestee/C<requestee>

GET /rest/review/flag_activity/setter/C<setter>

GET /rest/review/flag_activity/type_id/C<type_id>

GET /rest/review/flag_activity/type_name/C<type_name>

GET /rest/review/flag_activity

The returned data format is the same as below.

=item B<Params>

Use one or more of the following parameters to find specific flag status changes.

=over

=item C<flag_id> (integer) - The flag ID.

Note that searching by C<flag_id> is not reliable because when flags are removed, flag_ids cease to exist.

=item C<requestee> (string) - The bugzilla login of the flag's requestee

=item C<setter> (string) - The bugzilla login of the flag's setter

=item C<type_id> (int) - The flag type id of a change

=item C<type_name> (string) - the flag type name of a change

=back

=item B<Returns>

An array of hashes with the following keys/values:

=over

=item C<flag_id> (integer)

The id of the flag that changed. This field may be absent after a flag is deleted.

=item C<creation_time> (dateTime)

Timestamp of when the flag status changed.

=item C<type> (object)

An object with the following fields:

=over

=item C<id> (integer)

The flag type id of the flag that changed

=item C<name> (string)

The name of the flag type (review, feedback, etc)

=item C<description> (string)

A plain english description of the flag type.

=item C<type> (string)

The content of the target_type field of the flagtypes table.

=item C<is_active> (boolean)

Boolean flag indicating if the flag type is available for use.

=item C<is_requesteeble> (boolean)

Boolean flag indicating if the flag type is requesteeable.

=item C<is_multiplicable> (boolean)

Boolean flag indicating if the flag type is multiplicable.

=back

=item C<setter> (object)

The setter is the bugzilla user that set the flag. It is represented by an object with the following fields.

=over

=item C<id> (integer)

The id of the bugzilla user. A unique integer value.

=item C<real_name> (string)

The real name of the bugzilla user. 

=item C<name> (string)

The bugzilla login of the bugzilla user (typically an email address).

=back

=item C<requestee> (object)

The requestee is the bugzilla user that is specified by the flag. Optional - absent if there is no requestee.

Requestee has the same keys/values as the setter object.

=item C<bug_id> (integer)

The id of the bugzilla bug that the changed flag belongs to.

=item C<attachment_id> (integer)

The id of the bugzilla attachment that the changed flag belongs to.

=item C<status> (string)

The status of the bugzilla flag that changed. One of C<+ - ? X>.

=back

=back
