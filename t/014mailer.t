# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

##################
#Bugzilla Test 14#
####Mailer.pm#####

use 5.14.0;
use strict;
use warnings;

use lib qw(. lib t);
use Support::Files;
use Test::More tests => 18;

BEGIN {
  use_ok('Bugzilla');
  use_ok('Bugzilla::Mailer', 'build_thread_marker');
}

# Inject urlbase into the params cache without needing a real installation.
my $params = Bugzilla->params;

# ---- build_message_id: sitespec transformation ----
#
# The central invariant: whatever urlbase looks like, the resulting
# Message-ID must be a valid <local-part@domain> with no '/' characters
# after the '@'.

my $mid;

# Plain http, trailing slash only — baseline case.
$params->{urlbase} = 'http://bugs.example.org/';
$mid = Bugzilla::Mailer::build_message_id();
like($mid, qr/^<bugzilla-[A-Za-z0-9]+\@http\.bugs\.example\.org>$/,
  'simple http urlbase: correct format and sitespec');
unlike($mid, qr/\@[^>]*\//, 'simple http urlbase: no slash after @');

# Path component after the hostname — the key regression this patch fixes.
$params->{urlbase} = 'https://bugs.example.org/bugzilla/';
$mid = Bugzilla::Mailer::build_message_id();
like($mid, qr/^<bugzilla-[A-Za-z0-9]+\@https\.bugs\.example\.org>$/,
  'https with path: path component stripped from sitespec');
unlike($mid, qr/\@[^>]*\//, 'https with path: no slash after @');

# Non-standard port — port must move before the '@'.
$params->{urlbase} = 'https://bugs.example.org:8080/';
$mid = Bugzilla::Mailer::build_message_id();
like($mid, qr/^<bugzilla-[A-Za-z0-9]+-8080\@https\.bugs\.example\.org>$/,
  'https with port: port relocated before @');
unlike($mid, qr/\@[^>]*\//, 'https with port: no slash after @');

# Port and path together.
$params->{urlbase} = 'https://bugs.example.org:8080/bugzilla/';
$mid = Bugzilla::Mailer::build_message_id();
like($mid, qr/^<bugzilla-[A-Za-z0-9]+-8080\@https\.bugs\.example\.org>$/,
  'https with port and path: path stripped, port relocated');
unlike($mid, qr/\@[^>]*\//, 'https with port and path: no slash after @');

# ---- build_message_id: user_id handling ----

$params->{urlbase} = 'https://bugs.example.org/';

my $mid_with_user = Bugzilla::Mailer::build_message_id(42);
like($mid_with_user, qr/^<bugzilla-42-[A-Za-z0-9]+\@/,
  'with user_id: user_id present in local-part');
unlike($mid_with_user, qr/bugzilla--/,
  'with user_id: no double-dash');

my $mid_no_user = Bugzilla::Mailer::build_message_id();
like($mid_no_user, qr/^<bugzilla-[A-Za-z0-9]+\@/,
  'without user_id: clean local-part (no double-dash)');
unlike($mid_no_user, qr/bugzilla--/,
  'without user_id: no double-dash');

# ---- build_thread_marker: same sitespec logic ----

my $marker;

# Path component must be stripped here too.
$params->{urlbase} = 'https://bugs.example.org/bugzilla/';
$marker = build_thread_marker(99, 7, 1);    # new bug
like($marker, qr/Message-ID: <bug-99-7\@https\.bugs\.example\.org>/,
  'new thread with path: path stripped from sitespec');
unlike($marker, qr/\@[^>]*\//, 'new thread with path: no slash after @');

# Port relocation for non-standard port.
$params->{urlbase} = 'https://bugs.example.org:8080/';
$marker = build_thread_marker(99, 7, 1);    # new bug
like($marker, qr/Message-ID: <bug-99-7-8080\@https\.bugs\.example\.org>/,
  'new thread with port: port relocated before @');

# Reply includes In-Reply-To pointing at the root message.
$marker = build_thread_marker(99, 7, 0);    # reply
like($marker, qr/In-Reply-To: <bug-99-7-8080\@https\.bugs\.example\.org>/,
  'reply thread: In-Reply-To uses correct sitespec');
