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
# The Original Code is the Component Watching Extension
#
# The Initial Developer of the Original Code is the Mozilla Foundation
# Portions created by the Initial Developers are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Byron Jones <bjones@mozilla.com>

package Bugzilla::Extension::ComponentWatching;
use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Group;
use Bugzilla::User;
use Bugzilla::User::Setting;

our $VERSION = '1.1';

use constant REL_COMPONENT_WATCHER => 15;

#
# installation
#

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    $args->{'schema'}->{'component_watch'} = {
        FIELDS => [
            user_id => {
                TYPE => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'profiles',
                    COLUMN => 'userid',
                    DELETE => 'CASCADE',
                }
            },
            component_id => {
                TYPE => 'INT2',
                NOTNULL => 0,
                REFERENCES => {
                    TABLE  => 'components',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                }
            },
            product_id => {
                TYPE => 'INT2',
                NOTNULL => 0,
                REFERENCES => {
                    TABLE  => 'products',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                }
            },
        ],
    };
}

#
# templates
#

sub template_before_create {
    my ($self, $args) = @_;
    my $config = $args->{config};
    my $constants = $config->{CONSTANTS};
    $constants->{REL_COMPONENT_WATCHER} = REL_COMPONENT_WATCHER;
}

#
# preferences
#

sub user_preferences {
    my ($self, $args) = @_;
    my $tab = $args->{'current_tab'};
    return unless $tab eq 'component_watch';

    my $save = $args->{'save_changes'};
    my $handled = $args->{'handled'};
    my $user = Bugzilla->user;

    if ($save) {
        my ($sth, $sthAdd, $sthDel);

        if (Bugzilla->input_params->{'add'}) {
            # add watch

            my $productName = Bugzilla->input_params->{'add_product'};
            my $ra_componentNames = Bugzilla->input_params->{'add_component'};
            $ra_componentNames = [$ra_componentNames] unless ref($ra_componentNames);

            # load product and verify access
            my $product = Bugzilla::Product->new({ name => $productName });
            unless ($product && $user->can_access_product($product)) {
                ThrowUserError('product_access_denied', { product => $productName });
            }

            if (grep { $_ eq '' } @$ra_componentNames) {
                # watching a product
                _addProductWatch($user, $product);

            } else {
                # watching specific components
                foreach my $componentName (@$ra_componentNames) {
                    my $component = Bugzilla::Component->new({ name => $componentName, product => $product });
                    unless ($component) {
                        ThrowUserError('product_access_denied', { product => $productName });
                    }
                    _addComponentWatch($user, $component);
                }
            }

            _addDefaultSettings($user);

        } else {
            # remove watch(s)

            foreach my $name (keys %{Bugzilla->input_params}) {
                if ($name =~ /^del_(\d+)$/) {
                    _deleteProductWatch($user, $1);
                } elsif ($name =~ /^del_(\d+)_(\d+)$/) {
                    _deleteComponentWatch($user, $1, $2);
                }
            }
        }
    }

    $args->{'vars'}->{'watches'} = _getWatches($user);

    $$handled = 1;
}

#
# bugmail
#

sub bugmail_recipients {
    my ($self, $args) = @_;
    my $bug = $args->{'bug'};
    my $recipients = $args->{'recipients'};
    my $diffs = $args->{'diffs'};

    my ($oldProductId, $newProductId) = ($bug->product_id, $bug->product_id);
    my ($oldComponentId, $newComponentId) = ($bug->component_id, $bug->component_id);

    # notify when the product/component is switch from one being watched
    if (@$diffs) {
        # we need the product to process the component, so scan for that first
        my $product;
        foreach my $ra (@$diffs) {
            next if !(exists $ra->{'old'}
                      && exists $ra->{'field_name'});
            if ($ra->{'field_name'} eq 'product') {
                $product = Bugzilla::Product->new({ name => $ra->{'old'} });
                $oldProductId = $product->id;
            }
        }
        if (!$product) {
            $product = Bugzilla::Product->new($oldProductId);
        }
        foreach my $ra (@$diffs) {
            next if !(exists $ra->{'old'}
                      && exists $ra->{'field_name'});
            if ($ra->{'field_name'} eq 'component') {
                my $component = Bugzilla::Component->new({ name => $ra->{'old'}, product => $product });
                $oldComponentId = $component->id;
            }
        }
    }

    my $dbh = Bugzilla->dbh;
    my $sth = $dbh->prepare("
        SELECT user_id
          FROM component_watch
         WHERE ((product_id = ? OR product_id = ?) AND component_id IS NULL)
               OR (component_id = ? OR component_id = ?)
    ");
    $sth->execute($oldProductId, $newProductId, $oldComponentId, $newComponentId);
    while (my ($uid) = $sth->fetchrow_array) {
        if (!exists $recipients->{$uid}) {
            $recipients->{$uid}->{+REL_COMPONENT_WATCHER} = Bugzilla::BugMail::BIT_WATCHING();
        }
    }
}

sub bugmail_relationships {
    my ($self, $args) = @_;
    my $relationships = $args->{relationships};
    $relationships->{+REL_COMPONENT_WATCHER} = 'Component-Watcher';
}

#
# db
#

sub _getWatches {
    my ($user) = @_;
    my $dbh = Bugzilla->dbh;

    my $sth = $dbh->prepare("
        SELECT product_id, component_id 
          FROM component_watch
         WHERE user_id = ?
    ");
    $sth->execute($user->id);
    my @watches;
    while (my ($productId, $componentId) = $sth->fetchrow_array) {
        my $product = Bugzilla::Product->new($productId);
        next unless $product && $user->can_access_product($product);

        my %watch = ( product => $product );
        if ($componentId) {
            my $component = Bugzilla::Component->new($componentId);
            next unless $component;
            $watch{'component'} = $component;
        }

        push @watches, \%watch;
    }

    @watches = sort { 
        $a->{'product'}->name cmp $b->{'product'}->name
        || $a->{'component'}->name cmp $b->{'component'}->name
    } @watches;

    return \@watches;
}

sub _addProductWatch {
    my ($user, $product) = @_;
    my $dbh = Bugzilla->dbh;

    my $sth = $dbh->prepare("
        SELECT 1 
          FROM component_watch
         WHERE user_id = ? AND product_id = ? AND component_id IS NULL
    ");
    $sth->execute($user->id, $product->id);
    return if $sth->fetchrow_array;

    $sth = $dbh->prepare("
        DELETE FROM component_watch
              WHERE user_id = ? AND product_id = ?
    ");
    $sth->execute($user->id, $product->id);

    $sth = $dbh->prepare("
        INSERT INTO component_watch(user_id, product_id)
             VALUES (?, ?)
    ");
    $sth->execute($user->id, $product->id);
}

sub _addComponentWatch {
    my ($user, $component) = @_;
    my $dbh = Bugzilla->dbh;

    my $sth = $dbh->prepare("
        SELECT 1 
          FROM component_watch
         WHERE user_id = ?
               AND (component_id = ?  OR (product_id = ? AND component_id IS NULL))
    ");
    $sth->execute($user->id, $component->id, $component->product_id);
    return if $sth->fetchrow_array;

    $sth = $dbh->prepare("
        INSERT INTO component_watch(user_id, product_id, component_id)
             VALUES (?, ?, ?)
    ");
    $sth->execute($user->id, $component->product_id, $component->id);
}

sub _deleteProductWatch {
    my ($user, $productId) = @_;
    my $dbh = Bugzilla->dbh;

    my $sth = $dbh->prepare("
        DELETE FROM component_watch
              WHERE user_id = ? AND product_id = ? AND component_id IS NULL
    ");
    $sth->execute($user->id, $productId);
}

sub _deleteComponentWatch {
    my ($user, $productId, $componentId) = @_;
    my $dbh = Bugzilla->dbh;

    my $sth = $dbh->prepare("
        DELETE FROM component_watch
              WHERE user_id = ? AND product_id = ? AND component_id = ?
    ");
    $sth->execute($user->id, $productId, $componentId);
}

sub _addDefaultSettings {
    my ($user) = @_;
    my $dbh = Bugzilla->dbh;

    my $sth = $dbh->prepare("
        SELECT 1 
          FROM email_setting
         WHERE user_id = ? AND relationship = ?
    ");
    $sth->execute($user->id, REL_COMPONENT_WATCHER);
    return if $sth->fetchrow_array;
    
    my @defaultEvents = (
        EVT_OTHER,
        EVT_COMMENT,
        EVT_ATTACHMENT,
        EVT_ATTACHMENT_DATA,
        EVT_PROJ_MANAGEMENT,
        EVT_OPENED_CLOSED,
        EVT_KEYWORD,
        EVT_DEPEND_BLOCK,
        EVT_BUG_CREATED,
    );
    foreach my $event (@defaultEvents) {
        $dbh->do(
            "INSERT INTO email_setting(user_id,relationship,event) VALUES (?,?,?)",
            undef,
            $user->id, REL_COMPONENT_WATCHER, $event
        );
    }
}

__PACKAGE__->NAME;
