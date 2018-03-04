#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use 5.10.1;
use strict;
use warnings;
use autodie;
use lib qw(. lib local/lib/perl5);
use constant HAVE_DATABASE => 0;

use if HAVE_DATABASE, 'Bugzilla';
BEGIN {
    if (HAVE_DATABASE) {
        Bugzilla->extensions
    }
}
use Bugzilla::DB::Schema;
use Module::Runtime qw(require_module);
use Test::More;

# These are all subclasses of Bugzilla::Object
my @packages = qw(
    Bugzilla::Attachment
    Bugzilla::Bug
    Bugzilla::BugUrl
    Bugzilla::BugUserLastVisit
    Bugzilla::Classification
    Bugzilla::Comment
    Bugzilla::Comment::TagWeights
    Bugzilla::Component
    Bugzilla::Extension::BugmailFilter::Filter
    Bugzilla::Extension::MyDashboard::BugInterest
    Bugzilla::Extension::Push::BacklogMessage
    Bugzilla::Extension::Push::Backoff
    Bugzilla::Extension::Push::LogEntry
    Bugzilla::Extension::Push::Message
    Bugzilla::Extension::Push::Option
    Bugzilla::Extension::Review::FlagStateActivity
    Bugzilla::Extension::TrackingFlags::Flag
    Bugzilla::Extension::TrackingFlags::Flag::Bug
    Bugzilla::Extension::TrackingFlags::Flag::Value
    Bugzilla::Extension::TrackingFlags::Flag::Visibility
    Bugzilla::Field
    Bugzilla::Field::Choice
    Bugzilla::Flag
    Bugzilla::FlagType
    Bugzilla::Group
    Bugzilla::Keyword
    Bugzilla::Milestone
    Bugzilla::Product
    Bugzilla::Search::Recent
    Bugzilla::Search::Saved
    Bugzilla::User
    Bugzilla::User::APIKey
    Bugzilla::User::Session
    Bugzilla::Version
    Bugzilla::Whine
    Bugzilla::Whine::Query
    Bugzilla::Whine::Schedule
);

# some of the subclasses have things to skip.
# 'name' means skip checking the name() method
# 'id' means skip checking the id() method
# 'db_name' means NAME_FIELD isn't a database field.
my %skip = (
    'Bugzilla::Attachment'                                 => { db_name => 1 },
    'Bugzilla::Comment'                                    => { db_name => 1 },
    'Bugzilla::Extension::BugmailFilter::Filter'           => { db_name => 1 },
    'Bugzilla::Extension::Push::BacklogMessage'            => { db_name => 1 },
    'Bugzilla::Extension::Push::Backoff'                   => { db_name => 1 },
    'Bugzilla::Extension::Push::Message'                   => { db_name => 1 },
    'Bugzilla::Extension::Push::Option'                    => { name => 1 },
    'Bugzilla::Extension::Review::FlagStateActivity'       => { db_name => 1 },
    'Bugzilla::Extension::TrackingFlags::Flag'             => { id   => 1 },
    'Bugzilla::Extension::TrackingFlags::Flag::Bug'        => { db_name => 1 },
    'Bugzilla::Extension::TrackingFlags::Flag::Value'      => { name => 1 },
    'Bugzilla::Extension::TrackingFlags::Flag::Visibility' => { db_name => 1 },
    'Bugzilla::Flag'                                       => { name => 1, id => 1 },
    'Bugzilla::Search::Recent'                             => { db_name => 1 },
    'Bugzilla::User'                                       => { name => 1 },
    'Bugzilla::Whine'                                      => { db_name => 1 },
    'Bugzilla::Whine::Query'                               => { name => 1 },
);

# this is kind of evil, but I want a copy
# of the schema without accessing a real DB.
my $schema = Bugzilla::DB::Schema::ABSTRACT_SCHEMA;
if (HAVE_DATABASE) {
    Bugzilla::Hook::process( 'db_schema_abstract_schema', { schema => $schema } );
}

foreach my $package (@packages) {
    next if $package =~ /^Bugzilla::Extension::/ && !HAVE_DATABASE;
    require_module($package);
    isa_ok($package, 'Bugzilla::Object');
    can_ok($package, qw( id name ID_FIELD NAME_FIELD));
    my $fake = bless {}, $package;
    my ($NAME_FIELD, $ID_FIELD);
    unless ($skip{$package}{id}) {
        $ID_FIELD = $package->ID_FIELD;
        $fake->{ $package->ID_FIELD } = 42;
        my $ok = eval {
            is($fake->id, 42, "$package->id is ID_FIELD");
            1;
        };
        ok($ok, "$package->id is not a fatal error");
    }
    unless ($skip{$package}{name}) {
        $NAME_FIELD = $package->NAME_FIELD;
        $fake->{ $package->NAME_FIELD } = 'camel';
        my $ok = eval {
            is($fake->name, 'camel', "$package->name is NAME_FIELD");
            1;
        };
        ok($ok, "$package->name is not a fatal error");
    }
    if ($package->can('DB_TABLE')) {
        my $table = $package->DB_TABLE;
        my $table_def = $schema->{$table};
        my %fields = @{ $table_def->{FIELDS} };
        ok($table_def, "$package has a table definition");
        if ($ID_FIELD and not $skip{$package}{db_id}) {
            ok($fields{ $ID_FIELD }, "$package table $table has column named by $ID_FIELD");
        }
        if ($NAME_FIELD and not $skip{$package}{db_name}) {
            ok($fields{ $NAME_FIELD }, "$package table $table has column named $NAME_FIELD");
        }
    }
}

done_testing;
