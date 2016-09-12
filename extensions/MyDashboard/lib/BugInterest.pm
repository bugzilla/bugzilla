# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MyDashboard::BugInterest;

use 5.10.1;
use strict;

use parent qw(Bugzilla::Object);

#####################################################################
# Overriden Constants that are used as methods
#####################################################################

use constant DB_TABLE       => 'bug_interest';
use constant DB_COLUMNS     => qw( id bug_id user_id modification_time );
use constant UPDATE_COLUMNS => qw( modification_time );
use constant VALIDATORS     => {};
use constant LIST_ORDER     => 'id';
use constant NAME_FIELD     => 'id';

# turn off auditing and exclude these objects from memcached
use constant { AUDIT_CREATES => 0,
               AUDIT_UPDATES => 0,
               AUDIT_REMOVES => 0,
               USE_MEMCACHED => 0 };

#####################################################################
# Provide accessors for our columns
#####################################################################

sub id                { return $_[0]->{id}                }
sub bug_id            { return $_[0]->{bug_id}            }
sub user_id           { return $_[0]->{user_id}           }
sub modification_time { return $_[0]->{modification_time} }

sub mark {
    my ($class, $user_id, $bug_id, $timestamp) = @_;

    my ($interest) = @{ $class->match({ user_id => $user_id,
                                        bug_id => $bug_id }) };
    if ($interest) {
        $interest->set(modification_time => $timestamp);
        $interest->update();
        return $interest;
    }
    else {
        return $class->create({
            user_id           => $user_id,
            bug_id            => $bug_id,
            modification_time => $timestamp,
        });
    }
}

sub unmark {
    my ($class, $user_id, $bug_id) = @_;

    my ($interest) = @{ $class->match({ user_id => $user_id,
                                        bug_id  => $bug_id }) };
    if ($interest) {
        $interest->remove_from_db();
    }
}

1;
