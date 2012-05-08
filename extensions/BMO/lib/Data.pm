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
# The Original Code is the BMO Bugzilla Extension.
#
# The Initial Developer of the Original Code is the Mozilla Foundation.
# Portions created by the Initial Developer are Copyright (C) 2010 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Gervase Markham <gerv@gerv.net>
#   Reed Loden <reed@reedloden.com>

package Bugzilla::Extension::BMO::Data;
use strict;

use base qw(Exporter);
use Tie::IxHash;

our @EXPORT_OK = qw($cf_visible_in_products
                    $cf_flags $cf_project_flags
                    $cf_disabled_flags
                    %group_to_cc_map
                    $blocking_trusted_setters
                    $blocking_trusted_requesters
                    $status_trusted_wanters
                    $status_trusted_setters
                    $other_setters
                    %always_fileable_group
                    %product_sec_groups);

# Which custom fields are visible in which products and components.
#
# By default, custom fields are visible in all products. However, if the name
# of the field matches any of these regexps, it is only visible if the 
# product (and component if necessary) is a member of the attached hash. []
# for component means "all".
#
# IxHash keeps them in insertion order, and so we get regexp priorities right.
our $cf_visible_in_products;
tie(%$cf_visible_in_products, "Tie::IxHash", 
    qw/^cf_blocking_kilimanjaro/ => {
        "Core"             => [],
        "Fennec"           => [],
        "Fennec Native"    => [],
        "Firefox"          => [],
        "mozilla.org"      => [],
        "Mozilla Services" => [],
        "NSPR"             => [],
        "NSS"              => [],
        "Testing"          => [],
        "Thunderbird"      => [],
        "Toolkit"          => [],
        "Tracking"         => [],
        "Web Apps"         => [],
    }, 
    qr/^cf_blocking_fennec/ => {
        "addons.mozilla.org"    => [],
        "AUS"                   => [],
        "Core"                  => [],
        "Fennec"                => [],
        "Fennec Native"         => [],
        "Marketing"             => ["General"],
        "mozilla.org"           => ["Release Engineering"],
        "Mozilla Localizations" => [],
        "Mozilla Services"      => [],
        "NSPR"                  => [],
        "support.mozilla.com"   => [],
        "Toolkit"               => [],
        "Tech Evangelism"       => [],
        "Testing"               => ["General"],
    },
    qr/^cf_tracking_thunderbird|cf_blocking_thunderbird|cf_status_thunderbird/ => {
        "support.mozillamessaging.com"  => [],
        "Thunderbird"                   => [],
        "MailNews Core"                 => [],
        "Mozilla Messaging"             => [],
        "Websites"                      => ["www.mozillamessaging.com"],
    },
    qr/^(cf_(blocking|tracking)_seamonkey|cf_status_seamonkey)/ => {
        "Composer"              => [],
        "MailNews Core"         => [],
        "Mozilla Localizations" => [],
        "Other Applications"    => [],
        "SeaMonkey"             => [],
    },
    qr/^cf_blocking_|cf_tracking_|cf_status/ => {
        "Add-on SDK"            => [],
        "addons.mozilla.org"    => [],
        "AUS"                   => [],
        "Core Graveyard"        => [],
        "Core"                  => [],
        "Directory"             => [],
        "Fennec"                => [],
        "Fennec Native"         => [], 
        "Firefox"               => [],
        "MailNews Core"         => [],
        "mozilla.org"           => ["Release Engineering"],
        "Mozilla QA"            => ["Mozmill Tests"],
        "Mozilla Localizations" => [],
        "Mozilla Services"      => [],
        "NSPR"                  => [],
        "NSS"                   => [],
        "Other Applications"    => [],
        "SeaMonkey"             => [],
        "Socorro"               => [], 
        "support.mozilla.com"   => [],
        "Tech Evangelism"       => [],
        "Testing"               => [],
        "Toolkit"               => [],
        "Websites"              => ["getpersonas.com"],
        "Webtools"              => [],
        "Plugins"               => [],
    },
    qr/^cf_colo_site$/ => {
        "mozilla.org"           => [
            "Server Operations",
            "Server Operations: Projects",
            "Server Operations: RelEng",
            "Server Operations: Security",
        ],
    },
    qw/^cf_office$/ => {
        "mozilla.org"           => ["Server Operations: Desktop Issues"],
    },
    qr/^cf_crash_signature$/ => {
        "addons.mozilla.org"    => [], 
        "Add-on SDK"            => [], 
        "Calendar"              => [], 
        "Camino"                => [], 
        "Composer"              => [], 
        "Fennec"                => [], 
        "Fennec Native"         => [], 
        "Firefox"               => [], 
        "Mozilla Localizations" => [], 
        "Mozilla Services"      => [], 
        "Other Applications"    => [], 
        "Penelope"              => [], 
        "SeaMonkey"             => [], 
        "Thunderbird"           => [],
        "Core"                  => [], 
        "Directory"             => [], 
        "JSS"                   => [], 
        "MailNews Core"         => [], 
        "NSPR"                  => [], 
        "NSS"                   => [], 
        "Plugins"               => [], 
        "Rhino"                 => [], 
        "Tamarin"               => [], 
        "Testing"               => [], 
        "Toolkit"               => [], 
        "Mozilla Labs"          => [],
        "mozilla.org"           => [], 
        "Tech Evangelism"       => [],  
    },
    qw/^cf_due_date$/ => {
        "Mozilla Reps" => [],
        "mozilla.org"  => ["Security Assurance: Review Request"], 
    }, 
);

# Which custom fields are acting as flags (ie. custom flags)
our $cf_flags = [
    qr/^cf_(?:blocking|tracking|status)_/,
];

our $cf_project_flags = [
    qr/^cf_blocking_kilimanjaro/,
];

# List of disabled fields.
# Temp kludge until custom fields can be disabled correctly upstream.
# Disabled fields are hidden unless they have a value set
our $cf_disabled_flags = [
    'cf_blocking_20',
    'cf_status_20',
    'cf_tracking_firefox5',
    'cf_status_firefox5',
    'cf_blocking_thunderbird32',
    'cf_status_thunderbird32',
    'cf_blocking_thunderbird30',
    'cf_status_thunderbird30',
    'cf_blocking_seamonkey21',
    'cf_status_seamonkey21',
    'cf_tracking_seamonkey22',
    'cf_status_seamonkey22',
    'cf_tracking_firefox6',
    'cf_status_firefox6',
    'cf_tracking_thunderbird6',
    'cf_status_thunderbird6',
    'cf_tracking_seamonkey23',
    'cf_status_seamonkey23',
    'cf_tracking_firefox7',
    'cf_status_firefox7',
    'cf_tracking_thunderbird7',
    'cf_status_thunderbird7',
    'cf_tracking_seamonkey24',
    'cf_status_seamonkey24',
    'cf_tracking_firefox8',
    'cf_status_firefox8',
    'cf_tracking_thunderbird8',
    'cf_status_thunderbird8',
    'cf_tracking_seamonkey25',
    'cf_status_seamonkey25',
    'cf_blocking_191',
    'cf_status_191',
    'cf_blocking_thunderbird33',
    'cf_status_thunderbird33',
    'cf_tracking_firefox9',
    'cf_status_firefox9',
    'cf_tracking_thunderbird9',
    'cf_status_thunderbird9',
    'cf_tracking_seamonkey26',
    'cf_status_seamonkey26',
    'cf_tracking_firefox10',
    'cf_status_firefox10',
    'cf_tracking_thunderbird10',
    'cf_status_thunderbird10',
    'cf_tracking_seamonkey27',
    'cf_status_seamonkey27',
    'cf_tracking_firefox11',
    'cf_status_firefox11',
    'cf_tracking_thunderbird11',
    'cf_status_thunderbird11',
    'cf_tracking_seamonkey28',
    'cf_status_seamonkey28',
];

# Who to CC on particular bugmails when certain groups are added or removed.
our %group_to_cc_map = (
  'addons-security'          => 'amo-editors@mozilla.org', 
  'bugzilla-security'        => 'security@bugzilla.org',
  'client-services-security' => 'amo-admins@mozilla.org',
  'core-security'            => 'security@mozilla.org',
  'tamarin-security'         => 'tamarinsecurity@adobe.com',
  'websites-security'        => 'website-drivers@mozilla.org',
  'webtools-security'        => 'webtools-security@mozilla.org',
);

# Only users in certain groups can change certain custom fields in 
# certain ways. 
#
# Who can set cf_blocking_* or cf_tracking_* to +/-
our $blocking_trusted_setters = {
    'cf_blocking_fennec'          => 'fennec-drivers',
    'cf_blocking_20'              => 'mozilla-next-drivers',
    qr/^cf_tracking_firefox/      => 'mozilla-next-drivers',
    qr/^cf_blocking_thunderbird/  => 'thunderbird-drivers',
    qr/^cf_tracking_thunderbird/  => 'thunderbird-drivers',
    qr/^cf_tracking_seamonkey/    => 'seamonkey-council',
    qr/^cf_blocking_seamonkey/    => 'seamonkey-council',
    qr/^cf_blocking_kilimanjaro/  => 'kilimanjaro-drivers', 
    '_default'                    => 'mozilla-stable-branch-drivers',
};

# Who can request cf_blocking_* or cf_tracking_*
our $blocking_trusted_requesters = {
    qr/^cf_blocking_thunderbird/  => 'thunderbird-trusted-requesters',
    '_default'                    => 'everyone',
};

# Who can set cf_status_* to "wanted"?
our $status_trusted_wanters = {
    'cf_status_20'                => 'mozilla-next-drivers',
    qr/^cf_status_thunderbird/    => 'thunderbird-drivers',
    qr/^cf_status_seamonkey/      => 'seamonkey-council',
    '_default'                    => 'mozilla-stable-branch-drivers',
};

# Who can set cf_status_* to values other than "wanted"?
our $status_trusted_setters = {
    qr/^cf_status_thunderbird/    => 'editbugs',
    '_default'                    => 'canconfirm',
};

# Who can set other custom flags (use full field names only, not regex's)
our $other_setters = {
    'cf_colo_site'  => ['infra', 'build'],
};

# Groups in which you can always file a bug, whoever you are.
our %always_fileable_group = (
    'addons-security'                   => 1, 
    'bugzilla-security'                 => 1,
    'client-services-security'          => 1,
    'consulting'                        => 1,
    'core-security'                     => 1,
    'infra'                             => 1,
    'infrasec'                          => 1, 
    'marketing-private'                 => 1,
    'mozilla-confidential'              => 1,
    'mozilla-corporation-confidential'  => 1,
    'mozilla-foundation-confidential'   => 1, 
    'mozilla-messaging-confidential'    => 1,
    'partner-confidential'              => 1,
    'payments-confidential'             => 1,  
    'tamarin-security'                  => 1,
    'websites-security'                 => 1,
    'webtools-security'                 => 1,
);

# Mapping of products to their security bits
our %product_sec_groups = (
    "addons.mozilla.org"           => 'client-services-security',
    "AUS"                          => 'client-services-security',
    "Bugzilla"                     => 'bugzilla-security',
    "bugzilla.mozilla.org"         => 'bugzilla-security',
    "Community Tools"              => 'websites-security',
    "Legal"                        => 'legal',
    "Marketing"                    => 'marketing-private',
    "Mozilla Corporation"          => 'mozilla-corporation-confidential',
    "Mozilla Developer Network"    => 'websites-security',
    "Mozilla Grants"               => 'grants',
    "Mozilla Messaging"            => 'mozilla-messaging-confidential',
    "Mozilla Metrics"              => 'metrics-private',
    "mozilla.org"                  => 'mozilla-confidential',
    "Mozilla PR"                   => 'pr-private',
    "Mozilla Reps"                 => 'mozilla-reps',
    "Mozilla Services"             => 'mozilla-services-security',
    "quality.mozilla.org"          => 'websites-security',
    "Skywriter"                    => 'websites-security',
    "Socorro"                      => 'client-services-security',
    "support.mozilla.com"          => 'websites-security',
    "support.mozillamessaging.com" => 'websites-security',
    "Talkback"                     => 'talkback-private',
    "Tamarin"                      => 'tamarin-security',
    "Testopia"                     => 'bugzilla-security',
    "Web Apps"                     => 'webtools-security',
    "Webpagemaker"                 => 'websites-security',
    "Websites"                     => 'websites-security',
    "Websites Graveyard"           => 'websites-security',
    "Webtools"                     => 'webtools-security',
    "_default"                     => 'core-security'
);

# Default security groups for products should always been fileable
map { $always_fileable_group{$_} = 1 } values %product_sec_groups;

1;
