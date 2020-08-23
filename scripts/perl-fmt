#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

use File::Basename qw(dirname);
use Cwd qw(realpath);
use File::Spec::Functions qw(catfile catdir);
use Env qw(@PATH @PERL5LIB);

my $bugzilla_dir = realpath(catdir( dirname(__FILE__), '..' ));
unshift @PERL5LIB, catdir($bugzilla_dir, 'local', 'lib', 'perl5');
unshift @PATH, catdir($bugzilla_dir, 'local', 'bin');

my $profile = catfile($bugzilla_dir, ".perltidyrc" );
warn "formatting @ARGV\n";
exec( perltidy => "--profile=$profile", '-nst', '-b', '-bext=/', '-conv', @ARGV );
