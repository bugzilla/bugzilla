package Menlo::Dependency;
use strict;
use CPAN::Meta::Requirements;
use Class::Tiny qw( module version type original_version dist mirror url );

sub BUILDARGS {
    my($class, $module, $version, $type) = @_;
    return {
        module => $module,
        version => $version,
        type => $type || 'requires',
    };
}

sub from_prereqs {
    my($class, $prereqs, $phases, $types) = @_;

    my @deps;
    for my $type (@$types) {
        push @deps, $class->from_versions(
            $prereqs->merged_requirements($phases, [$type])->as_string_hash,
            $type,
        );
    }

    return @deps;
}

sub from_versions {
    my($class, $versions, $type) = @_;

    my @deps;
    while (my($module, $version) = each %$versions) {
        push @deps, $class->new($module, $version, $type)
    }

    @deps;
}

sub merge_with {
    my($self, $requirements) = @_;

    # save the original requirement
    $self->original_version($self->version);

    # should it clone? not cloning means we upgrade root $requirements on our way
    eval {
        $requirements->add_string_requirement($self->module, $self->version);
    };
    if ($@ =~ /illegal requirements/) {
        # Just give a warning then replace with the root requirements
        # so that later CPAN::Meta::Check can give a valid error
        warn sprintf("Can't merge requirements for %s: '%s' and '%s'",
                    $self->module, $self->version,
                    $requirements->requirements_for_module($self->module));
    }

    $self->version( $requirements->requirements_for_module($self->module) );
}

sub requires_version {
    my $self = shift;

    # original_version may be 0
    if (defined $self->original_version) {
        return $self->original_version;
    }

    $self->version;
}

sub is_requirement {
    $_[0]->type eq 'requires';
}

1;
