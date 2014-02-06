# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# Contributor(s): Marc Schumann <wurblzap@gmail.com>
#                 Max Kanat-Alexander <mkanat@bugzilla.org>
#                 Mads Bondo Dydensborg <mbd@dbc.dk>
#                 Noura Elhawary <nelhawar@redhat.com>

package Bugzilla::WebService::User;

use strict;
use base qw(Bugzilla::WebService);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Group;
use Bugzilla::User;
use Bugzilla::Util qw(trim);
use Bugzilla::WebService::Util qw(filter filter_wants validate);
use Bugzilla::Hook;

use List::Util qw(first);

# Don't need auth to login
use constant LOGIN_EXEMPT => {
    login => 1,
    offer_account_by_email => 1,
};

use constant READ_ONLY => qw(
    get
);

##############
# User Login #
##############

sub login {
    my ($self, $params) = @_;
    my $remember = $params->{remember};

    # Username and password params are required 
    foreach my $param ("login", "password") {
        defined $params->{$param} 
            || ThrowCodeError('param_required', { param => $param });
    }

    # Convert $remember from a boolean 0/1 value to a CGI-compatible one.
    if (defined($remember)) {
        $remember = $remember? 'on': '';
    }
    else {
        # Use Bugzilla's default if $remember is not supplied.
        $remember =
            Bugzilla->params->{'rememberlogin'} eq 'defaulton'? 'on': '';
    }

    # Make sure the CGI user info class works if necessary.
    my $input_params = Bugzilla->input_params;
    $input_params->{'Bugzilla_login'} =  $params->{login};
    $input_params->{'Bugzilla_password'} = $params->{password};
    $input_params->{'Bugzilla_remember'} = $remember;

    my $user = Bugzilla->login();

    my $result = { id => $self->type('int', $user->id) };

    # We will use the stored cookie value combined with the user id
    # to create a token that can be used with future requests in the
    # query parameters
    my $login_cookie = first { $_->name eq 'Bugzilla_logincookie' }
                              @{ Bugzilla->cgi->{'Bugzilla_cookie_list'} };
    if ($login_cookie) {
        $result->{'token'} = $user->id . "-" . $login_cookie->value;
    }

    return $result;
}

sub logout {
    my $self = shift;
    Bugzilla->logout;
}

sub valid_login {
    my ($self, $params) = @_;
    defined $params->{login}
        || ThrowCodeError('param_required', { param => 'login' });
    Bugzilla->login();
    if (Bugzilla->user->id && Bugzilla->user->login eq $params->{login}) {
        return $self->type('boolean', 1);
    }
    return $self->type('boolean', 0);
}

#################
# User Creation #
#################

sub offer_account_by_email {
    my $self = shift;
    my ($params) = @_;
    my $email = trim($params->{email})
        || ThrowCodeError('param_required', { param => 'email' });

    Bugzilla->user->check_account_creation_enabled;
    Bugzilla->user->check_and_send_account_creation_confirmation($email);
    return undef;
}

sub create {
    my $self = shift;
    my ($params) = @_;

    Bugzilla->user->in_group('editusers') 
        || ThrowUserError("auth_failure", { group  => "editusers",
                                            action => "add",
                                            object => "users"});

    my $email = trim($params->{email})
        || ThrowCodeError('param_required', { param => 'email' });
    my $realname = trim($params->{full_name});
    my $password = trim($params->{password}) || '*';

    my $user = Bugzilla::User->create({
        login_name    => $email,
        realname      => $realname,
        cryptpassword => $password
    });

    return { id => $self->type('int', $user->id) };
}


# function to return user information by passing either user ids or 
# login names or both together:
# $call = $rpc->call( 'User.get', { ids => [1,2,3], 
#         names => ['testusera@redhat.com', 'testuserb@redhat.com'] });
sub get {
    my ($self, $params) = validate(@_, 'names', 'ids', 'match', 'group_ids', 'groups');

    Bugzilla->switch_to_shadow_db();

    defined($params->{names}) || defined($params->{ids})
        || defined($params->{match})
        || ThrowCodeError('params_required', 
               { function => 'User.get', params => ['ids', 'names', 'match'] });

    my @user_objects;
    @user_objects = map { Bugzilla::User->check($_) } @{ $params->{names} }
                    if $params->{names};

    # start filtering to remove duplicate user ids
    my %unique_users = map { $_->id => $_ } @user_objects;
    @user_objects = values %unique_users;
      
    my @users;

    # If the user is not logged in: Return an error if they passed any user ids.
    # Otherwise, return a limited amount of information based on login names.
    if (!Bugzilla->user->id){
        if ($params->{ids}){
            ThrowUserError("user_access_by_id_denied");
        }
        if ($params->{match}) {
            ThrowUserError('user_access_by_match_denied');
        }
        my $in_group = $self->_filter_users_by_group(
            \@user_objects, $params);
        @users = map {filter $params, {
                     id        => $self->type('int', $_->id),
                     real_name => $self->type('string', $_->name),
                     name      => $self->type('email', $_->login),
                 }} @$in_group;

        return { users => \@users };
    }

    my $obj_by_ids;
    $obj_by_ids = Bugzilla::User->new_from_list($params->{ids}) if $params->{ids};

    # obj_by_ids are only visible to the user if he can see 
    # the otheruser, for non visible otheruser throw an error
    foreach my $obj (@$obj_by_ids) {
        if (Bugzilla->user->can_see_user($obj)){
            if (!$unique_users{$obj->id}) {
                push (@user_objects, $obj);
                $unique_users{$obj->id} = $obj;
            }
        }
        else {
            ThrowUserError('auth_failure', {reason => "not_visible",
                                            action => "access",
                                            object => "user",
                                            userid => $obj->id});
        }
    }
    
    # User Matching
    my $limit;
    if ($params->{'maxusermatches'}) {
        $limit = $params->{'maxusermatches'} + 1;
    }
    my $exclude_disabled = $params->{'include_disabled'} ? 0 : 1;
    foreach my $match_string (@{ $params->{'match'} || [] }) {
        my $matched = Bugzilla::User::match($match_string, $limit, $exclude_disabled);
        foreach my $user (@$matched) {
            if (!$unique_users{$user->id}) {
                push(@user_objects, $user);
                $unique_users{$user->id} = $user;
            }
        }
    }

    my $in_group = $self->_filter_users_by_group(\@user_objects, $params);
    foreach my $user (@$in_group) {
        my $user_info = {
            id        => $self->type('int', $user->id),
            real_name => $self->type('string', $user->name),
            name      => $self->type('email', $user->login),
            email     => $self->type('email', $user->email),
            can_login => $self->type('boolean', $user->is_enabled ? 1 : 0),
        };

        if (Bugzilla->user->in_group('editusers')) {
            $user_info->{email_enabled}     = $self->type('boolean', $user->email_enabled);
            $user_info->{login_denied_text} = $self->type('string', $user->disabledtext);
        }

        if (Bugzilla->user->id == $user->id) {
            if (filter_wants($params, 'saved_searches')) {
                $user_info->{saved_searches} = [
                    map { $self->_query_to_hash($_) } @{ $user->queries }
                ];
            }
        }

        if (filter_wants($params, 'groups')) {
            if (Bugzilla->user->id == $user->id || Bugzilla->user->in_group('editusers')) {
                $user_info->{groups} = [
                    map { $self->_group_to_hash($_) } @{ $user->groups }
                ];
            }
            else {
                $user_info->{groups} = $self->_filter_bless_groups($user->groups);
            }
        }

        push(@users, filter($params, $user_info));
    }

    Bugzilla::Hook::process('webservice_user_get', 
        { webservice => $self, params => $params, users => \@users });

    return { users => \@users };
}

sub _filter_users_by_group {
    my ($self, $users, $params) = @_;
    my ($group_ids, $group_names) = @$params{qw(group_ids groups)};

    # If no groups are specified, we return all users.
    return $users if (!$group_ids and !$group_names);

    my $user = Bugzilla->user;

    my @groups = map { Bugzilla::Group->check({ id => $_ }) } 
                     @{ $group_ids || [] };

    if ($group_names) {
        foreach my $name (@$group_names) {
            my $group = Bugzilla::Group->check({ name => $name, _error => 'invalid_group_name' });
            $user->in_group($group) || ThrowUserError('invalid_group_name', { name => $name });
            push(@groups, $group);
        }
    }

    my @in_group = grep { $self->_user_in_any_group($_, \@groups) }
                        @$users;
    return \@in_group;
}

sub _user_in_any_group {
    my ($self, $user, $groups) = @_;
    foreach my $group (@$groups) {
        return 1 if $user->in_group($group);
    }
    return 0;
}

sub _filter_bless_groups {
    my ($self, $groups) = @_;
    my $user = Bugzilla->user;

    my @filtered_groups;
    foreach my $group (@$groups) {
        next unless ($user->in_group('editusers') || $user->can_bless($group->id));
        push(@filtered_groups, $self->_group_to_hash($group));
    }

    return \@filtered_groups;
}

sub _group_to_hash {
    my ($self, $group) = @_;
    my $item = {
        id          => $self->type('int', $group->id), 
        name        => $self->type('string', $group->name), 
        description => $self->type('string', $group->description), 
    };
    return $item;
}

sub _query_to_hash {
    my ($self, $query) = @_;
    my $item = {
        id   => $self->type('int', $query->id),
        name => $self->type('string', $query->name),
        url  => $self->type('string', $query->url),
    };

    return $item;
}

1;

__END__

=head1 NAME

Bugzilla::Webservice::User - The User Account and Login API

=head1 DESCRIPTION

This part of the Bugzilla API allows you to create User Accounts and
log in/out using an existing account.

=head1 METHODS

See L<Bugzilla::WebService> for a description of how parameters are passed,
and what B<STABLE>, B<UNSTABLE>, and B<EXPERIMENTAL> mean.

Although the data input and output is the same for JSONRPC, XMLRPC and REST,
the directions for how to access the data via REST is noted in each method
where applicable.

=head1 Logging In and Out

=head2 login

B<STABLE>

=over

=item B<Description>

Logging in, with a username and password, is required for many
Bugzilla installations, in order to search for bugs, post new bugs,
etc. This method logs in an user.

=item B<Params>

=over

=item C<login> (string) - The user's login name.

=item C<password> (string) - The user's password.

=item C<remember> (bool) B<Optional> - if the cookies returned by the
call to login should expire with the session or not.  In order for
this option to have effect the Bugzilla server must be configured to
allow the user to set this option - the Bugzilla parameter
I<rememberlogin> must be set to "defaulton" or
"defaultoff". Addionally, the client application must implement
management of cookies across sessions.

=back

=item B<Returns>

On success, a hash containing two items, C<id>, the numeric id of the
user that was logged in, and a C<token> which can be passed in
the parameters as authentication in other calls. A set of http cookies
is also sent with the response. These cookies *or* the token can be sent
along with any future requests to the webservice, for the duration of the
session. Note that cookies are not accepted for GET requests for JSONRPC
and REST for security reasons. You may, however, use the token or valid
login parameters for those requests.

=item B<Errors>

=over

=item 300 (Invalid Username or Password)

The username does not exist, or the password is wrong.

=item 301 (Account Disabled)

The account has been disabled.  A reason may be specified with the
error.

=item 305 (New Password Required)

The current password is correct, but the user is asked to change
his password.

=item 50 (Param Required)

A login or password parameter was not provided.

=back

=back

=head2 logout

B<STABLE>

=over

=item B<Description>

Log out the user. Does nothing if there is no user logged in.

=item B<Params> (none)

=item B<Returns> (nothing)

=item B<Errors> (none)

=back

=head2 valid_login

B<UNSTABLE>

=over

=item B<Description>

This method will verify whether a client's cookies or current login
token is still valid or have expired. A valid username must be provided
as well that matches.

=item B<Params>

=over

=item C<login>

The login name that matches the provided cookies or token.

=item C<token>

(string) Persistent login token current being used for authentication (optional).
Cookies passed by client will be used before the token if both provided.

=back

=item B<Returns>

Returns true/false depending on if the current cookies or token are valid
for the provided username.

=item B<Errors> (none)

=item B<History>

=over

=item Added in Bugzilla B<5.0>.

=back

=back

=head1 Account Creation

=head2 offer_account_by_email

B<STABLE>

=over

=item B<Description>

Sends an email to the user, offering to create an account.  The user
will have to click on a URL in the email, and choose their password
and real name.

This is the recommended way to create a Bugzilla account.

=item B<Param>

=over

=item C<email> (string) - the email to send the offer to.

=back

=item B<Returns> (nothing)

=item B<Errors>

=over

=item 500 (Account Already Exists)

An account with that email address already exists in Bugzilla.

=item 501 (Illegal Email Address)

This Bugzilla does not allow you to create accounts with the format of
email address you specified. Account creation may be entirely disabled.

=back

=back

=head2 create

B<STABLE>

=over

=item B<Description>

Creates a user account directly in Bugzilla, password and all.
Instead of this, you should use L</offer_account_by_email> when
possible, because that makes sure that the email address specified can
actually receive an email. This function does not check that.

You must be logged in and have the C<editusers> privilege in order to
call this function.

=item B<REST>

POST /user

The params to include in the POST body as well as the returned data format,
are the same as below.

=item B<Params>

=over

=item C<email> (string) - The email address for the new user.

=item C<full_name> (string) B<Optional> - The user's full name. Will
be set to empty if not specified.

=item C<password> (string) B<Optional> - The password for the new user
account, in plain text.  It will be stripped of leading and trailing
whitespace.  If blank or not specified, the newly created account will
exist in Bugzilla, but will not be allowed to log in using DB
authentication until a password is set either by the user (through
resetting their password) or by the administrator.

=back

=item B<Returns>

A hash containing one item, C<id>, the numeric id of the user that was
created.

=item B<Errors>

The same as L</offer_account_by_email>. If a password is specified,
the function may also throw:

=over

=item 502 (Password Too Short)

The password specified is too short. (Usually, this means the
password is under three characters.)

=back

=item B<History>

=over

=item Error 503 (Password Too Long) removed in Bugzilla B<3.6>.

=item REST API call added in Bugzilla B<5.0>.

=back

=back

=head1 User Info

=head2 get

B<STABLE>

=over

=item B<Description>

Gets information about user accounts in Bugzilla.

=item B<REST>

To get information about a single user:

GET /user/<user_id_or_name>

To search for users by name, group using URL params same as below:

GET /user

The returned data format is the same as below.

=item B<Params>

B<Note>: At least one of C<ids>, C<names>, or C<match> must be specified.

B<Note>: Users will not be returned more than once, so even if a user 
is matched by more than one argument, only one user will be returned.

In addition to the parameters below, this method also accepts the
standard L<include_fields|Bugzilla::WebService/include_fields> and
L<exclude_fields|Bugzilla::WebService/exclude_fields> arguments.

=over

=item C<ids> (array) 

An array of integers, representing user ids.

Logged-out users cannot pass this parameter to this function. If they try,
they will get an error. Logged-in users will get an error if they specify
the id of a user they cannot see.

=item C<names> (array)

An array of login names (strings).

=item C<match> (array)

An array of strings. This works just like "user matching" in
Bugzilla itself. Users will be returned whose real name or login name
contains any one of the specified strings. Users that you cannot see will
not be included in the returned list.

Some Bugzilla installations have user-matching turned off, in which
case you will only be returned exact matches.

Most installations have a limit on how many matches are returned for
each string, which defaults to 1000 but can be changed by the Bugzilla
administrator.

Logged-out users cannot use this argument, and an error will be thrown
if they try. (This is to make it harder for spammers to harvest email
addresses from Bugzilla, and also to enforce the user visibility
restrictions that are implemented on some Bugzillas.)

=item C<group_ids> (array)

=item C<groups> (array)

C<group_ids> is an array of numeric ids for groups that a user can be in.
C<groups> is an array of names of groups that a user can be in.
If these are specified, they limit the return value to users who are
in I<any> of the groups specified.

=item C<include_disabled> (boolean)

By default, when using the C<match> parameter, disabled users are excluded
from the returned results unless their full username is identical to the
match string. Setting C<include_disabled> to C<true> will include disabled
users in the returned results even if their username doesn't fully match
the input string.

=item B<History>

=over

=item REST API call added in Bugzilla B<5.0>.

=back

=back

=item B<Returns> 

A hash containing one item, C<users>, that is an array of
hashes. Each hash describes a user, and has the following items:

=over

=item id

C<int> The unique integer ID that Bugzilla uses to represent this user. 
Even if the user's login name changes, this will not change.

=item real_name

C<string> The actual name of the user. May be blank.

=item email

C<string> The email address of the user.

=item name

C<string> The login name of the user. Note that in some situations this is 
different than their email.

=item can_login

C<boolean> A boolean value to indicate if the user can login into bugzilla. 

=item email_enabled

C<boolean> A boolean value to indicate if bug-related mail will be sent
to the user or not.

=item login_denied_text

C<string> A text field that holds the reason for disabling a user from logging
into bugzilla, if empty then the user account is enabled. Otherwise it is 
disabled/closed.

=item groups

C<array> An array of group hashes the user is a member of. Each hash describes
the group and contains the following items:

=over

=item id

C<int> The group id

=item name

C<string> The name of the group

=item description

C<string> The description for the group

=back

=over

=item saved_searches

C<array> An array of hashes, each of which represents a user's saved search and has
the following keys:

=over

=item id

C<int> An integer id uniquely identifying the saved search.

=item name

C<string> The name of the saved search.

=item url

C<string> The CGI parameters for the saved search.

=back

B<Note>: The elements of the returned array (i.e. hashes) are ordered by the 
name of each saved search.

=back

B<Note>: If you are not logged in to Bugzilla when you call this function, you
will only be returned the C<id>, C<name>, and C<real_name> items. If you are
logged in and not in editusers group, you will only be returned the C<id>, C<name>, 
C<real_name>, C<email>, and C<can_login> items. The groups returned are filtered
based on your permission to bless each group.

=back

=item B<Errors>

=over

=item 51 (Bad Login Name or Group ID)

You passed an invalid login name in the "names" array or a bad
group ID in the C<group_ids> argument.

=item 304 (Authorization Required)

You are logged in, but you are not authorized to see one of the users you
wanted to get information about by user id.

=item 505 (User Access By Id or User-Matching Denied)

Logged-out users cannot use the "ids" or "match" arguments to this 
function.

=item 804 (Invalid Group Name)

You passed a group name in the C<groups> argument which either does not
exist or you do not belong to it.

=back

=item B<History>

=over

=item Added in Bugzilla B<3.4>.

=item C<group_ids> and C<groups> were added in Bugzilla B<4.0>.

=item C<include_disabled> added in Bugzilla B<4.0>. Default behavior 
for C<match> has changed to only returning enabled accounts.

=item C<groups> Added in Bugzilla B<4.4>.

=item C<saved_searches> Added in Bugzilla B<4.4>.

=item Error 804 has been added in Bugzilla 4.0.9 and 4.2.4. It's now
illegal to pass a group name you don't belong to.

=back

=item REST API call added in Bugzilla B<5.0>.

=back
