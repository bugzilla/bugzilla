# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::ComponentWatching;
use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Group;
use Bugzilla::User;
use Bugzilla::User::Setting;
use Bugzilla::Util qw(trim);

our $VERSION = '2';

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

sub install_update_db {
    my $dbh = Bugzilla->dbh;
    $dbh->bz_add_column(
        'components',
        'watch_user',
        {
            TYPE => 'INT3',
            REFERENCES => {
                TABLE  => 'profiles',
                COLUMN => 'userid',
                DELETE => 'SET NULL',
            }
        }
    );
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
# user-watch
#

BEGIN {
    *Bugzilla::Component::watch_user = \&_component_watch_user;
}

sub _component_watch_user {
    my ($self) = @_;
    return unless $self->{watch_user};
    $self->{watch_user_object} ||= Bugzilla::User->new($self->{watch_user});
    return $self->{watch_user_object};
}

sub object_columns {
    my ($self, $args) = @_;
    my $class = $args->{class};
    my $columns = $args->{columns};
    return unless $class->isa('Bugzilla::Component');

    push(@$columns, 'watch_user');
}

sub object_update_columns {
    my ($self, $args) = @_;
    my $object = $args->{object};
    my $columns = $args->{columns};
    return unless $object->isa('Bugzilla::Component');

    push(@$columns, 'watch_user');

    # editcomponents.cgi doesn't call set_all, so we have to do this here
    my $input = Bugzilla->input_params;
    $object->set('watch_user', $input->{watch_user});
}

sub object_validators {
    my ($self, $args) = @_;
    my $class = $args->{class};
    my $validators = $args->{validators};
    return unless $class->isa('Bugzilla::Component');

    $validators->{watch_user} = \&_check_watch_user;
}

sub object_before_create {
    my ($self, $args) = @_;
    my $class = $args->{class};
    my $params = $args->{params};
    return unless $class->isa('Bugzilla::Component');

    my $input = Bugzilla->input_params;
    $params->{watch_user} = $input->{watch_user};
}

sub object_end_of_update {
    my ($self, $args) = @_;
    my $object = $args->{object};
    my $old_object = $args->{old_object};
    my $changes = $args->{changes};
    return unless $object->isa('Bugzilla::Component');

    my $old_id = $old_object->watch_user ? $old_object->watch_user->id : 0;
    my $new_id = $object->watch_user ? $object->watch_user->id : 0;
    return if $old_id == $new_id;

    $changes->{watch_user} = [ $old_id ? $old_id : undef, $new_id ? $new_id : undef ];
}

sub _check_watch_user {
    my ($self, $value, $field) = @_;

    $value = trim($value || '');
    if ($value eq '') {
        ThrowUserError('component_watch_missing_watch_user');
    }
    if ($value !~ /\.bugs$/i) {
        ThrowUserError('component_watch_invalid_watch_user');
    }
    return Bugzilla::User->check($value)->id;
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
    my $vars = $args->{'vars'};
    my $user = Bugzilla->user;
    my $input = Bugzilla->input_params;

    if ($save) {
        my ($sth, $sthAdd, $sthDel);

        if ($input->{'add'} && $input->{'add_product'}) {
            # add watch

            my $productName = $input->{'add_product'};
            my $ra_componentNames = $input->{'add_component'};
            $ra_componentNames = [$ra_componentNames || ''] unless ref($ra_componentNames);

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

            foreach my $name (keys %$input) {
                if ($name =~ /^del_(\d+)$/) {
                    _deleteProductWatch($user, $1);
                } elsif ($name =~ /^del_(\d+)_(\d+)$/) {
                    _deleteComponentWatch($user, $1, $2);
                }
            }
        }
    }

    $vars->{'add_product'}   = $input->{'product'};
    $vars->{'add_component'} = $input->{'component'};
    $vars->{'watches'}       = _getWatches($user);
    $vars->{'user_watches'}  = _getUserWatches($user);

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

    # add component watchers
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

    # add component watchers from watch-users
    my $uidList = join(',', keys %$recipients);
    $sth = $dbh->prepare("
        SELECT component_watch.user_id
          FROM components
               INNER JOIN component_watch ON component_watch.component_id = components.id
         WHERE components.watch_user in ($uidList)
    ");
    $sth->execute();
    while (my ($uid) = $sth->fetchrow_array) {
        if (!exists $recipients->{$uid}) {
            $recipients->{$uid}->{+REL_COMPONENT_WATCHER} = Bugzilla::BugMail::BIT_WATCHING();
        }
    }

    # add watch-users from component watchers
    $sth = $dbh->prepare("
        SELECT watch_user
          FROM components
         WHERE (id = ? OR id = ?)
               AND (watch_user IS NOT NULL)
    ");
    $sth->execute($oldComponentId, $newComponentId);
    while (my ($uid) = $sth->fetchrow_array) {
        if (!exists $recipients->{$uid}) {
            $recipients->{$uid}->{+REL_COMPONENT_WATCHER} = Bugzilla::BugMail::BIT_DIRECT();
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

sub _getUserWatches {
    my ($user) = @_;
    my $dbh = Bugzilla->dbh;

    my $sth = $dbh->prepare("
        SELECT components.product_id, components.id as component, profiles.login_name
          FROM watch
               INNER JOIN components ON components.watch_user = watched
               INNER JOIN profiles ON profiles.userid = watched
         WHERE watcher = ?
    ");
    $sth->execute($user->id);
    my @watches;
    while (my ($productId, $componentId, $login) = $sth->fetchrow_array) {
        my $product = Bugzilla::Product->new($productId);
        next unless $product && $user->can_access_product($product);

        my %watch = (
            product => $product,
            component => Bugzilla::Component->new($componentId),
            user      => Bugzilla::User->check($login),
        );
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
