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
use lib qw(. lib local/lib/perl5);




use Bugzilla::Constants;
use Bugzilla::Install::Requirements;
use Bugzilla::Install::Util;

sub _check_vers {
    my ($params) = @_;
    my $module  = $params->{module};
    my $package = $params->{package};
    if (!$package) {
        $package = $module;
        $package =~ s/::/-/g;
    }

    my $wanted = $params->{version};

    eval "require $module;";
    # Don't let loading a module change the output-encoding of STDOUT
    # or STDERR. (CGI.pm tries to set "binmode" on these file handles when
    # it's loaded, and other modules may do the same in the future.)
    Bugzilla::Install::Util::set_output_encoding();

    # VERSION is provided by UNIVERSAL::, and can be called even if
    # the module isn't loaded. We eval'uate ->VERSION because it can die
    # when the version is not valid (yes, this happens from time to time).
    # In that case, we use an uglier method to get the version.
    my $vnum = eval { $module->VERSION };
    if ($@) {
        no strict 'refs';
        $vnum = ${"${module}::VERSION"};

        # If we come here, then the version is not a valid one.
        # We try to sanitize it.
        if ($vnum =~ /^((\d+)(\.\d+)*)/) {
            $vnum = $1;
        }
    }
    $vnum ||= -1;

    # Must do a string comparison as $vnum may be of the form 5.10.1.
    my $vok = ($vnum ne '-1' && version->new($vnum) >= version->new($wanted)) ? 1 : 0;
    if ($vok && $params->{blacklist}) {
        $vok = 0 if grep($vnum =~ /$_/, @{$params->{blacklist}});
    }

    return {
        module => $module,
        ok     => $vok,
        wanted => $wanted,
        found  => $vnum,
    };
}

my $cpanfile;
# Required modules
foreach my $module (@{ REQUIRED_MODULES() }) {
    my $current = _check_vers($module);
    my $requires = "requires '" . $current->{module} . "'";
    $requires .= ", '" . ($current->{ok} ? $current->{found} : $current->{wanted}) . "'";
    $requires .= ";\n";
    $cpanfile .= $requires;
}

# Recommended modules
$cpanfile .= "\n# Optional\n";
my %features;
foreach my $module (@{ OPTIONAL_MODULES() }) {
    next if $module->{package} eq 'mod_perl'; # Skip mod_perl since this would be installed by distro
    my $current = _check_vers($module);
    if (exists $module->{feature}) {
        foreach my $feature (@{ $module->{feature} }) {
            # cpanm requires that each feature only be defined in the cpanfile
            # once, so we use an intermediate hash to consolidate/de-dupe the
            # modules associated with each feature.
            $features{$feature}{$module->{module}}
              = ($current->{ok} ? $current->{found} : $current->{wanted});
        }
    }
    else {
        my $recommends = "";
        $recommends .= "recommends '" . $module->{module} . "'";
        $recommends .= ", '" . ($current->{ok} ? $current->{found} : $current->{wanted}) . "'";
        $recommends .= ";\n";
        $cpanfile .= $recommends;
    }
}

foreach my $feature (sort keys %features) {
    my $recommends = "";
    $recommends .= "feature '" . $feature . "' => sub {\n";
    foreach my $module (sort keys %{ $features{$feature} }) {
        my $version = $features{$feature}{$module};
        $recommends .= "  recommends '" . $module . "'";
        $recommends .= ", '$version'" if $version;
        $recommends .= ";\n";
    }
    $recommends .= "};\n";
    $cpanfile .= $recommends;
}

# Database modules
$cpanfile .= "\n# Database support\n";
foreach my $db (keys %{ DB_MODULE() }) {
    next if !exists DB_MODULE->{$db}->{dbd};
    my $dbd = DB_MODULE->{$db}->{dbd};
    my $current = _check_vers($dbd);
    my $recommends .= "feature '$db' => sub {\n";
    $recommends .= "  recommends '" . $dbd->{module} . "'";
    $recommends .= ", '" . ($current->{ok} ? $current->{found} : $current->{wanted}) . "'";
    $recommends .= ";\n};\n";
    $cpanfile .= $recommends;
}

# Write out the cpanfile to STDOUT
print $cpanfile . "\n";
