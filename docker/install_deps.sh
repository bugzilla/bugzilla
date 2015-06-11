#!/bin/bash

cd $BUGZILLA_ROOT

# Install Perl dependencies
CPANM="cpanm --quiet --notest --skip-satisfied"

# Force version due to problem with CentOS ImageMagick-devel
$CPANM Image::Magick@6.77

perl checksetup.pl --cpanfile
$CPANM --installdeps --with-recommends --with-all-features \
    --without-feature oracle --without-feature sqlite --without-feature pg .

# These are not picked up by cpanm --with-all-features for some reason
$CPANM Template::Plugin::GD::Image
$CPANM MIME::Parser
$CPANM SOAP::Lite
$CPANM JSON::RPC
$CPANM Email::MIME::Attachment::Stripper
$CPANM TheSchwartz
$CPANM XMLRPC::Lite

# For testing support
$CPANM Test::WWW::Selenium
$CPANM Pod::Coverage
$CPANM Pod::Checker

# Remove CPAN build files to minimize disk usage
rm -rf /root/.cpanm
