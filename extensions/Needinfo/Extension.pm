# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Extension::Needinfo;

use strict;

use base qw(Bugzilla::Extension);

use Bugzilla::Error;
use Bugzilla::Flag;
use Bugzilla::FlagType;
use Bugzilla::User;

our $VERSION = '0.01';

sub install_update_db {
    my ($self, $args) = @_;
    my $dbh = Bugzilla->dbh;

    if (@{ Bugzilla::FlagType::match({ name => 'needinfo' }) }) {
        return;
    }

    print "Creating needinfo flag ... " . 
          "enable the Needinfo feature by editing the flag's properties.\n";

    # Initially populate the list of exclusions as __Any__:__Any__ to
    # allow admin to decide which products to enable the flag for.
    my $flagtype = Bugzilla::FlagType->create({
        name        => 'needinfo',
        description => "Set this flag when the bug is in need of additional information",
        target_type => 'bug',
        cc_list     => '',
        sortkey     => 1,
        is_active   => 1,
        is_requestable   => 1,
        is_requesteeble  => 1,
        is_multiplicable => 0,
        request_group    => '',
        grant_group      => '',
        inclusions       => [],
        exclusions       => ['0:0'],
    });
}

# Clear the needinfo? flag if comment is being given by
# requestee or someone used the override flag.
sub bug_start_of_update {
    my ($self, $args) = @_;
    my $bug       = $args->{bug};
    my $old_bug   = $args->{old_bug};

    my $user   = Bugzilla->user;
    my $cgi    = Bugzilla->cgi;
    my $params = Bugzilla->input_params;

    if ($params->{needinfo}) {
        # do a match if applicable
        Bugzilla::User::match_field({
            'needinfo_from' => { 'type' => 'multi' }
        });
    }

    # Set needinfo_done param to true so as to not loop back here
    return if $params->{needinfo_done};
    $params->{needinfo_done} = 1;
    Bugzilla->input_params($params);

    my $add_needinfo  = delete $params->{needinfo};
    my $needinfo_from = delete $params->{needinfo_from};
    my $needinfo_role = delete $params->{needinfo_role};
    my $is_private    = $params->{'comment_is_private'};

    my @needinfo_overrides;
    foreach my $key (grep(/^needinfo_override_/, keys %$params)) {
        my ($id) = $key =~ /(\d+)$/;
        # Should always be true if key exists (checkbox) but better to be sure
        push(@needinfo_overrides, $id) if $id && $params->{$key};
    }

    # Set the needinfo flag if user is requesting more information
    my @new_flags;
    my $needinfo_requestee;

    if ($add_needinfo) {
        foreach my $type (@{ $bug->flag_types }) {
            next if $type->name ne 'needinfo';
            my %requestees;

            # Allow anyone to be the requestee
            if (!$needinfo_role) {
                $requestees{'anyone'} = 1;
            }
            # Use assigned_to as requestee
            elsif ($needinfo_role eq 'assigned_to') {
                $requestees{$bug->assigned_to->login} = 1;
            }
            # Use reporter as requestee
            elsif ($needinfo_role eq 'reporter') {
                $requestees{$bug->reporter->login} = 1;
            }
            # Use qa_contact as requestee
            elsif ($needinfo_role eq 'qa_contact') {
                $requestees{$bug->qa_contact->login} = 1;
            }
            # Use user specified requestee
            elsif ($needinfo_role eq 'other' && $needinfo_from) {
                my @needinfo_from_list = ref $needinfo_from
                                         ? @$needinfo_from :
                                         ($needinfo_from);
                foreach my $requestee (@needinfo_from_list) {
                    my $requestee_obj = Bugzilla::User->check($requestee);
                    $requestees{$requestee_obj->login} = 1;
                }
            }

            # Find out if the requestee has already been used and skip if so
            my $requestee_found;
            foreach my $flag (@{ $type->{flags} }) {
                if (!$flag->requestee && $requestees{'anyone'}) {
                    delete $requestees{'anyone'};
                }
                if ($flag->requestee && $requestees{$flag->requestee->login}) {
                    delete $requestees{$flag->requestee->login};
                }
            }

            foreach my $requestee (keys %requestees) {
                my $needinfo_flag = { type_id => $type->id, status => '?' };
                if ($requestee ne 'anyone') {
                    $needinfo_flag->{requestee} = $requestee;
                }
                push(@new_flags, $needinfo_flag);
            }
        }
    }

    my @flags;
    foreach my $flag (@{ $bug->flags }) {
        next if $flag->type->name ne 'needinfo';
        # Clear if somehow the flag has been set to +/-
        # or if the "clear needinfo" override checkbox is selected
        if ($flag->status ne '?'
            or grep { $_ == $flag->id } @needinfo_overrides)
        {
            push(@flags, { id => $flag->id, status => 'X' });
        }
    }

    if (@flags || @new_flags) {
        $bug->set_flags(\@flags, \@new_flags);
    }
}

sub object_before_delete {
    my ($self, $args) = @_;
    my $object = $args->{object};
    return unless $object->isa('Bugzilla::Flag')
                  && $object->type->name eq 'needinfo';
    my $user = Bugzilla->user;

    # Require canconfirm to clear requests targetted at someone else
    if ($object->setter_id != $user->id
        && $object->requestee
        && $object->requestee->id != $user->id
        && !$user->in_group('canconfirm'))
    {
        ThrowUserError('needinfo_illegal_change');
    }
}

__PACKAGE__->NAME;
