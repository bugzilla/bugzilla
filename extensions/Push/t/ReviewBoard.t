#!/usr/bin/perl -T
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use strict;
use warnings;
use lib qw( . lib );

use Test::More;
use Bugzilla;
use Bugzilla::Extension;
use Bugzilla::Attachment;
use Scalar::Util 'blessed';
use YAML;

BEGIN {
    eval {
        require Test::LWP::UserAgent;
        require Test::MockObject;
    };
    if ($@) {
        plan skip_all =>
          'Tests require Test::LWP::UserAgent and Test::MockObject';
        exit;
    }
}

BEGIN {
    Bugzilla->extensions; # load all of them
    use_ok 'Bugzilla::Extension::Push::Connector::ReviewBoard::Client';
    use_ok 'Bugzilla::Extension::Push::Constants';
}

my ($push) = grep { blessed($_) eq 'Bugzilla::Extension::Push' } @{Bugzilla->extensions };
my $connectors = $push->_get_instance->connectors;
my $con = $connectors->by_name('ReviewBoard');

my $ua_204 = Test::LWP::UserAgent->new;
$ua_204->map_response(
                  qr{https://reviewboard-dev\.allizom\.org/api/review-requests/\d+},
                  HTTP::Response->new('204'));

my $ua_404 = Test::LWP::UserAgent->new;
$ua_404->map_response(
    qr{https://reviewboard-dev\.allizom\.org/api/review-requests/\d+},
    HTTP::Response->new('404', undef, undef, q[{ "err": { "code": 100, "msg": "Object does not exist" }, "stat": "fail" }]));

# forbidden
my $ua_403 = Test::LWP::UserAgent->new;
$ua_403->map_response(
    qr{https://reviewboard-dev\.allizom\.org/api/review-requests/\d+},
    HTTP::Response->new('403', undef, undef, q[ {"err":{"code":101,"msg":"You don't have permission for this"},"stat":"fail"}]));

# not logged in
my $ua_401 = Test::LWP::UserAgent->new;
$ua_401->map_response(
    qr{https://reviewboard-dev\.allizom\.org/api/review-requests/\d+},
    HTTP::Response->new('401', undef, undef, q[ { "err": { "code": 103, "msg": "You are not logged in" }, "stat": "fail" } ]));

# not logged in
my $ua_500 = Test::LWP::UserAgent->new;
$ua_500->map_response(
    qr{https://reviewboard-dev\.allizom\.org/api/review-requests/\d+},
    HTTP::Response->new('500'));

$con->client->{useragent} = $ua_204;
$con->config->{base_uri} = 'https://reviewboard-dev.allizom.org';
$con->client->{base_uri} = 'https://reviewboard-dev.allizom.org';

{
    my $msg = message(
        event => {
            routing_key => 'attachment.modify:is_private',
            target => 'attachment',
        },
        attachment => {
            is_private => 1,
            content_type => 'text/plain',
            bug => { id => 1, is_private => 0 },
        },
    );

    ok(not($con->should_send($msg)), "text/plain message should not be sent");
}

my $data = slurp("extensions/Push/t/rblink.txt");
Bugzilla::User::DEFAULT_USER->{userid} = 42;
Bugzilla->set_user(Bugzilla::User->super_user);
diag " " . Bugzilla::User->super_user->id;

my $dbh = Bugzilla->dbh;
$dbh->bz_start_transaction;
my $timestamp = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
my $bug = Bugzilla::Bug->new({id => 9000});
my $attachment = Bugzilla::Attachment->create(
                                { bug         => $bug,
                                    creation_ts => $timestamp,
                                    data        => $data,
                                    filesize    => length $data,
                                    description => "rblink.txt",
                                    filename => "rblink.txt",
                                    isprivate => 1, ispatch => 0,
                                    mimetype    => 'text/x-review-board-request'});
diag "".$attachment->id;
$dbh->bz_commit_transaction;

{
    my $msg = message(
        event => {
            routing_key => 'attachment.modify:cc,is_private',
            target => 'attachment',
        },
        attachment => {
            id => $attachment->id,
            is_private => 1,
            content_type => 'text/x-review-board-request',
            bug => { id => $bug->id, is_private => 0 },
        },
    );
    ok($con->should_send($msg), "rb attachment should be sent");

    {
        my ($rv, $err) = $con->send($msg);
        is($rv, PUSH_RESULT_OK, "good push result");
        diag $err if $err;
    }

    {
        local $con->client->{useragent} = $ua_404;
        my ($rv, $err) = $con->send($msg);
        is($rv, PUSH_RESULT_OK, "good push result for 404");
        diag $err if $err;
    }


    {
        local $con->client->{useragent} = $ua_403;
        my ($rv, $err) = $con->send($msg);
        is($rv, PUSH_RESULT_TRANSIENT, "transient error on 403");
        diag $err if $err;
    }


    {
        local $con->client->{useragent} = $ua_401;
        my ($rv, $err) = $con->send($msg);
        is($rv, PUSH_RESULT_TRANSIENT, "transient error on 401");
        diag $err if $err;
    }

    {
        local $con->client->{useragent} = $ua_500;
        my ($rv, $err) = $con->send($msg);
        is($rv, PUSH_RESULT_TRANSIENT, "transient error on 500");
        diag $err if $err;
    }
}

{
    my $msg = message(
        event => {
            routing_key => 'bug.modify:is_private',
            target => 'bug',
        },
        bug => {
            is_private => 1,
            id => $bug->id,
        },
    );

    ok($con->should_send($msg), "rb attachment should be sent");
    my ($rv, $err) = $con->send($msg);
    is($rv, PUSH_RESULT_OK, "good push result");

    {
        local $con->client->{useragent} = $ua_404;
        my ($rv, $err) = $con->send($msg);
        is($rv, PUSH_RESULT_OK, "good push result for 404");
    }

    {
        local $con->client->{useragent} = $ua_403;
        my ($rv, $err) = $con->send($msg);
        is($rv, PUSH_RESULT_TRANSIENT, "transient error on 404");
        diag $err if $err;
    }


    {
        local $con->client->{useragent} = $ua_401;
        my ($rv, $err) = $con->send($msg);
        is($rv, PUSH_RESULT_TRANSIENT, "transient error on 401");
        diag $err if $err;
    }

    {
        local $con->client->{useragent} = $ua_401;
        my ($rv, $err) = $con->send($msg);
        is($rv, PUSH_RESULT_TRANSIENT, "transient error on 401");
        diag $err if $err;
    }
}

sub message {
    my $msg_data = { @_ };

    return Test::MockObject->new
        ->set_always( routing_key => $msg_data->{event}{routing_key} )
        ->set_always( payload_decoded => $msg_data );
}

sub slurp {
    my $file = shift;
    local $/ = undef;
    open my $fh, '<', $file or die "unable to open $file";
    my $s = readline $fh;
    close $fh;
    return $s;
}

done_testing;
