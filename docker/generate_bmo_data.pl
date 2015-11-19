#!/usr/bin/perl -w
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use strict;
use warnings;

use lib '.';

use Bugzilla;
use Bugzilla::User;
use Bugzilla::Install;
use Bugzilla::Milestone;
use Bugzilla::Product;
use Bugzilla::Component;
use Bugzilla::Group;
use Bugzilla::Version;
use Bugzilla::Constants;
use Bugzilla::Keyword;
use Bugzilla::Config qw(:admin);
use Bugzilla::User::Setting;
use Bugzilla::Status;

my $dbh = Bugzilla->dbh;

# set Bugzilla usage mode to USAGE_MODE_CMDLINE
Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $admin_email = shift || 'admin@mozilla.bugs';
Bugzilla->set_user(Bugzilla::User->check({ name => $admin_email }));

##########################################################################
#  Set Default User Preferences
##########################################################################

my %user_prefs = (
    post_bug_submit_action => 'nothing',
    bugmail_new_prefix     => 'on',
    comment_box_position   => 'after_comments',
    comment_sort_order     => 'oldest_to_newest',
    csv_colsepchar         => ',',
    display_quips          => 'off',
    email_format           => 'text_only',
    headers_in_body        => 'off',
    inline_history         => 'on',
    lang                   => 'en',
    orange_factor          => 'off',
    per_bug_queries        => 'off',
    possible_duplicates    => 'on',
    post_bug_submit_action => 'same_bug',
    product_chooser        => 'pretty_product_chooser',
    quicksearch_fulltext   => 'off',
    quote_replies          => 'quoted_reply',
    requestee_cc           => 'on',
    request_nagging        => 'on',
    show_gravatars         => 'On',
    show_my_gravatar       => 'On',
    skin                   => 'Mozilla',
    state_addselfcc        => 'cc_unless_role',
    timezone               => 'local',
    zoom_textareas         => 'off',
);

foreach my $pref (keys %user_prefs) {
    my $value = $user_prefs{$pref};
    Bugzilla::User::Setting::set_default($pref, $value, 1);
}

############################################################
# OS, Platform, Priority
############################################################

my @priorities = qw(
    --
    P1
    P2
    P3
    P4
    P5
);

if (!$dbh->selectrow_array("SELECT 1 FROM priority WHERE value = 'P1'")) {
    $dbh->do("DELETE FROM priority");
    my $count = 100;
    foreach my $priority (@priorities) {
        $dbh->do("INSERT INTO priority (value, sortkey) VALUES (?, ?)",
                 undef, ($priority, $count+100));
    }
}

my @platforms = qw(
    All
    ARM
    x86
    x86_64
    Unspecified
    Other
);

if (!$dbh->selectrow_array("SELECT 1 FROM rep_platform WHERE value = 'ARM'")) {
    $dbh->do("DELETE FROM rep_platform");
    my $count = 100;
    foreach my $platform (@platforms) {
        $dbh->do("INSERT INTO rep_platform (value, sortkey) VALUES (?, ?)",
                 undef, ($platform, $count+100));
    }
}

my @oses= (
    'All',
    'Windows',
    'Windows XP',
    'Windows Server 2008',
    'Windows Vista',
    'Windows 7',
    'Windows 8',
    'Windows 8.1',
    'Windows 10',
    'Windows Phone',
    'Mac OS X',
    'Linux',
    'Gonk (Firefox OS)',
    'Android',
    'iOS',
    'iOS 7',
    'iOS 8',
    'BSDI',
    'FreeBSD',
    'NetBSD',
    'OpenBSD',
    'Unspecified',
    'Other'
);

if (!$dbh->selectrow_array("SELECT 1 FROM op_sys WHERE value = 'AIX'")) {
    $dbh->do("DELETE FROM op_sys");
    my $count = 100;
    foreach my $os (@oses) {
        $dbh->do("INSERT INTO op_sys (value, sortkey) VALUES (?, ?)",
                 undef, ($os, $count+100));
    }
}

##########################################################################
# Create Users
##########################################################################
# First of all, remove the default .* regexp for the editbugs group.
my $group = new Bugzilla::Group({ name => 'editbugs' });
$group->set_user_regexp('');
$group->update();

my @users = (
    {
        login    => 'nobody@mozilla.org',
        realname => 'Nobody; OK to take it and work on it',
        password => '*'
    },
);

print "creating user accounts...\n";
foreach my $user (@users) {
    if (is_available_username($user->{login})) {
        Bugzilla::User->create(
            {   login_name    => $user->{login},
                realname      => $user->{realname},
                cryptpassword => $user->{password},
            }
        );
        if ($user->{admin}) {
            Bugzilla::Install::make_admin($user->{login});
        }
    }
}

##########################################################################
# Create Classifications
##########################################################################
my @classifications = (
    {
        name        => "Client Software",
        description => "End User Products developed by mozilla.org contributors"
    },
    {
        name        => "Components",
        description => "Standalone components that can be used by other products. " .
                       "Core, Directory, NSPR, NSS and Toolkit are used by Gecko " .
                       "(which is in turn used by Firefox, Thunderbird, SeaMonkey, " .
                       "Fennec, and others)",
    },
    {
        name        => "Server Software",
        description => "Web Server software developed by mozilla.org contributors " .
                       "to aid the development of mozilla.org products"
    },
    {
        name        => "Other",
        description => "Everything else - websites, Labs, important things which aren't code"
    },
    {
        name        => "Graveyard",
        description => "Old, retired products"
    },
);

print "creating classifications...\n";
for my $class (@classifications) {
    my $new_class = Bugzilla::Classification->new({ name => $class->{name} });
    if (!$new_class) {
        $dbh->do('INSERT INTO classifications (name, description) VALUES (?, ?)',
                 undef, ( $class->{name}, $class->{description} ));
    }
}

##########################################################################
# Create Some Products
##########################################################################
my @products = (
    {
        classification   => 'Client Software',
        product_name     => 'Firefox',
        description      => 'For bugs in Firefox Desktop, the Mozilla Foundations ' .
                            'web browser. For Firefox user interface issues in ' .
                            'menus, developer tools, bookmarks, location bar, and ' .
                            'preferences. Many Firefox bugs will either be filed ' .
                            'here or in the <a href="https://bugzilla.mozilla.org/describecomponents.cgi?product=Core">Core</a> product.' .
                            '(<a href="https://wiki.mozilla.org/Modules/All#Firefox">more info</a>)',
        versions         => [
                                '34 Branch',
                                '35 Branch',
                                '36 Branch',
                                '37 Branch',
                                'Trunk',
                                'unspecified'
                            ],
        milestones       => [
                                'Firefox 36',
                                '---',
                                'Firefox 37',
                                'Firefox 38',
                                'Firefox 39',
                                'Future'
                            ],
        defaultmilestone => '---',
        components       => [
            {
                name           => 'General',
                description    => 'For bugs in Firefox which do not fit into ' .
                                  'other more specific Firefox components',
                initialowner   => 'nobody@mozilla.org',
                initialqaowner => '',
                initial_cc     => [],
                watch_user     => 'general@firefox.bugs'
            }
        ],
    },
);

my $default_op_sys_id
    = $dbh->selectrow_array("SELECT id FROM op_sys WHERE value = 'Unspecified'");
my $default_platform_id
    = $dbh->selectrow_array("SELECT id FROM rep_platform WHERE value = 'Unspecified'");

print "creating products...\n";
for my $product (@products) {
    my $new_product =
        Bugzilla::Product->new({ name => $product->{product_name} });
    if (!$new_product) {
        my $class_id = 1;
        if ($product->{classification}) {
            $class_id = Bugzilla::Classification->new({ name => $product->{classification} })->id;
        }
        $dbh->do('INSERT INTO products (name, description, classification_id,
                                        default_op_sys_id, default_platform_id)
                  VALUES (?, ?, ?, ?, ?)',
            undef, ( $product->{product_name}, $product->{description},
                     $class_id, $default_op_sys_id, $default_platform_id ));

        $new_product
            = new Bugzilla::Product( { name => $product->{product_name} } );

        $dbh->do( 'INSERT INTO milestones (product_id, value) VALUES (?, ?)',
            undef, ( $new_product->id, $product->{defaultmilestone} ) );

        # Now clear the internal list of accessible products.
        delete Bugzilla->user->{selectable_products};

        foreach my $component (@{ $product->{components} }) {
            if (!Bugzilla::User->new({ name => $component->{watch_user} })) {
                Bugzilla::User->create({
                    login_name    => $component->{watch_user},
                    cryptpassword => '*',
                });
            }
            Bugzilla->input_params({ watch_user => $component->{watch_user} });
            Bugzilla::Component->create({
                name             => $component->{name},
                product          => $new_product,
                description      => $component->{description},
                initialowner     => $component->{initialowner},
                initialqacontact => $component->{initialqacontact} || '',
                initial_cc       => $component->{initial_cc} || [],
            });
        }
    }

    foreach my $version (@{ $product->{versions} }) {
        if (!new Bugzilla::Version({ name    => $version,
                                     product => $new_product }))
        {
            Bugzilla::Version->create({value => $version, product => $new_product});
        }
    }

    foreach my $milestone (@{ $product->{milestones} }) {
        if (!new Bugzilla::Milestone({ name    => $milestone,
                                       product => $new_product }))
        {
            $dbh->do('INSERT INTO milestones (product_id, value) VALUES (?,?)',
                     undef, $new_product->id, $milestone);
        }
    }
}

##########################################################################
# Create Groups
##########################################################################
my @groups = (
    {
        name         => 'core-security',
        description  => 'Security-Sensitive Core Bug',
        no_admin     => 1,
        bug_group    => 1,
        all_products => 1,
    },
    {
        name         => 'core-security-release',
        description  => 'Release-track Client Security Bug',
        no_admin     => 1,
        bug_group    => 1,
        all_products => 1,
    },
    {
        name         => 'core-security-release',
        description  => 'Release-track Client Security Bug',
        no_admin     => 1,
        bug_group    => 1,
        all_products => 1,
    },
    {
        name         => 'core-security-release',
        description  => 'Release-track Client Security Bug',
        no_admin     => 1,
        bug_group    => 1,
        all_products => 1,
    },
    {
        name         => 'can_edit_comments',
        description  => 'Members of this group will be able to edit comments',
        no_admin     => 0,
        bug_group    => 0,
        all_products => 0,
    },
    {
        name         => 'can_restrict_comments',
        description  => 'Members of this group will be able to restrict comments on bugs',
        no_admin     => 0,
        all_products => 0,
        bug_group    => 0,
    },
    {
        name         => 'timetrackers',
        description  => 'Time Trackers',
        no_admin     => 1,
        all_products => 0,
        bug_group    => 0,
    },
);

print "creating groups...\n";
foreach my $group (@groups) {
    my $name      = $group->{name};
    my $desc      = $group->{desc};
    my $bug_group = exists $group->{bug_group} ? $group->{bug_group} : 1;
    my $no_admin  = exists $group->{no_admin}  ? $group->{no_admin}  : 0;

    if (!Bugzilla::Group->new({ name => $name })) {
        my $new_group;
        if (exists $group->{no_admin} && $group->{no_admin}) {
            $dbh->do('INSERT INTO groups (name, description, isbuggroup, isactive)
                      VALUES (?, ?, 1, 1)',
                     undef, ($group->{name}, $group->{description}));
            $new_group = Bugzilla::Group->new({ name => $group->{name} });
        }
        else {
            $new_group
                = Bugzilla::Group->create({ name        => $group->{name},
                                            description => $group->{description},
                                            isbuggroup  => $group->{bug_group} });
        }

        if (exists $group->{all_products} && $group->{all_products}) {
            $dbh->do('INSERT INTO group_control_map
                     (group_id, product_id, entry, membercontrol, othercontrol, canedit)
                     SELECT ?, products.id, 0, ?, ?, 0 FROM products',
                     undef, ( $new_group->id, CONTROLMAPSHOWN, CONTROLMAPSHOWN ) );
        }
    }
}

# Update default security group settings for new products
my $default_security_group = Bugzilla::Group->new({ name => 'core-security' });
if ($default_security_group) {
    $dbh->do('UPDATE products SET security_group_id = ? WHERE security_group_id IS NULL',
             undef, $default_security_group->id);
}

##########################################################################
# Set Parameters
##########################################################################

my %set_params = (
    allowbugdeletion          => 1,
    allowuserdeletion         => 0,
    allow_attachment_deletion => 1,
    bonsai_url                => 'http://bonsai.mozilla.org',
    collapsed_comment_tags    => 'obsolete,spam,typo,me-too,advocacy,off-topic,offtopic,abuse,abusive',
    confirmuniqueusermatch    => 0,
    maxusermatches            => '100',
    debug_group               => 'editbugs',
    defaultpriority           => '--', # FIXME: add priority
    defaultquery              => 'resolution=---&emailassigned_to1=1&emailassigned_to2=1' .
                                 '&emailreporter2=1&emailqa_contact2=1&emailtype1=exact' .
                                 '&emailtype2=exact&order=Importance&keywords_type=allwords' .
                                 '&long_desc_type=substring',
    defaultseverity           => 'normal',
    edit_comments_group       => 'can_edit_comments',
    insidergroup              => 'core-security-release',
    last_visit_keep_days      => '28',
    lxr_url                   => 'http://mxr.mozilla.org/mozilla',
    lxr_root                  => 'mozilla/',
    mail_delivery_method      => 'Test',
    mailfrom                  => '"Bugzilla@Mozilla" <bugzilla-daemon@mozilla.org>',
    maintainer                => 'bugzilla-admin@mozilla.org',
    maxattachmentsize         => '10240',
    maxusermatches            => '100',
    mostfreqthreshold         => '5',
    mybugstemplate            => 'buglist.cgi?bug_status=UNCONFIRMED&amp;bug_status=NEW' .
                                 '&amp;bug_status=ASSIGNED&amp;bug_status=REOPENED' .
                                 '&amp;emailassigned_to1=1&amp;emailreporter1=1' .
                                 '&amp;emailtype1=exact&amp;email1=%userid%' .
                                 '&amp;field0-0-0=bug_status&amp;type0-0-0=notequals' .
                                 '&amp;value0-0-0=UNCONFIRMED&amp;field0-0-1=reporter' .
                                 '&amp;type0-0-1=equals&amp;value0-0-1=%userid%',
    persona_verify_url        => 'https://verifier.login.persona.org/verify',
    persona_includejs_url     => 'https://login.persona.org/include.js',
    quip_list_entry_control   => 'moderated',
    restrict_comments_group   => 'editbugs',
    restrict_comments_enable_group => 'can_restrict_comments',
    search_allow_no_criteria  => 0,
    strict_transport_security => 'include_subdomains',
    timetrackinggroup         => 'timetrackers',
    upgrade_notification      => 'disabled',
    useclassification         => 1,
    usetargetmilestone        => 1,
    usestatuswhiteboard       => 1,
    usebugaliases             => 1,
    useqacontact              => 1,
    use_mailer_queue          => 1,
    user_info_class           => 'Persona,CGI',
);

my $params_modified;
foreach my $param (keys %set_params) {
    my $value = $set_params{$param};
    next unless defined $value && Bugzilla->params->{$param} ne $value;
    SetParam($param, $value);
    $params_modified = 1;
}

write_params() if $params_modified;

##########################################################################
# Create flag types
##########################################################################
my @flagtypes = (
    {
        name             => 'review',
        desc             => 'The patch has passed review by a module owner or peer.',
        is_requestable   => 1,
        is_requesteeble  => 1,
        is_multiplicable => 1,
        grant_group      => '',
        target_type      => 'a',
        cc_list          => '',
        inclusions       => ['']
    },
    {
        name             => 'feedback',
        desc             => 'A particular person\'s input is requested for a patch, ' .
                            'but that input does not amount to an official review.',
        is_requestable   => 1,
        is_requesteeble  => 1,
        is_multiplicable => 1,
        grant_group      => '',
        target_type      => 'a',
        cc_list          => '',
        inclusions       => ['']
    }
);

print "creating flag types...\n";
foreach my $flag (@flagtypes) {
    next if new Bugzilla::FlagType({ name => $flag->{name} });
    my $grant_group_id = $flag->{grant_group}
                         ? Bugzilla::Group->new({ name => $flag->{grant_group} })->id
                         : undef;
    my $request_group_id = $flag->{request_group}
                           ? Bugzilla::Group->new({ name => $flag->{request_group} })->id
                           : undef;

    $dbh->do('INSERT INTO flagtypes (name, description, cc_list, target_type, is_requestable,
                                     is_requesteeble, is_multiplicable, grant_group_id, request_group_id)
                             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
             undef, ($flag->{name}, $flag->{desc}, $flag->{cc_list}, $flag->{target_type},
                     $flag->{is_requestable}, $flag->{is_requesteeble}, $flag->{is_multiplicable},
                     $grant_group_id, $request_group_id));

    my $type_id = $dbh->bz_last_key('flagtypes', 'id');

    foreach my $inclusion (@{$flag->{inclusions}}) {
        my ($product, $component) = split(':', $inclusion);
        my ($prod_id, $comp_id);
        if ($product) {
            my $prod_obj = Bugzilla::Product->new({ name => $product });
            $prod_id = $prod_obj->id;
            if ($component) {
                $comp_id = Bugzilla::Component->new({ name => $component, product => $prod_obj})->id;
            }
        }
        $dbh->do('INSERT INTO flaginclusions (type_id, product_id, component_id)
                  VALUES (?, ?, ?)',
                 undef, ($type_id, $prod_id, $comp_id));
    }
}

###########################################################
# Create bug status
###########################################################

my @statuses = (
    {
        value       => undef,
        transitions => [['UNCONFIRMED', 0], ['NEW', 0], ['ASSIGNED', 0]],
    },
    {
        value       => 'UNCONFIRMED',
        sortkey     => 100,
        isactive    => 1,
        isopen      => 1,
        transitions => [['NEW', 0], ['ASSIGNED', 0], ['RESOLVED', 0]],
    },
    {
        value       => 'NEW',
        sortkey     => 200,
        isactive    => 1,
        isopen      => 1,
        transitions => [['UNCONFIRMED', 0], ['ASSIGNED', 0], ['RESOLVED', 0]],
    },
    {
        value       => 'ASSIGNED',
        sortkey     => 300,
        isactive    => 1,
        isopen      => 1,
        transitions => [['UNCONFIRMED', 0], ['NEW', 0], ['RESOLVED', 0]],
    },
    {
        value       => 'REOPENED',
        sortkey     => 400,
        isactive    => 1,
        isopen      => 1,
        transitions => [['UNCONFIRMED', 0], ['NEW', 0], ['ASSIGNED', 0], ['RESOLVED', 0]],
    },
    {
        value       => 'RESOLVED',
        sortkey     => 500,
        isactive    => 1,
        isopen      => 0,
        transitions => [['UNCONFIRMED', 0], ['REOPENED', 0], ['VERIFIED', 0]],
    },
    {
        value       => 'VERIFIED',
        sortkey     => 600,
        isactive    => 1,
        isopen      => 0,
        transitions => [['UNCONFIRMED', 0], ['REOPENED', 0], ['RESOLVED', 0]],
    },
    {
        value       => 'CLOSED',
        sortkey     => 700,
        isactive    => 1,
        isopen      => 0,
        transitions => [['UNCONFIRMED', 0], ['REOPENED', 0], ['RESOLVED', 0]],
    },
);

if (!$dbh->selectrow_array("SELECT 1 FROM bug_status WHERE value = 'ASSIGNED'")) {
    $dbh->do('DELETE FROM bug_status');
    $dbh->do('DELETE FROM status_workflow');

    print "creating status workflow...\n";

    # One pass to add the status entries.
    foreach my $status (@statuses) {
        next if !$status->{value};
        $dbh->do('INSERT INTO bug_status (value, sortkey, isactive, is_open) VALUES (?, ?, ?, ?)',
            undef, ( $status->{value}, $status->{sortkey}, $status->{isactive}, $status->{isopen} ));
    }

    # Another pass to add the transitions.
    foreach my $status (@statuses) {
        my $old_id;
        if ($status->{value}) {
            my $from_status = new Bugzilla::Status({ name => $status->{value} });
            $old_id = $from_status->{id};
        } else {
            $old_id = undef;
        }

        foreach my $transition (@{$status->{transitions}}) {
            my $to_status = new Bugzilla::Status({ name => $transition->[0] });

            $dbh->do('INSERT INTO status_workflow (old_status, new_status, require_comment) VALUES (?, ?, ?)',
                undef, ( $old_id, $to_status->{id}, $transition->[1] ));
        }
    }
}

###########################################################
# Creating resolutions
###########################################################

my @resolutions = (
    {
        value    => '',
        sortkey  => 100,
        isactive => 1,
    },
    {
        value    => 'FIXED',
        sortkey  => 200,
        isactive => 1,
    },
    {
        value    => 'INVALID',
        sortkey  => 300,
        isactive => 1,
    },
    {
        value    => 'WONTFIX',
        sortkey  => 400,
        isactive => 1,
    },
    {
        value    => 'DUPLICATE',
        sortkey  => 700,
        isactive => 1,
    },
    {
        value    => 'WORKSFORME',
        sortkey  => 800,
        isactive => 1,
    },
    {
        value    => 'EXPIRED',
        sortkey  => 900,
        isactive => 1,
    },
    {
        value    => 'MOVED',
        sortkey  => 1000,
        isactive => 0,
    },
    {
        value    => 'INCOMPLETE',
        sortkey  => 850,
        isactive => 1,
    },
    {
        value    => 'SUPPORT',
        sortkey  => 875,
        isactive => 0,
    },
);

if (!$dbh->selectrow_array("SELECT 1 FROM resolution WHERE value = 'INCOMPLETE'")) {
    $dbh->do('DELETE FROM resolution');
    print "creating resolutions...\n";
    foreach my $resolution (@resolutions) {
        next if !$resolution->{value};
        $dbh->do('INSERT INTO resolution (value, sortkey, isactive) VALUES (?, ?, ?)',
            undef, ($resolution->{value}, $resolution->{sortkey}, $resolution->{isactive}));
    }
}

###########################################################
# Create Keywords
###########################################################

my @keywords = (
    {
        name        => 'regression',
        description => 'The problem was fixed, but then it came back (regressed) ' .
                       'and this new bug was filed to track the regression.'
    },
    {
        name        => 'relnote',
        description => 'This bug need to be put on release notes for next ' .
                       'milestone announcement.'
    },
);

print "creating keywords...\n";
foreach my $kw (@keywords) {
    next if new Bugzilla::Keyword({ name => $kw->{name} });
    Bugzilla::Keyword->create($kw);
}

print "installation and configuration complete!\n";
