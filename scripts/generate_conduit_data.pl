#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use strict;
use warnings;
use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Bug;
use Bugzilla::Config qw(:admin);
use Bugzilla::Constants;
use Bugzilla::User;
use Bugzilla::User::APIKey;

BEGIN {
    Bugzilla->extensions;
}

my $dbh = Bugzilla->dbh;

# set Bugzilla usage mode to USAGE_MODE_CMDLINE
Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $admin_email = shift || 'admin@mozilla.bugs';
Bugzilla->set_user( Bugzilla::User->check( { name => $admin_email } ) );

##########################################################################
# Create Conduit Test Users
##########################################################################

my $conduit_login    = $ENV{CONDUIT_USER_LOGIN}    || 'conduit@mozilla.bugs';
my $conduit_password = $ENV{CONDUIT_USER_PASSWORD} || 'password123456789!';
my $conduit_api_key  = $ENV{CONDUIT_USER_API_KEY}  || '';

print "creating conduit developer user account...\n";
if ( !Bugzilla::User->new( { name => $conduit_login } ) ) {
    my $new_user = Bugzilla::User->create(
        {
            login_name    => $conduit_login,
            realname      => 'Conduit Developer',
            cryptpassword => $conduit_password
        },
    );

    if ($conduit_api_key) {
        Bugzilla::User::APIKey->create_special(
            {
                user_id     => $new_user->id,
                description => 'API key for Conduit Developer',
                api_key     => $conduit_api_key
            }
        );
    }
}

my $conduit_reviewer_login    = $ENV{CONDUIT_REVIEWER_USER_LOGIN}    || 'conduit-reviewer@mozilla.bugs';
my $conduit_reviewer_password = $ENV{CONDUIT_REVIEWER_USER_PASSWORD} || 'password123456789!';
my $conduit_reviewer_api_key  = $ENV{CONDUIT_REVIEWER_USER_API_KEY}  || '';

print "creating conduit reviewer user account...\n";
if ( !Bugzilla::User->new( { name => $conduit_reviewer_login } ) ) {
    my $new_user = Bugzilla::User->create(
        {
            login_name    => $conduit_reviewer_login,
            realname      => 'Conduit Reviewer',
            cryptpassword => $conduit_reviewer_password
        },
    );

    if ($conduit_reviewer_api_key) {
        Bugzilla::User::APIKey->create_special(
            {
                user_id     => $new_user->id,
                description => 'API key for Conduit Reviewer',
                api_key     => $conduit_reviewer_api_key
            }
        );
    }
}

##########################################################################
# Create Phabricator Automation Bot
##########################################################################

my $phab_login    = $ENV{PHABRICATOR_BOT_LOGIN}    || 'phab-bot@bmo.tld';
my $phab_password = $ENV{PHABRICATOR_BOT_PASSWORD} || 'password123456789!';
my $phab_api_key  = $ENV{PHABRICATOR_BOT_API_KEY}  || '';

print "creating phabricator automation account...\n";
if ( !Bugzilla::User->new( { name => $phab_login } ) ) {
    my $new_user = Bugzilla::User->create(
        {
            login_name    => $phab_login,
            realname      => 'Phabricator Automation',
            cryptpassword => $phab_password
        },
    );

    if ($phab_api_key) {
        Bugzilla::User::APIKey->create_special(
            {
                user_id     => $new_user->id,
                description => 'API key for Phabricator Automation',
                api_key     => $phab_api_key
            }
        );
    }
}
##########################################################################
# Add Users to Groups
##########################################################################
my @users_groups = (
    { user => 'conduit@mozilla.bugs', group => 'editbugs' },
    { user => 'conduit@mozilla.bugs', group => 'core-security' },
    { user => 'conduit-reviewer@mozilla.bugs', group => 'editbugs' },
    { user => 'phab-bot@bmo.tld',     group => 'editbugs' },
    { user => 'phab-bot@bmo.tld',     group => 'core-security' },
);
print "adding users to groups...\n";
foreach my $user_group (@users_groups) {
    my $group = Bugzilla::Group->new( { name => $user_group->{group} } );
    my $user = Bugzilla::User->new( { name => $user_group->{user} } );
    my $sth_add_mapping = $dbh->prepare(
        'INSERT INTO user_group_map (user_id, group_id, isbless, grant_type)'
        . ' VALUES (?, ?, ?, ?)'
    );

    # Don't crash if the entry already exists.
    my $ok = eval {
        $sth_add_mapping->execute( $user->id, $group->id, 0, GRANT_DIRECT );
        1;
    };
    warn $@ unless $ok;
}

##########################################################################
# Create Conduit Test Bug
##########################################################################
print "creating conduit test bug...\n";
Bugzilla->set_user( Bugzilla::User->check( { name => 'conduit@mozilla.bugs' } ) );
Bugzilla::Bug->create(
    {
        product      => 'Firefox',
        component    => 'General',
        priority     => '--',
        bug_status   => 'NEW',
        version      => 'unspecified',
        comment      => '-- Comment Created By Conduit User --',
        rep_platform => 'Unspecified',
        short_desc   => 'Conduit Test Bug',
        op_sys       => 'Unspecified',
        bug_severity => 'normal',
        version      => 'unspecified',
    }
);

set_params(
    password_check_on_login => 0,
    phabricator_base_uri    => 'http://phabricator.test/',
    phabricator_enabled     => 1,
);
set_push_connector_options();

print "installation and configuration complete!\n";

sub set_push_connector_options {
    print "setting push connector options...\n";
    my ($phab_is_configured) = $dbh->selectrow_array(q{SELECT COUNT(*) FROM push_options WHERE connector = 'Phabricator'});
    unless ($phab_is_configured) {
        $dbh->do(q{INSERT INTO push_options (connector, option_name, option_value) VALUES ('global','enabled','Enabled')});
        $dbh->do(
            q{INSERT INTO push_options (connector, option_name, option_value) VALUES ('Phabricator','enabled','Enabled')});
        $dbh->do(
            q{INSERT INTO push_options (connector, option_name, option_value) VALUES ('Phabricator','phabricator_url','http://phabricator.test')}
        );
    }
}

sub set_params {
    my (%set_params) = @_;
    print "setting custom parameters...\n";
    if ($ENV{PHABRICATOR_API_KEY}) {
        $set_params{phabricator_api_key} = $ENV{PHABRICATOR_API_KEY};
    }

    if ($ENV{PHABRICATOR_APP_ID} && $ENV{PHABRICATOR_AUTH_CALLBACK_URL}) {
        $set_params{phabricator_app_id}            = $ENV{PHABRICATOR_APP_ID};
        $set_params{phabricator_auth_callback_url} = $ENV{PHABRICATOR_AUTH_CALLBACK_URL};
    }

    my $params_modified;
    foreach my $param ( keys %set_params ) {
        my $value = $set_params{$param};
        next if !$value || Bugzilla->params->{$param} eq $value;
        SetParam( $param, $value );
        $params_modified = 1;
    }

    write_params() if $params_modified;
}

