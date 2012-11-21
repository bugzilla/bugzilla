# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Extension::Needinfo;

use strict;

use base qw(Bugzilla::Extension);

use Bugzilla::User;
use Bugzilla::Flag;
use Bugzilla::FlagType;

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

    # Set needinfo_done param to true so as to not loop back here
    return if $params->{needinfo_done};
    $params->{needinfo_done} = 1;
    Bugzilla->input_params($params);

    # do a match if applicable
    Bugzilla::User::match_field({ 
        'needinfo_from' => { 'type' => 'single' }
    });

    my $needinfo      = delete $params->{needinfo};
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

    if ($user->in_group('canconfirm') && $needinfo) {
        foreach my $type (@{ $bug->flag_types }) {
            next if $type->name ne 'needinfo';

            my $needinfo_flag = { type_id => $type->id, status => '?' };

            # Use assigned_to as requestee
            if ($needinfo_role eq 'assigned_to') {
                $needinfo_flag->{requestee} = $bug->assigned_to->login;
            }
            # Use reporter as requestee
            elsif ( $needinfo_role eq 'reporter') {
                $needinfo_flag->{requestee} = $bug->reporter->login;
            }
            # Use qa_contact as requestee
            elsif ($needinfo_role eq 'qa_contact') {
                $needinfo_flag->{requestee} = $bug->qa_contact->login;
            }
            # Use user specified requestee
            elsif ($needinfo_role eq 'other' && $needinfo_from) {
                Bugzilla::User->check($needinfo_from);
                $needinfo_flag->{requestee} = $needinfo_from;
            }

            if ($needinfo) {
                push(@new_flags, $needinfo_flag);
                last;
            }
        }
    }

    # Clear the flag if bug is being closed or if additional
    # information was given as requested
    my @flags;
    foreach my $flag (@{ $bug->flags }) {
        next if $flag->type->name ne 'needinfo';
        my $clear_needinfo = 0;

        # Clear if somehow the flag has been set to +/-
        $clear_needinfo = 1 if $flag->status ne '?';

        # Clear if current user has selected override
        $clear_needinfo = 1 if grep($_ == $flag->id, @needinfo_overrides);

        # Clear if bug is being closed
        if (($bug->bug_status ne $old_bug->bug_status)
            && !$old_bug->status->is_open)
        {
            $clear_needinfo = 1;
        }

        # Clear if comment provided by the proper requestee
        if ($bug->{added_comments}
            && (!$flag->requestee || $flag->requestee->login eq Bugzilla->user->login)
            && (!$is_private || $flag->setter->is_insider))
        {
            $clear_needinfo = 1;
        }

        if ($clear_needinfo) {
            push(@flags, { id => $flag->id, status => 'X' });
        }
    }

    if (@flags || @new_flags) {
        $bug->set_flags(\@flags, \@new_flags);
    }
}

__PACKAGE__->NAME;
