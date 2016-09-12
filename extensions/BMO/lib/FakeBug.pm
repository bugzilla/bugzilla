package Bugzilla::Extension::BMO::FakeBug;

# hack to allow the bug entry templates to use check_can_change_field to see if
# various field values should be available to the current user

use strict;

use Bugzilla::Bug;

our $AUTOLOAD;

sub new {
    my $class = shift;
    my $self = shift;
    bless $self, $class;
    return $self;
}

sub AUTOLOAD {
    my $self = shift;
    my $name = $AUTOLOAD;
    $name =~ s/.*://;
    return exists $self->{$name} ? $self->{$name} : undef;
}

sub check_can_change_field {
    my $self = shift;
    return Bugzilla::Bug::check_can_change_field($self, @_)
}

sub _changes_everconfirmed {
    my $self = shift;
    return Bugzilla::Bug::_changes_everconfirmed($self, @_)
}

sub everconfirmed {
    my $self = shift;
    return ($self->{'status'} == 'UNCONFIRMED') ? 0 : 1;
}

1;

