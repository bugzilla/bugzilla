# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::TellUsMore::VersionMirror;

use strict;
use base qw(Exporter);
our @EXPORT_OK = qw(update_versions);

use Bugzilla::Constants;
use Bugzilla::Product;

use Bugzilla::Extension::TellUsMore::Constants;

sub new {
    my $invocant = shift;
    my $class = ref($invocant) || $invocant;
    my $object = {};
    bless($object, $class);
    return $object;
}

sub created {
    my ($self, $created) = @_;
    return unless $self->_should_process($created);

    my $version = $self->_get($created);
    if ($version) {
        # version already exists, reactivate if required
        if (!$version->is_active) {
            $version->set_is_active(1);
            $version->update();
        }
    } else {
        # create version
        $self->_create_version($created->name);
    }
}

sub updated {
    my ($self, $old, $new) = @_;
    return unless $self->_should_process($old);

    my $version = $self->_get($old)
        or return;

    my $updated = 0;
    if ($version->name ne $new->name) {
        if ($version->bug_count) {
            # version renamed, but old name has bugs
            # create a new version to avoid touching bugs
            $self->_create_version($new->name);
            return;
        } else {
            # renaming the version is safe as it is unused
            $version->set_name($new->name);
            $updated = 1;
        }
    }

    if ($version->is_active != $new->is_active) {
        if ($new->is_active) {
            # activating, always safe
            $version->set_is_active(1);
            $updated = 1;
        } else {
            # can only deactivate when all source products agree
            my $active = 0;
            foreach my $product ($self->_sources) {
                foreach my $product_version (@{$product->versions}) {
                    next unless _version_eq($product_version, $new);
                    if ($product_version->is_active) {
                        $active = 1;
                        last;
                    }
                }
                last if $active;
            }
            if (!$active) {
                $version->set_is_active(0);
                $updated = 1;
            }
        }
    }

    if ($updated) {
        $version->update();
    }
}

sub deleted {
    my ($self, $deleted) = @_;
    return unless $self->_should_process($deleted);

    my $version = $self->_get($deleted)
        or return;

    # can only delete when all source products agreee
    foreach my $product ($self->_sources) {
        next if $product->name eq $deleted->product->name;
        if (grep { _version_eq($_, $version) } @{$product->versions}) {
            return;
        }
    }

    if ($version->bug_count) {
        # if there's active bugs, deactivate instead of deleting
        $version->set_is_active(0);
        $version->update();
    } else {
        # no bugs, safe to delete
        $version->remove_from_db();
    }
}

sub check_setup {
    my ($self, $full) = @_;
    $self->{setup_error} = '';

    if (!$self->_target) {
        $self->{setup_error} = "TellUsMore: Error: Target product '" . VERSION_TARGET_PRODUCT . "' does not exist.\n";
        return 0;
    }
    return 1 unless $full;

    foreach my $name (VERSION_SOURCE_PRODUCTS) {
        my $product = Bugzilla::Product->new({ name => $name });
        if (!$product) {
            $self->{setup_error} .= "TellUsMore: Warning: Source product '$name' does not exist.\n";
            next;
        }
        my $component = Bugzilla::Component->new({ product => $self->_target, name => $name });
        if (!$component) {
            $self->{setup_error} .= "TellUsMore: Warning: Target component '$name' does not exist.\n";
        }
    }
    return $self->{setup_error} ? 0 : 1;
}

sub setup_error {
    my ($self) = @_;
    return $self->{setup_error};
}

sub refresh {
    my ($self) = @_;
    foreach my $product ($self->_sources) {
        foreach my $version (@{$product->versions}) {
            if (!$self->_get($version)) {
                $self->created($version);
            }
        }
    }
}

sub _should_process {
    my ($self, $version) = @_;
    return 0 unless $self->check_setup();
    foreach my $product ($self->_sources) {
        return 1 if $version->product->name eq $product->name;
    }
    return 0;
}

sub _get {
    my ($self, $query) = @_;
    my $name = ref($query) ? $query->name : $query;
    my @versions = grep { $_->name eq $name } @{$self->_target->versions};
    return scalar @versions ? $versions[0] : undef;
}

sub _sources {
    my ($self) = @_;
    if (!$self->{sources} || scalar(@{$self->{sources}}) != scalar VERSION_SOURCE_PRODUCTS) {
        my @sources;
        foreach my $name (VERSION_SOURCE_PRODUCTS) {
            my $product = Bugzilla::Product->new({ name => $name });
            push @sources, $product if $product;
        }
        $self->{sources} = \@sources;
    }
    return @{$self->{sources}};
}

sub _target {
    my ($self) = @_;
    $self->{target} ||= Bugzilla::Product->new({ name => VERSION_TARGET_PRODUCT });
    return $self->{target};
}

sub _version_eq {
    my ($version_a, $version_b) = @_;
    return lc($version_a->name) eq lc($version_b->name);
}

sub _create_version {
    my ($self, $name) = @_;
    Bugzilla::Version->create({ product => $self->_target, value => $name });
    # remove bugzilla's cached list of versions
    delete $self->_target->{versions};
}

1;
