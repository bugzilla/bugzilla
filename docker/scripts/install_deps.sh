#!/bin/bash

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
