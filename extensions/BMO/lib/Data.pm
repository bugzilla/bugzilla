# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BMO::Data;
use strict;

use base qw(Exporter);
use Tie::IxHash;

our @EXPORT = qw( $cf_visible_in_products
                  %group_change_notification
                  $cf_setters
                  @always_fileable_groups
                  %group_auto_cc
                  %product_sec_groups
                  %create_bug_formats
                  @default_named_queries
                  %autodetect_attach_urls );

# Creating an attachment whose contents is a URL matching one of these regexes
# will result in the user being redirected to that URL when viewing the
# attachment.
our %autodetect_attach_urls = (
    github_pr => {
        regex        => qr#^https://github\.com/[^/]+/[^/]+/pull/\d+/?$#i,
        content_type => 'text/x-github-pull-request',
    },
    reviewboard => {
        regex        => qr#^https?://reviewboard(?:-dev)?\.(?:allizom|mozilla)\.org/r/\d+/?#i,
        content_type => 'text/x-review-board-request',
    },
    google_docs => {
        regex        => qr#^https://docs\.google\.com/(?:document|spreadsheets|presentation)/d/#i,
        content_type => 'text/x-google-doc',
    },
);

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
    qr/^cf_colo_site$/ => {
        "mozilla.org" => [
            "Server Operations",
            "Server Operations: DCOps",
            "Server Operations: Projects",
            "Server Operations: RelEng",
            "Server Operations: Security",
        ],
        "Infrastructure & Operations" => [
            "RelOps",
            "RelOps: Puppet",
            "DCOps",
        ],
    },
    qr/^cf_office$/ => {
        "mozilla.org" => ["Server Operations: Desktop Issues"],
    },
    qr/^cf_crash_signature$/ => {
        "Add-on SDK"                  => [],
        "addons.mozilla.org"          => [],
        "Android Background Services" => [],
        "Calendar"                    => [],
        "Camino"                      => [],
        "Composer"                    => [],
        "Core"                        => [],
        "Directory"                   => [],
        "Fennec"                      => [],
        "Firefox"                     => [],
        "Firefox for Android"         => [],
        "Firefox for Metro"           => [],
        "Firefox OS"                  => [],
        "JSS"                         => [],
        "MailNews Core"               => [],
        "Mozilla Labs"                => [],
        "Mozilla Localizations"       => [],
        "mozilla.org"                 => [],
        "Cloud Services"              => [],
        "NSPR"                        => [],
        "NSS"                         => [],
        "Other Applications"          => [],
        "Penelope"                    => [],
        "Plugins"                     => [],
        "Release Engineering"         => [],
        "Rhino"                       => [],
        "SeaMonkey"                   => [],
        "Tamarin"                     => [],
        "Tech Evangelism"             => [],
        "Testing"                     => [],
        "Thunderbird"                 => [],
        "Toolkit"                     => [],
    },
    qr/^cf_due_date$/ => {
        "bugzilla.mozilla.org"        => [],
        "Community Building"          => [],
        "Data & BI Services Team"     => [],
        "Data Compliance"             => [],
        "Developer Engagement"        => [],
        "Infrastructure & Operations" => [],
        "Marketing"                   => [],
        "mozilla.org"                 => ["Security Assurance: Review Request"],
        "Mozilla Metrics"             => [],
        "Mozilla PR"                  => [],
        "Mozilla Reps"                => [],
    },
    qr/^cf_locale$/ => {
        "Mozilla Localizations" => ['Other'],
        "www.mozilla.org"       => [],
    },
    qr/^cf_mozilla_project$/ => {
        "Data & BI Services Team" => [],
    },
    qr/^cf_machine_state$/ => {
        "Release Engineering" => ["Buildduty"],
    },
    qr/^cf_rank$/ => {
        "Core"                => [],
        "Firefox for Android" => [],
        "Firefox for iOS"     => [],
        "Firefox"             => [],
        "Hello (Loop)"        => [],
        "Cloud Services"      => [],
        "Toolkit"             => [],
    },
);

# Who to CC on particular bugmails when certain groups are added or removed.
our %group_change_notification = (
  'addons-security'           => ['amo-editors@mozilla.org'],
  'bugzilla-security'         => ['security@bugzilla.org'],
  'client-services-security'  => ['amo-admins@mozilla.org', 'web-security@mozilla.org'],
  'core-security'             => ['security@mozilla.org'],
  'cloud-services-security'   => ['web-security@mozilla.org'],
  'tamarin-security'          => ['tamarinsecurity@adobe.com'],
  'websites-security'         => ['web-security@mozilla.org'],
  'webtools-security'         => ['web-security@mozilla.org'],
);

# Who can set custom flags (use full field names only, not regex's)
our $cf_setters = {
    'cf_colo_site'  => [ 'infra', 'build' ],
    'cf_rank'       => [ 'rank-setters' ],
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
    mozilla-employee-confidential
    mozilla-foundation-confidential
    mozilla-engagement
    mozilla-messaging-confidential
    partner-confidential
    payments-confidential
    tamarin-security
    websites-security
    webtools-security
);

# Mapping of products to their security bits
our %product_sec_groups = (
    "addons.mozilla.org"           => 'client-services-security',
    "Air Mozilla"                  => 'mozilla-employee-confidential',
    "Android Background Services"  => 'cloud-services-security',
    "Audio/Visual Infrastructure"  => 'mozilla-employee-confidential',
    "AUS"                          => 'client-services-security',
    "Bugzilla"                     => 'bugzilla-security',
    "bugzilla.mozilla.org"         => 'bugzilla-security',
    "Community Tools"              => 'websites-security',
    "Data & BI Services Team"      => 'metrics-private',
    "Developer Documentation"      => 'websites-security',
    "Developer Ecosystem"          => 'client-services-security',
    "Finance"                      => 'finance',
    "Firefox Friends"              => 'mozilla-employee-confidential',
    "Firefox Health Report"        => 'cloud-services-security',
    "Infrastructure & Operations"  => 'mozilla-employee-confidential',
    "Input"                        => 'websites-security',
    "Intellego"                    => 'intellego-team',
    "Internet Public Policy"       => 'mozilla-employee-confidential',
    "L20n"                         => 'l20n-security',
    "Legal"                        => 'legal',
    "Recruiting"                   => 'hr',
    "Marketing"                    => 'marketing-private',
    "Marketplace"                  => 'client-services-security',
    "Mozilla Communities"          => 'mozilla-communities-security',
    "Mozilla Corporation"          => 'mozilla-employee-confidential',
    "Mozilla Developer Network"    => 'websites-security',
    "Mozilla Foundation"           => 'mozilla-employee-confidential',
    "Mozilla Grants"               => 'grants',
    "mozillaignite"                => 'websites-security',
    "Mozilla Messaging"            => 'mozilla-messaging-confidential',
    "Mozilla Metrics"              => 'metrics-private',
    "mozilla.org"                  => 'mozilla-employee-confidential',
    "Mozilla PR"                   => 'pr-private',
    "Mozilla QA"                   => 'mozilla-employee-confidential',
    "Mozilla Reps"                 => 'mozilla-reps',
    "Cloud Services"               => 'cloud-services-security',
    "Popcorn"                      => 'websites-security',
    "Privacy"                      => 'privacy',
    "quality.mozilla.org"          => 'websites-security',
    "Release Engineering"          => 'mozilla-employee-confidential',
    "Snippets"                     => 'websites-security',
    "Socorro"                      => 'client-services-security',
    "support.mozillamessaging.com" => 'websites-security',
    "support.mozilla.org"          => 'websites-security',
    "Talkback"                     => 'talkback-private',
    "Tamarin"                      => 'tamarin-security',
    "Taskcluster"                  => 'taskcluster-security',
    "Testopia"                     => 'bugzilla-security',
    "Tree Management"              => 'mozilla-employee-confidential',
    "Web Apps"                     => 'client-services-security',
    "Webmaker"                     => 'websites-security',
    "Websites"                     => 'websites-security',
    "Webtools"                     => 'webtools-security',
    "www.mozilla.org"              => 'websites-security',
    "Mozilla Foundation Operations" => 'mozilla-foundation-operations',
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
# Users in 'include' group will be forced into using the form.
our %create_bug_formats = (
    'Data Compliance' => {
        'format'  => 'data-compliance',
        'include' => 'everyone',
    },
    'Mozilla Developer Network' => {
        'format'  => 'mdn',
        'include' => 'everyone',
    },
    'Legal' => {
        'format'  => 'legal',
        'include' => 'everyone',
    },
    'Recruiting' => {
        'format' => 'recruiting',
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
