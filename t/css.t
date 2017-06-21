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
use File::Spec;
use File::Slurp qw(read_file);
use File::Find qw(find);
use Cwd qw(realpath cwd);
use Test::More;

my $root = cwd();

find(
    {
        wanted => sub {
            if (/\.css$/) {
                my $css_file = $File::Find::name;
                my $content = read_file($_);
                while ($content =~ m{url\(["']?([^\)"']+)['"]?\)}g) {
                    my $file = $1;
                    my $file_rel_root = File::Spec->abs2rel(realpath(File::Spec->rel2abs($file)), $root);

                    ok(-f $file, "$css_file references $file ($file_rel_root)");
                }
            }
        },
    },
    'skins'
);

done_testing;
