#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use strict;
use warnings;
use 5.10.1;
use lib qw( . lib local/lib/perl5 );

use Scalar::Util qw(weaken);
use Mojo::JSON qw(encode_json);
use Scalar::Util qw(refaddr);
use Test2::V0;

use ok 'Bugzilla::WebService::JSON';

my $json = Bugzilla::WebService::JSON->new;
my $ref = {foo => 1};
is(refaddr $json->decode($json->encode($ref)), refaddr $ref);

my $box = $json->encode($ref);

is($json->decode(q[{"foo":1}]), {foo => 1});
is($json->decode($box),         {foo => 1});

is "$box", $box->label;

$box->encode;

is encode_json([ $box ]), encode_json([ encode_json($box->value) ]);
is "$box", q[{"foo":1}];

done_testing;
