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

our @EXPORT = qw( $cf_visible_in_products
                  $cf_flags $cf_project_flags
                  $cf_disabled_flags
                  %group_change_notification
                  $blocking_trusted_setters
                  $blocking_trusted_requesters
                  $status_trusted_wanters
                  $status_trusted_setters
                  $other_setters
                  @always_fileable_groups
                  %group_auto_cc
                  %product_sec_groups
                  %create_bug_formats
                  @default_named_queries );

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
    qw/^cf_blocking_kilimanjaro|cf_blocking_basecamp|cf_blocking_b2g/ => {
        "Boot2Gecko"            => [],
        "Core"                  => [],
        "Fennec"                => [],
        "Firefox"               => [],
        "Firefox for Android"   => [],
        "Firefox for Metro"     => [],
        "Firefox Health Report" => [],
        "Marketplace"           => [],
        "mozilla.org"           => [],
        "Mozilla Services"      => [],
        "NSPR"                  => [],
        "NSS"                   => [],
        "Socorro"               => [],
        "Tech Evangelism"       => [],
        "Testing"               => [],
        "Thunderbird"           => [],
        "Toolkit"               => [],
        "Tracking"              => [],
        "Web Apps"              => [],
    },
    qr/^cf_blocking_fennec/ => {
        "addons.mozilla.org"          => [],
        "Android Background Services" => [],
        "AUS"                         => [],
        "Core"                        => [],
        "Fennec"                      => [],
        "Firefox for Android"         => [],
        "Firefox Health Report"       => [],
        "Marketing"                   => ["General"],
        "Mozilla Localizations"       => [],
        "mozilla.org"                 => ["Release Engineering", qr/^Release Engineering: /],
        "Mozilla Services"            => [],
        "NSPR"                        => [],
        "support.mozilla.org"         => [],
        "Tech Evangelism"             => [],
        "Testing"                     => ["General"],
        "Toolkit"                     => [],
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
        "Boot2Gecko"            => [],
        "Core"                  => [],
        "Core Graveyard"        => [],
        "Directory"             => [],
        "Fennec"                => [],
        "Firefox"               => [],
        "Firefox for Android"   => [],
        "Firefox for Metro"     => [],
        "Firefox Health Report" => [],
        "MailNews Core"         => [],
        "Mozilla Localizations" => [],
        "mozilla.org"           => ["Release Engineering", qr/^Release Engineering: /],
        "Mozilla QA"            => ["Mozmill Tests"],
        "Mozilla Services"      => [],
        "NSPR"                  => [],
        "NSS"                   => [],
        "Other Applications"    => [],
        "Plugins"               => [],
        "SeaMonkey"             => [],
        "Socorro"               => [],
        "support.mozilla.org"   => [],
        "Tech Evangelism"       => [],
        "Testing"               => [],
        "Toolkit"               => [],
        "Websites"              => ["getpersonas.com"],
        "Webtools"              => [],
    },
    qr/^cf_colo_site$/ => {
        "mozilla.org"           => [
            "Server Operations",
            "Server Operations: DCOps",
            "Server Operations: Projects",
            "Server Operations: RelEng",
            "Server Operations: Security",
        ],
    },
    qw/^cf_office$/ => {
        "mozilla.org"           => ["Server Operations: Desktop Issues"],
    },
    qr/^cf_crash_signature$/ => {
        "Add-on SDK"            => [],
        "addons.mozilla.org"    => [],
        "Boot2Gecko"            => [],
        "Calendar"              => [],
        "Camino"                => [],
        "Composer"              => [],
        "Core"                  => [],
        "Directory"             => [],
        "Fennec"                => [],
        "Firefox"               => [],
        "Firefox for Android"   => [],
        "Firefox for Metro"     => [],
        "JSS"                   => [],
        "MailNews Core"         => [],
        "Mozilla Labs"          => [],
        "Mozilla Localizations" => [],
        "mozilla.org"           => [],
        "Mozilla Services"      => [],
        "NSPR"                  => [],
        "NSS"                   => [],
        "Other Applications"    => [],
        "Penelope"              => [],
        "Plugins"               => [],
        "Rhino"                 => [],
        "SeaMonkey"             => [],
        "Tamarin"               => [],
        "Tech Evangelism"       => [],
        "Testing"               => [],
        "Thunderbird"           => [],
        "Toolkit"               => [],
    },
    qw/^cf_due_date$/ => {
        "Marketing"    => [],
        "Mozilla Reps" => [],
        "mozilla.org"  => ["Security Assurance: Review Request"],
    },
    qw/^cf_locale$/ => {
        "www.mozilla.org"       => [],
    },
);

# Which custom fields are acting as flags (ie. custom flags)
our $cf_flags = [
    qr/^cf_(?:blocking|tracking|status)_/,
];

our $cf_project_flags = [
    'cf_blocking_kilimanjaro',
    'cf_blocking_b2g',
    'cf_blocking_basecamp',
];

# List of disabled fields.
# Temp kludge until custom fields can be disabled correctly upstream.
# Disabled fields are hidden unless they have a value set
our $cf_disabled_flags = [
    'cf_blocking_20',
    'cf_status_20',
    'cf_blocking_basecamp',
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
    'cf_tracking_firefox12',
    'cf_status_firefox12',
    'cf_tracking_thunderbird12',
    'cf_status_thunderbird12',
    'cf_tracking_seamonkey29',
    'cf_status_seamonkey29',
    'cf_blocking_192',
    'cf_status_192',
    'cf_blocking_fennec10',
    'cf_tracking_firefox13',
    'cf_status_firefox13',
    'cf_tracking_thunderbird13',
    'cf_status_thunderbird13',
    'cf_tracking_seamonkey210',
    'cf_status_seamonkey210',
    'cf_tracking_firefox14',
    'cf_status_firefox14',
    'cf_tracking_thunderbird14',
    'cf_status_thunderbird14',
    'cf_tracking_seamonkey211',
    'cf_status_seamonkey211',
    'cf_tracking_firefox15',
    'cf_status_firefox15',
    'cf_tracking_thunderbird15',
    'cf_status_thunderbird15',
    'cf_tracking_seamonkey212',
    'cf_status_seamonkey212',
    'cf_tracking_firefox16',
    'cf_status_firefox16',
    'cf_tracking_thunderbird16',
    'cf_status_thunderbird16',
    'cf_tracking_seamonkey213',
    'cf_status_seamonkey213',
    'cf_tracking_firefox17',
    'cf_status_firefox17',
    'cf_tracking_thunderbird17',
    'cf_status_thunderbird17',
    'cf_tracking_seamonkey214',
    'cf_status_seamonkey214',
    'cf_tracking_esr10',
    'cf_status_esr10',
    'cf_tracking_thunderbird_esr10',
    'cf_status_thunderbird_esr10',
    'cf_blocking_kilimanjaro',
    'cf_tracking_firefox18',
    'cf_status_firefox18',
    'cf_tracking_thunderbird18',
    'cf_status_thunderbird18',
    'cf_tracking_seamonkey215',
    'cf_status_seamonkey215',
    'cf_tracking_firefox19',
    'cf_status_firefox19',
    'cf_tracking_thunderbird19',
    'cf_status_thunderbird19',
    'cf_tracking_seamonkey216',
    'cf_status_seamonkey216',
    'cf_tracking_firefox20',
    'cf_status_firefox20',
    'cf_tracking_thunderbird20',
    'cf_status_thunderbird20',
    'cf_tracking_seamonkey217',
    'cf_status_seamonkey217',
    'cf_tracking_firefox21',
    'cf_status_firefox21',
    'cf_tracking_thunderbird21',
    'cf_status_thunderbird21',
    'cf_tracking_seamonkey218',
    'cf_status_seamonkey218',
];

# Who to CC on particular bugmails when certain groups are added or removed.
our %group_change_notification = (
  'addons-security'           => ['amo-editors@mozilla.org'], 
  'bugzilla-security'         => ['security@bugzilla.org'],
  'client-services-security'  => ['amo-admins@mozilla.org', 'web-security@mozilla.org'],
  'core-security'             => ['security@mozilla.org'],
  'mozilla-services-security' => ['web-security@mozilla.org'],
  'tamarin-security'          => ['tamarinsecurity@adobe.com'],
  'websites-security'         => ['web-security@mozilla.org'],
  'webtools-security'         => ['web-security@mozilla.org'],
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
    qr/^cf_blocking_basecamp/     => 'kilimanjaro-drivers',
    qr/^cf_tracking_b2g/          => 'kilimanjaro-drivers',
    qr/^cf_blocking_b2g/          => 'kilimanjaro-drivers',
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

# Groups in which you can always file a bug, regardless of product or user.
our @always_fileable_groups = qw(
    addons-security
    bugzilla-security
    client-services-security
    consulting
    core-security
    finance
    infra
    infrasec
    l20n-security
    marketing-private
    mozilla-confidential
    mozilla-corporation-confidential
    mozilla-foundation-confidential
    mozilla-engagement
    mozilla-messaging-confidential
    partner-confidential
    payments-confidential
    tamarin-security
    websites-security
    webtools-security
    winqual-data
);

# Mapping of products to their security bits
our %product_sec_groups = (
    "addons.mozilla.org"           => 'client-services-security',
    "Air Mozilla"                  => 'mozilla-corporation-confidential',
    "Android Background Services"  => 'mozilla-services-security',
    "AUS"                          => 'client-services-security',
    "Bugzilla"                     => 'bugzilla-security',
    "bugzilla.mozilla.org"         => 'bugzilla-security',
    "Community Tools"              => 'websites-security',
    "Developer Documentation"      => 'websites-security',
    "Developer Ecosystem"          => 'client-services-security',
    "Finance"                      => 'finance',
    "Firefox Health Report"        => 'mozilla-services-security',
    "Input"                        => 'websites-security',
    "Internet Public Policy"       => 'mozilla-corporation-confidential',
    "Infrastructure & Operations"  => 'mozilla-corporation-confidential',
    "L20n"                         => 'l20n-security',
    "Legal"                        => 'legal',
    "Marketing"                    => 'marketing-private',
    "Marketplace"                  => 'client-services-security',
    "Mozilla Corporation"          => 'mozilla-corporation-confidential',
    "Mozilla Developer Network"    => 'websites-security',
    "Mozilla Grants"               => 'grants',
    "Mozilla Messaging"            => 'mozilla-messaging-confidential',
    "Mozilla Metrics"              => 'metrics-private',
    "mozilla.org"                  => 'mozilla-corporation-confidential',
    "Mozilla PR"                   => 'pr-private',
    "Mozilla QA"                   => 'mozilla-corporation-confidential',
    "Mozilla Reps"                 => 'mozilla-reps',
    "Mozilla Services"             => 'mozilla-services-security',
    "mozillaignite"                => 'websites-security',
    "Popcorn"                      => 'websites-security',
    "Privacy"                      => 'privacy',
    "quality.mozilla.org"          => 'websites-security',
    "Socorro"                      => 'client-services-security',
    "Snippets"                     => 'websites-security',
    "support.mozilla.org"          => 'websites-security',
    "support.mozillamessaging.com" => 'websites-security',
    "Talkback"                     => 'talkback-private',
    "Tamarin"                      => 'tamarin-security',
    "Testopia"                     => 'bugzilla-security',
    "Web Apps"                     => 'client-services-security',
    "Webmaker"                     => 'websites-security',
    "Websites"                     => 'websites-security',
    "Webtools"                     => 'webtools-security',
    "www.mozilla.org"              => 'websites-security',
    "_default"                     => 'core-security'
);

# Automatically CC users to bugs filed into configured groups and products
our %group_auto_cc = (
    'partner-confidential' => {
        'Marketing' => ['jbalaco@mozilla.com'],
        '_default'  => ['mbest@mozilla.com'],
    },
);

# Force create-bug template by product
# Users in 'include' group will be fored into using the form.
our %create_bug_formats = (
    'Mozilla Developer Network' => {
        'format'  => 'mdn',
        'include' => 'everyone',
    },
    'Legal' => {
        'format'  => 'legal',
        'include' => 'everyone',
    },
    'Internet Public Policy' => {
        'format'  => 'ipp',
        'include' => 'everyone',
    },
);

# List of named queries which will be added to new users' footer
our @default_named_queries = (
    {
        name  => 'Bugs Filed Today',
        query => 'query_format=advanced&chfieldto=Now&chfield=[Bug creation]&chfieldfrom=-24h&order=bug_id',
    },
);

1;
