# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.


package Support::Files;

use File::Find;

@additional_files = ();

@files = glob('*');
find(sub { push(@files, $File::Find::name) if $_ =~ /\.pm$/;}, 'Bugzilla');
push(@files, 'extensions/create.pl');

my @extensions = glob('extensions/*');
foreach my $extension (@extensions) {
    # Skip disabled extensions
    next if -e "$extension/disabled";

    find(sub { push(@files, $File::Find::name) if $_ =~ /\.pm$/;}, $extension);
}

sub isTestingFile {
    my ($file) = @_;
    my $exclude;

    if ($file =~ /\.cgi$|\.pl$|\.pm$/) {
        return 1;
    }
    my $additional;
    foreach $additional (@additional_files) {
        if ($file eq $additional) { return 1; }
    }
    return undef;
}

foreach $currentfile (@files) {
    if (isTestingFile($currentfile)) {
        push(@testitems,$currentfile);
    }
    push(@module_files, $currentfile) if $currentfile =~ /\.pm$/;
}


1;
