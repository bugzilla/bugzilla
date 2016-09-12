# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Sitemap Bugzilla Extension.
#
# The Initial Developer of the Original Code is Everything Solved, Inc.
# Portions created by the Initial Developer are Copyright (C) 2010 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Max Kanat-Alexander <mkanat@bugzilla.org>

package Bugzilla::Extension::SiteMapIndex::Constants;
use strict;
use base qw(Exporter);
our @EXPORT = qw(
    SITEMAP_AGE
    SITEMAP_MAX
    SITEMAP_DELAY
    SITEMAP_URL
);

# This is the amount of hours a sitemap index and it's files are considered
# valid before needing to be regenerated.
use constant SITEMAP_AGE => 12;

# This is the largest number of entries that can be in a single sitemap file,
# per the sitemaps.org standard. 
use constant SITEMAP_MAX => 50_000;

# We only show bugs that are at least 12 hours old, because if somebody
# files a bug that's a security bug but doesn't protect it, we want to give 
# them time to fix that.
use constant SITEMAP_DELAY => 12;

use constant SITEMAP_URL => 'page.cgi?id=sitemap/sitemap.xml';

1;
