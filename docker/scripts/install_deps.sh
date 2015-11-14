#!/bin/bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

cd $BUGZILLA_ROOT

# Install Perl dependencies
CPANM="cpanm --quiet --notest --skip-satisfied"

perl checksetup.pl --cpanfile
$CPANM --installdeps --with-recommends --with-all-features \
    --without-feature oracle --without-feature sqlite --without-feature pg .

# These are not picked up by cpanm --with-all-features for some reason
$CPANM XMLRPC::Lite

# For testing support
$CPANM File::Copy::Recursive
$CPANM Test::WWW::Selenium
$CPANM Pod::Coverage
$CPANM Pod::Checker
$CPANM Test::LWP::UserAgent
$CPANM Test::MockObject

# Remove CPAN build files to minimize disk usage
rm -rf ~/.cpanm
