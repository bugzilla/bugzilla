#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

cd $BUGZILLA_ROOT

# Install Perl dependencies
CPANM="cpanm -l local --quiet --skip-satisfied"

$CPANM --installdeps --with-all-features \
       --without-feature oracle --without-feature sqlite --without-feature pg .

# Building PDF documentation
if [ ! -x "/usr/bin/rst2pdf" ]; then
    pip install rst2pdf
fi

# For UI testing support (--notest because it tries to connect to a running server)
$CPANM --notest Test::WWW::Selenium

# Remove CPAN build files to minimize disk usage
rm -rf ~/.cpanm
