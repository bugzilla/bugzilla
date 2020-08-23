use 5.006;
use strict;
no strict 'refs';
use warnings;

package Class::Tiny;
# ABSTRACT: Minimalist class construction

our $VERSION = '1.006';

use Carp ();

# load as .pm to hide from min version scanners
require( $] >= 5.010 ? "mro.pm" : "MRO/Compat.pm" ); ## no critic:

my %CLASS_ATTRIBUTES;

sub import {
    my $class = shift;
    my $pkg   = caller;
    $class->prepare_class($pkg);
    $class->create_attributes( $pkg, @_ ) if @_;
}

sub prepare_class {
    my ( $class, $pkg ) = @_;
    @{"${pkg}::ISA"} = "Class::Tiny::Object" unless @{"${pkg}::ISA"};
}

# adapted from Object::Tiny and Object::Tiny::RW
sub create_attributes {
    my ( $class, $pkg, @spec ) = @_;
    my %defaults = map { ref $_ eq 'HASH' ? %$_ : ( $_ => undef ) } @spec;
    my @attr = grep {
        defined and !ref and /^[^\W\d]\w*$/s
          or Carp::croak "Invalid accessor name '$_'"
    } keys %defaults;
    $CLASS_ATTRIBUTES{$pkg}{$_} = $defaults{$_} for @attr;
    $class->_gen_accessor( $pkg, $_ ) for grep { !*{"$pkg\::$_"}{CODE} } @attr;
    Carp::croak("Failed to generate attributes for $pkg: $@\n") if $@;
}

sub _gen_accessor {
    my ( $class, $pkg, $name ) = @_;
    my $outer_default = $CLASS_ATTRIBUTES{$pkg}{$name};

    my $sub =
      $class->__gen_sub_body( $name, defined($outer_default), ref($outer_default) );

    # default = outer_default avoids "won't stay shared" bug
    eval "package $pkg; my \$default=\$outer_default; $sub"; ## no critic
    Carp::croak("Failed to generate attributes for $pkg: $@\n") if $@;
}

# NOTE: overriding __gen_sub_body in a subclass of Class::Tiny is risky and
# could break if the internals of Class::Tiny need to change for any
# reason.  That said, I currently see no reason why this would be likely to
# change.
#
# The generated sub body should assume that a '$default' variable will be
# in scope (i.e. when the sub is evaluated) with any default value/coderef
sub __gen_sub_body {
    my ( $self, $name, $has_default, $default_type ) = @_;

    if ( $has_default && $default_type eq 'CODE' ) {
        return << "HERE";
sub $name {
    return (
          ( \@_ == 1 && exists \$_[0]{$name} )
        ? ( \$_[0]{$name} )
        : ( \$_[0]{$name} = ( \@_ == 2 ) ? \$_[1] : \$default->( \$_[0] ) )
    );
}
HERE
    }
    elsif ($has_default) {
        return << "HERE";
sub $name {
    return (
          ( \@_ == 1 && exists \$_[0]{$name} )
        ? ( \$_[0]{$name} )
        : ( \$_[0]{$name} = ( \@_ == 2 ) ? \$_[1] : \$default )
    );
}
HERE
    }
    else {
        return << "HERE";
sub $name {
    return \@_ == 1 ? \$_[0]{$name} : ( \$_[0]{$name} =  \$_[1] );
}
HERE
    }
}

sub get_all_attributes_for {
    my ( $class, $pkg ) = @_;
    my %attr =
      map { $_ => undef }
      map { keys %{ $CLASS_ATTRIBUTES{$_} || {} } } @{ mro::get_linear_isa($pkg) };
    return keys %attr;
}

sub get_all_attribute_defaults_for {
    my ( $class, $pkg ) = @_;
    my $defaults = {};
    for my $p ( reverse @{ mro::get_linear_isa($pkg) } ) {
        while ( my ( $k, $v ) = each %{ $CLASS_ATTRIBUTES{$p} || {} } ) {
            $defaults->{$k} = $v;
        }
    }
    return $defaults;
}

package Class::Tiny::Object;
# ABSTRACT: Base class for classes built with Class::Tiny

our $VERSION = '1.006';

my ( %HAS_BUILDARGS, %BUILD_CACHE, %DEMOLISH_CACHE, %ATTR_CACHE );

my $_PRECACHE = sub {
    no warnings 'once'; # needed to avoid downstream warnings
    my ($class) = @_;
    my $linear_isa =
      @{"$class\::ISA"} == 1 && ${"$class\::ISA"}[0] eq "Class::Tiny::Object"
      ? [$class]
      : mro::get_linear_isa($class);
    $DEMOLISH_CACHE{$class} = [
        map { ( *{$_}{CODE} ) ? ( *{$_}{CODE} ) : () }
        map { "$_\::DEMOLISH" } @$linear_isa
    ];
    $BUILD_CACHE{$class} = [
        map { ( *{$_}{CODE} ) ? ( *{$_}{CODE} ) : () }
        map { "$_\::BUILD" } reverse @$linear_isa
    ];
    $HAS_BUILDARGS{$class} = $class->can("BUILDARGS");
    return $ATTR_CACHE{$class} =
      { map { $_ => 1 } Class::Tiny->get_all_attributes_for($class) };
};

sub new {
    my $class = shift;
    my $valid_attrs = $ATTR_CACHE{$class} || $_PRECACHE->($class);

    # handle hash ref or key/value arguments
    my $args;
    if ( $HAS_BUILDARGS{$class} ) {
        $args = $class->BUILDARGS(@_);
    }
    else {
        if ( @_ == 1 && ref $_[0] ) {
            my %copy = eval { %{ $_[0] } }; # try shallow copy
            Carp::croak("Argument to $class->new() could not be dereferenced as a hash") if $@;
            $args = \%copy;
        }
        elsif ( @_ % 2 == 0 ) {
            $args = {@_};
        }
        else {
            Carp::croak("$class->new() got an odd number of elements");
        }
    }

    # create object and invoke BUILD (unless we were given __no_BUILD__)
    my $self =
      bless { map { $_ => $args->{$_} } grep { exists $valid_attrs->{$_} } keys %$args },
      $class;
    $self->BUILDALL($args) if !delete $args->{__no_BUILD__} && @{ $BUILD_CACHE{$class} };

    return $self;
}

sub BUILDALL { $_->(@_) for @{ $BUILD_CACHE{ ref $_[0] } } }

# Adapted from Moo and its dependencies
require Devel::GlobalDestruction unless defined ${^GLOBAL_PHASE};

sub DESTROY {
    my $self  = shift;
    my $class = ref $self;
    my $in_global_destruction =
      defined ${^GLOBAL_PHASE}
      ? ${^GLOBAL_PHASE} eq 'DESTRUCT'
      : Devel::GlobalDestruction::in_global_destruction();
    for my $demolisher ( @{ $DEMOLISH_CACHE{$class} } ) {
        my $e = do {
            local ( $?, $@ );
            eval { $demolisher->( $self, $in_global_destruction ) };
            $@;
        };
        no warnings 'misc'; # avoid (in cleanup) warnings
        die $e if $e;       # rethrow
    }
}

1;


# vim: ts=4 sts=4 sw=4 et:

__END__

=pod

=encoding UTF-8

=head1 NAME

Class::Tiny - Minimalist class construction

=head1 VERSION

version 1.006

=head1 SYNOPSIS

In F<Person.pm>:

  package Person;

  use Class::Tiny qw( name );

  1;

In F<Employee.pm>:

  package Employee;
  use parent 'Person';

  use Class::Tiny qw( ssn ), {
    timestamp => sub { time }   # attribute with default
  };

  1;

In F<example.pl>:

  use Employee;

  my $obj = Employee->new( name => "Larry", ssn => "111-22-3333" );

  # unknown attributes are ignored
  my $obj = Employee->new( name => "Larry", OS => "Linux" );
  # $obj->{OS} does not exist

=head1 DESCRIPTION

This module offers a minimalist class construction kit in around 120 lines of
code.  Here is a list of features:

=over 4

=item *

defines attributes via import arguments

=item *

generates read-write accessors

=item *

supports lazy attribute defaults

=item *

supports custom accessors

=item *

superclass provides a standard C<new> constructor

=item *

C<new> takes a hash reference or list of key/value pairs

=item *

C<new> supports providing C<BUILDARGS> to customize constructor options

=item *

C<new> calls C<BUILD> for each class from parent to child

=item *

superclass provides a C<DESTROY> method

=item *

C<DESTROY> calls C<DEMOLISH> for each class from child to parent

=back

Multiple-inheritance is possible, with superclass order determined via
L<mro::get_linear_isa|mro/Functions>.

It uses no non-core modules for any recent Perl. On Perls older than v5.10 it
requires L<MRO::Compat>. On Perls older than v5.14, it requires
L<Devel::GlobalDestruction>.

=head1 USAGE

=head2 Defining attributes

Define attributes as a list of import arguments:

    package Foo::Bar;

    use Class::Tiny qw(
        name
        id
        height
        weight
    );

For each attribute, a read-write accessor is created unless a subroutine of that
name already exists:

    $obj->name;               # getter
    $obj->name( "John Doe" ); # setter

Attribute names must be valid subroutine identifiers or an exception will
be thrown.

You can specify lazy defaults by defining attributes with a hash reference.
Keys define attribute names and values are constants or code references that
will be evaluated when the attribute is first accessed if no value has been
set.  The object is passed as an argument to a code reference.

    package Foo::WithDefaults;

    use Class::Tiny qw/name id/, {
        title     => 'Peon',
        skills    => sub { [] },
        hire_date => sub { $_[0]->_build_hire_date },
    };

When subclassing, if multiple accessors of the same name exist in different
classes, any default (or lack of default) is determined by standard
method resolution order.

To make your own custom accessors, just pre-declare the method name before
loading Class::Tiny:

    package Foo::Bar;

    use subs 'id';

    use Class::Tiny qw( name id );

    sub id { ... }

Even if you pre-declare a method name, you must include it in the attribute
list for Class::Tiny to register it as a valid attribute.

If you set a default for a custom accessor, your accessor will need to retrieve
the default and do something with it:

    package Foo::Bar;

    use subs 'id';

    use Class::Tiny qw( name ), { id => sub { int(rand(2*31)) } };

    sub id {
        my $self = shift;
        if (@_) {
            return $self->{id} = shift;
        }
        elsif ( exists $self->{id} ) {
            return $self->{id};
        }
        else {
            my $defaults =
                Class::Tiny->get_all_attribute_defaults_for( ref $self );
            return $self->{id} = $defaults->{id}->();
        }
    }

=head2 Class::Tiny::Object is your base class

If your class B<does not> already inherit from some class, then
Class::Tiny::Object will be added to your C<@ISA> to provide C<new> and
C<DESTROY>.

If your class B<does> inherit from something, then no additional inheritance is
set up.  If the parent subclasses Class::Tiny::Object, then all is well.  If
not, then you'll get accessors set up but no constructor or destructor. Don't
do that unless you really have a special need for it.

Define subclasses as normal.  It's best to define them with L<base>, L<parent>
or L<superclass> before defining attributes with Class::Tiny so the C<@ISA>
array is already populated at compile-time:

    package Foo::Bar::More;

    use parent 'Foo::Bar';

    use Class::Tiny qw( shoe_size );

=head2 Object construction

If your class inherits from Class::Tiny::Object (as it should if you followed
the advice above), it provides the C<new> constructor for you.

Objects can be created with attributes given as a hash reference or as a list
of key/value pairs:

    $obj = Foo::Bar->new( name => "David" );

    $obj = Foo::Bar->new( { name => "David" } );

If a reference is passed as a single argument, it must be able to be
dereferenced as a hash or an exception is thrown.

Unknown attributes in the constructor arguments will be ignored.  Prior to
version 1.000, unknown attributes were an error, but this made it harder for
people to cleanly subclass Class::Tiny classes so this feature was removed.

You can define a C<BUILDARGS> method to change how arguments to new are
handled.  It will receive the constructor arguments as they were provided and
must return a hash reference of key/value pairs (or else throw an
exception).

    sub BUILDARGS {
       my $class = shift;
       my $name = shift || "John Doe";
       return { name => $name };
     };

     Foo::Bar->new( "David" );
     Foo::Bar->new(); # "John Doe"

Unknown attributes returned from C<BUILDARGS> will be ignored.

=head2 BUILD

If your class or any superclass defines a C<BUILD> method, it will be called
by the constructor from the furthest parent class down to the child class after
the object has been created.

It is passed the constructor arguments as a hash reference.  The return value
is ignored.  Use C<BUILD> for validation, checking required attributes or
setting default values that depend on other attributes.

    sub BUILD {
        my ($self, $args) = @_;

        for my $req ( qw/name age/ ) {
            croak "$req attribute required" unless defined $self->$req;
        }

        croak "Age must be non-negative" if $self->age < 0;

        $self->msg( "Hello " . $self->name );
    }

The argument reference is a copy, so deleting elements won't affect data in the
original (but changes will be passed to other BUILD methods in C<@ISA>).

=head2 DEMOLISH

Class::Tiny provides a C<DESTROY> method.  If your class or any superclass
defines a C<DEMOLISH> method, they will be called from the child class to the
furthest parent class during object destruction.  It is provided a single
boolean argument indicating whether Perl is in global destruction.  Return
values and errors are ignored.

    sub DEMOLISH {
        my ($self, $global_destruct) = @_;
        $self->cleanup();
    }

=head2 Introspection and internals

You can retrieve an unsorted list of valid attributes known to Class::Tiny
for a class and its superclasses with the C<get_all_attributes_for> class
method.

    my @attrs = Class::Tiny->get_all_attributes_for("Employee");
    # returns qw/name ssn timestamp/

Likewise, a hash reference of all valid attributes and default values (or code
references) may be retrieved with the C<get_all_attribute_defaults_for> class
method.  Any attributes without a default will be C<undef>.

    my $def = Class::Tiny->get_all_attribute_defaults_for("Employee");
    # returns {
    #   name => undef,
    #   ssn => undef
    #   timestamp => $coderef
    # }

The C<import> method uses two class methods, C<prepare_class> and
C<create_attributes> to set up the C<@ISA> array and attributes.  Anyone
attempting to extend Class::Tiny itself should use these instead of mocking up
a call to C<import>.

When the first object is created, linearized C<@ISA>, the valid attribute list
and various subroutine references are cached for speed.  Ensure that all
inheritance and methods are in place before creating objects. (You don't want
to be changing that once you create objects anyway, right?)

=for Pod::Coverage new get_all_attributes_for get_all_attribute_defaults_for
prepare_class create_attributes

=head1 RATIONALE

=head2 Why this instead of Object::Tiny or Class::Accessor or something else?

I wanted something so simple that it could potentially be used by core Perl
modules I help maintain (or hope to write), most of which either use
L<Class::Struct> or roll-their-own OO framework each time.

L<Object::Tiny> and L<Object::Tiny::RW> were close to what I wanted, but
lacking some features I deemed necessary, and their maintainers have an even
more strict philosophy against feature creep than I have.

I also considered L<Class::Accessor>, which has been around a long time and is
heavily used, but it, too, lacked features I wanted and did things in ways I
considered poor design.

I looked for something else on CPAN, but after checking a dozen class creators
I realized I could implement exactly what I wanted faster than I could search
CPAN for something merely sufficient.

In general, compared to most things on CPAN (other than Object::Tiny),
Class::Tiny is smaller in implementation and simpler in API.

Specifically, here is how Class::Tiny ("C::T") compares to Object::Tiny
("O::T") and Class::Accessor ("C::A"):

 FEATURE                            C::T    O::T      C::A
 --------------------------------------------------------------
 attributes defined via import      yes     yes       no
 read/write accessors               yes     no        yes
 lazy attribute defaults            yes     no        no
 provides new                       yes     yes       yes
 provides DESTROY                   yes     no        no
 new takes either hashref or list   yes     no (list) no (hash)
 Moo(se)-like BUILD/DEMOLISH        yes     no        no
 Moo(se)-like BUILDARGS             yes     no        no
 no extraneous methods via @ISA     yes     yes       no

=head2 Why this instead of Moose or Moo?

L<Moose> and L<Moo> are both excellent OO frameworks.  Moose offers a powerful
meta-object protocol (MOP), but is slow to start up and has about 30 non-core
dependencies including XS modules.  Moo is faster to start up and has about 10
pure Perl dependencies but provides no true MOP, relying instead on its ability
to transparently upgrade Moo to Moose when Moose's full feature set is
required.

By contrast, Class::Tiny has no MOP and has B<zero> non-core dependencies for
Perls in the L<support window|perlpolicy>.  It has far less code, less
complexity and no learning curve. If you don't need or can't afford what Moo or
Moose offer, this is intended to be a reasonable fallback.

That said, Class::Tiny offers Moose-like conventions for things like C<BUILD>
and C<DEMOLISH> for some minimal interoperability and an easier upgrade path.

=for :stopwords cpan testmatrix url annocpan anno bugtracker rt cpants kwalitee diff irc mailto metadata placeholders metacpan

=head1 SUPPORT

=head2 Bugs / Feature Requests

Please report any bugs or feature requests through the issue tracker
at L<https://github.com/dagolden/Class-Tiny/issues>.
You will be notified automatically of any progress on your issue.

=head2 Source Code

This is open source software.  The code repository is available for
public review and contribution under the terms of the license.

L<https://github.com/dagolden/Class-Tiny>

  git clone https://github.com/dagolden/Class-Tiny.git

=head1 AUTHOR

David Golden <dagolden@cpan.org>

=head1 CONTRIBUTORS

=for stopwords Dagfinn Ilmari Mannsåker David Golden Gelu Lupas Karen Etheridge Olivier Mengué Toby Inkster

=over 4

=item *

Dagfinn Ilmari Mannsåker <ilmari@ilmari.org>

=item *

David Golden <xdg@xdg.me>

=item *

Gelu Lupas <gelu@devnull.ro>

=item *

Karen Etheridge <ether@cpan.org>

=item *

Olivier Mengué <dolmen@cpan.org>

=item *

Toby Inkster <tobyink@cpan.org>

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2013 by David Golden.

This is free software, licensed under:

  The Apache License, Version 2.0, January 2004

=cut
