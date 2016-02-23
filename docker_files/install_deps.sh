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

$CPANM --installdeps --with-recommends --with-all-features \
       --without-feature oracle --without-feature sqlite --without-feature pg .

# FIXME: These cause error when being installed using cpanfile
$CPANM HTML::Formatter
$CPANM HTML::FormatText::WithLinks

# Building PDF documentation
if [ ! -x "/usr/bin/rst2pdf" ]; then
    pip install rst2pdf
fi

# For testing support
$CPANM JSON::XS
$CPANM Test::WWW::Selenium
$CPANM Pod::Coverage
$CPANM Pod::Checker

# Remove CPAN build files to minimize disk usage
rm -rf ~/.cpanm
