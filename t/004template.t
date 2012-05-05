# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

#################
#Bugzilla Test 4#
####Templates####

use strict;

use lib 't';

use Support::Templates;

# Bug 137589 - Disable command-line input of CGI.pm when testing
use CGI qw(-no_debug);

use File::Spec;
use Template;
use Test::More tests => ( scalar(@referenced_files) + $num_actual_files );

# Capture the TESTOUT from Test::More or Test::Builder for printing errors.
# This will handle verbosity for us automatically.
my $fh;
{
    local $^W = 0;  # Don't complain about non-existent filehandles
    if (-e \*Test::More::TESTOUT) {
        $fh = \*Test::More::TESTOUT;
    } elsif (-e \*Test::Builder::TESTOUT) {
        $fh = \*Test::Builder::TESTOUT;
    } else {
        $fh = \*STDOUT;
    }
}

# Check to make sure all templates that are referenced in Bugzilla
# exist in the proper place in the English template directory.
# All other languages may or may not include any template as Bugzilla will
# fall back to English if necessary.

foreach my $file (@referenced_files) {
    my $path = File::Spec->catfile($english_default_include_path, $file);
    if (-e $path) {
        ok(1, "$path exists");
    } else {
        ok(0, "$path cannot be located --ERROR");
    }
}

foreach my $include_path (@include_paths) {
    # Processes all the templates to make sure they have good syntax
    my $provider = Template::Provider->new(
    {
        INCLUDE_PATH => $include_path ,
        # Need to define filters used in the codebase, they don't
        # actually have to function in this test, just be defined.
        # See Template.pm for the actual codebase definitions.

        # Initialize templates (f.e. by loading plugins like Hook).
        PRE_PROCESS => "global/variables.none.tmpl",

        FILTERS =>
        {
            html_linebreak => sub { return $_; },
            no_break => sub { return $_; } ,
            js        => sub { return $_ } ,
            base64   => sub { return $_ } ,
            inactive => [ sub { return sub { return $_; } }, 1] ,
            closed => [ sub { return sub { return $_; } }, 1] ,
            obsolete => [ sub { return sub { return $_; } }, 1] ,
            url_quote => sub { return $_ } ,
            css_class_quote => sub { return $_ } ,
            xml       => sub { return $_ } ,
            quoteUrls => sub { return $_ } ,
            bug_link => [ sub { return sub { return $_; } }, 1] ,
            csv       => sub { return $_ } ,
            unitconvert => sub { return $_ },
            time      => sub { return $_ } ,
            wrap_comment => sub { return $_ },
            none      => sub { return $_ } ,
            ics       => [ sub { return sub { return $_; } }, 1] ,
        },
    }
    );

    foreach my $file (@{$actual_files{$include_path}}) {
        my $path = File::Spec->catfile($include_path, $file);

        # These are actual files, so there's no need to check for existence.

        my ($data, $err) = $provider->fetch($file);

        if (!$err) {
            ok(1, "$path syntax ok");
        }
        else {
            ok(0, "$path has bad syntax --ERROR");
            print $fh $data . "\n";
        }
    }
}

exit 0;
