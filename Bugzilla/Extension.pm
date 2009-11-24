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
# The Original Code is the Bugzilla Bug Tracking System.
#
# The Initial Developer of the Original Code is Everything Solved, Inc.
# Portions created by the Initial Developers are Copyright (C) 2009 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Max Kanat-Alexander <mkanat@bugzilla.org>

package Bugzilla::Extension;
use strict;

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Install::Util qw(extension_code_files);

use File::Basename;
use File::Spec;

####################
# Subclass Methods #
####################

sub new {
    my ($class, $params) = @_;
    $params ||= {};
    bless $params, $class;
    return $params;
}

#######################################
# Class (Bugzilla::Extension) Methods #
#######################################

sub load {
    my ($class, $extension_file, $config_file) = @_;
    my $package;

    # This is needed during checksetup.pl, because Extension packages can 
    # only be loaded once (they return "1" the second time they're loaded,
    # instead of their name). During checksetup.pl, extensions are loaded
    # once by Bugzilla::Install::Requirements, and then later again via
    # Bugzilla->extensions (because of hooks).
    my $map = Bugzilla->request_cache->{extension_requirement_package_map};

    if ($config_file) {
        if ($map and defined $map->{$config_file}) {
            $package = $map->{$config_file};
        }
        else {
            my $name = require $config_file;
            if ($name =~ /^\d+$/) {
                ThrowCodeError('extension_must_return_name',
                               { extension => $config_file, 
                                 returned  => $name });
            }
            $package = "${class}::$name";
        }

        # This allows people to override modify_inc in Config.pm, if they
        # want to.
        if ($package->can('modify_inc')) {
            $package->modify_inc($config_file);
        }
        else {
            modify_inc($package, $config_file);
        }
    }

    if ($map and defined $map->{$extension_file}) {
        $package = $map->{$extension_file};
        $package->modify_inc($extension_file) if !$config_file;
    }
    else {
        my $name = require $extension_file;
        if ($name =~ /^\d+$/) {
            ThrowCodeError('extension_must_return_name', 
                           { extension => $extension_file, returned => $name });
        }
        $package = "${class}::$name";
        $package->modify_inc($extension_file) if !$config_file;
    }

    if (!eval { $package->NAME }) {
        ThrowCodeError('extension_no_name', 
                       { filename => $extension_file, package => $package });
    }

    if (!$package->isa($class)) {
        ThrowCodeError('extension_must_be_subclass',
                       { filename => $extension_file,
                         package  => $package,
                         class    => $class });
    }

    return $package;
}

sub load_all {
    my $class = shift;
    my $file_sets = extension_code_files();
    my @packages;
    foreach my $file_set (@$file_sets) {
        my $package = $class->load(@$file_set);
        push(@packages, $package);
    }

    return \@packages;
}

# Modifies @INC so that extensions can use modules like
# "use Bugzilla::Extension::Foo::Bar", when Bar.pm is in the lib/
# directory of the extension.
sub modify_inc {
    my ($class, $file) = @_;
    my $lib_dir = File::Spec->catdir(dirname($file), 'lib');
    # Allow Config.pm to override my_inc, if it wants to.
    if ($class->can('my_inc')) {
        unshift(@INC, sub { $class->my_inc($lib_dir, @_); });
    }
    else {
        unshift(@INC, sub { my_inc($class, $lib_dir, @_); });
    }
}

# This is what gets put into @INC by modify_inc.
sub my_inc {
    my ($class, $lib_dir, undef, $file) = @_;
    my @class_parts = split('::', $class);
    my ($vol, $dir, $file_name) = File::Spec->splitpath($file);
    my @dir_parts = File::Spec->splitdir($dir);
    # Validate that this is a sub-package of Bugzilla::Extension::Foo ($class).
    for (my $i = 0; $i < scalar(@class_parts); $i++) {
        return if !@dir_parts;
        if (File::Spec->case_tolerant) {
            return if lc($class_parts[$i]) ne lc($dir_parts[0]);
        }
        else {
            return if $class_parts[$i] ne $dir_parts[0];
        }
        shift(@dir_parts);
    }
    # For Bugzilla::Extension::Foo::Bar, this would look something like
    # extensions/Example/lib/Bar.pm
    my $resolved_path = File::Spec->catfile($lib_dir, @dir_parts, $file_name);
    open(my $fh, '<', $resolved_path);
    return $fh;
}

####################
# Instance Methods #
####################

use constant enabled => 1;

1;

__END__

=head1 NAME

Bugzilla::Extension - Base class for Bugzilla Extensions.

=head1 SYNOPSIS

The following would be in F<extensions/Foo/Extension.pm> or 
F<extensions/Foo.pm>:

 package Bugzilla::Extension::Foo
 use strict;
 use base qw(Bugzilla::Extension);

 our $VERSION = '0.02';
 use constant NAME => 'Foo';

 sub some_hook_name { ... }

 __PACKAGE__->NAME;

=head1 DESCRIPTION

This is the base class for all Bugzilla extensions.

=head1 WRITING EXTENSIONS

The L</SYNOPSIS> above gives a pretty good overview of what's basically
required to write an extension. This section gives more information
on exactly how extensions work and how you write them.

=head2 Example Extension

There is a sample extension in F<extensions/Example/> that demonstrates
most of the things described in this document, so if you find the
documentation confusing, try just reading the code instead.

=head2 Where Extension Code Goes

Extension code lives under the F<extensions/> directory in Bugzilla.

There are two ways to write extensions:

=over

=item 1

If your extension will have only code and no templates or other files,
you can create a simple C<.pm> file in the F<extensions/> directory. 

For example, if you wanted to create an extension called "Foo" using this
method, you would put your code into a file called F<extensions/Foo.pm>.

=item 2

If you plan for your extension to have templates and other files, you
can create a whole directory for your extension, and the main extension
code would go into a file called F<Extension.pm> in that directory.

For example, if you wanted to create an extension called "Foo" using this
method, you would put your code into a file called
F<extensions/Foo/Extension.pm>.

=back

=head2 The Extension C<NAME>.

The "name" of an extension shows up in several places:

=over

=item 1

The name of the package:

C<package Bugzilla::Extension::Foo;>

=item 2

In a C<NAME> constant that B<must> be defined for every extension:

C<< use constant NAME => 'Foo'; >>

=item 3

At the very end of the file:

C<< __PACKAGE__->NAME; >>

You'll notice that though most Perl packages end with C<1;>, Bugzilla
Extensions must B<always> end with C<< __PACKAGE__->NAME; >>.

=back

The name must be identical in all of those locations.

=head2 Hooks

In L<Bugzilla::Hook>, there is a L<list of hooks|Bugzilla::Hook/HOOKS>.
These are the various areas of Bugzilla that an extension can "hook" into,
which allow your extension to perform code during that point in Bugzilla's
execution.

If your extension wants to implement a hook, all you have to do is
write a subroutine in your hook package that has the same name as
the hook. The subroutine will be called as a method on your extension,
and it will get the arguments specified in the hook's documentation as
named parameters in a hashref.

For example, here's an implementation of a hook named C<foo_start>
that gets an argument named C<bar>:

 sub foo_start {
     my ($self, $params) = @_;
     my $bar = $params->{bar};
     print "I got $bar!\n";
 }

And that would go into your extension's code file--the file that was
described in the L</Where Extension Code Goes> section above.

During your subroutine, you may want to know what values were passed
as CGI arguments  to the current script, or what arguments were passed to
the current WebService method. You can get that data via 
<Bugzilla/input_params>.

=head2 If Your Extension Requires Certain Perl Modules

If there are certain Perl modules that your extension requires in order
to run, there is a way you can tell Bugzilla this, and then L<checksetup>
will make sure that those modules are installed, when you run L<checksetup>.

To do this, you need to specify a constant called C<REQUIRED_MODULES>
in your extension. This constant has the same format as
L<Bugzilla::Install::Requirements/REQUIRED_MODULES>.

If there are optional modules that add additional functionality to your
application, you can specify them in a constant called OPTIONAL_MODULES,
which has the same format as 
L<Bugzilla::Install::Requirements/OPTIONAL_MODULES>.

=head3 If Your Extension Needs Certain Modules In Order To Compile

If your extension needs a particular Perl module in order to
I<compile>, then you have a "chicken and egg" problem--in order to
read C<REQUIRED_MODULES>, we have to compile your extension. In order
to compile your extension, we need to already have the modules in
C<REQUIRED_MODULES>!

To get around this problem, Bugzilla allows you to have an additional
file, besides F<Extension.pm>, called F<Config.pm>, that contains
just C<REQUIRED_MODULES>. If you have a F<Config.pm>, it must also
contain the C<NAME> constant, instead of your main F<Extension.pm>
containing the C<NAME> constant.

The contents of the file would look something like this for an extension
named C<Foo>:

  package Bugzilla::Extension::Foo;
  use strict;
  use constant NAME => 'Foo';
  use constant REQUIRED_MODULES => [
    {
      package => 'Some-Package',
      module  => 'Some::Module',
      version => 0,
    }
  ];
  __PACKAGE__->NAME;

Note that it is I<not> a subclass of C<Bugzilla::Extension>, because
at the time that module requirements are being checked in L<checksetup>,
C<Bugzilla::Extension> cannot be loaded. Also, just like F<Extension.pm>,
it ends with C<< __PACKAGE__->NAME; >>. Note also that it has the exact
same C<package> name as F<Extension.pm>.

This file may not use any Perl modules other than L<Bugzilla::Constants>,
L<Bugzilla::Install::Util>, L<Bugzilla::Install::Requirements>, and 
modules that ship with Perl itself.

If you want to define both C<REQUIRED_MODULES> and C<OPTIONAL_MODULES>,
they must both be in F<Config.pm> or both in F<Extension.pm>.

Every time your extension is loaded by Bugzilla, F<Config.pm> will be
read and then F<Extension.pm> will be read, so your methods in F<Extension.pm>
will have access to everything in F<Config.pm>. Don't define anything
with an identical name in both files, or Perl may throw a warning that
you are redefining things.

This method of setting C<REQUIRED_MODULES> is of course not available if 
your extension is a single file named C<Foo.pm>.

If any of this is confusing, just look at the code of the Example extension.
It uses this method to specify requirements.

=head2 Libraries

Extensions often want to have their own Perl modules. Your extension
can load any Perl module in its F<lib/> directory. (So, if your extension is 
F<extensions/Foo/>, then your Perl modules go into F<extensions/Foo/lib/>.)

However, the C<package> name of your libraries will not work quite
like normal Perl modules do. F<extensions/Foo/lib/Bar.pm> is
loaded as C<Bugzilla::Extension::Foo::Bar>. Or, to say it another way,
C<use Bugzilla::Extension::Foo::Bar;> loads F<extensions/Foo/lib/Bar.pm>,
which should have C<package Bugzilla::Extension::Foo::Bar;> as its package
name.

This allows any place in Bugzilla to load your modules, which is important
for some hooks. It even allows other extensions to load your modules. It
even allows you to install your modules into the global Perl install
as F<Bugzilla/Extension/Foo/Bar.pm>, if you'd like, which helps allow CPAN
distribution of Bugzilla extensions.

B<Note:> If you want to C<use> or C<require> a module that's in 
F<extensions/Foo/lib/> at the top level of your F<Extension.pm>,
you must have a F<Config.pm> (see above) with at least the C<NAME>
constant defined in it.

=head2 Disabling Your Extension

If you want your extension to be totally ignored by Bugzilla (it will
not be compiled or seen to exist at all), then create a file called
C<disabled> in your extension's directory. (If your extension is just
a file, like F<extensions/Foo.pm>, you cannot use this method to disable
your extension, and will just have to remove it from the directory if you
want to totally disable it.) Note that if you are running under mod_perl,
you may have to restart your web server for this to take effect.

If you want your extension to be compiled and have L<checksetup> check
for its module pre-requisites, but you don't want the module to be used
by Bugzilla, then you should make your extension's L</enabled> method
return C<0> or some false value.

=head1 ADDITIONAL CONSTANTS

In addition to C<NAME>, there are some other constants you might
want to define:

=head2 C<$VERSION>

This should be a string that describes what version of your extension
this is. Something like C<1.0>, C<1.3.4> or a similar string.

There are no particular restrictions on the format of version numbers,
but you should probably keep them to just numbers and periods, in the
interest of other software that parses version numbers.

By default, this will be C<undef> if you don't define it.

=head1 SUBCLASS METHODS

In addition to hooks, there are a few methods that your extension can
define to modify its behavior, if you want:

=head2 C<enabled>

This should return C<1> if this extension's hook code should be run
by Bugzilla, and C<0> otherwise.

=head2 C<new>

Once every request, this method is called on your extension in order
to create an "instance" of it. (Extensions are treated like objects--they
are instantiated once per request in Bugzilla, and then methods are
called on the object.)

=head1 BUGZILLA::EXTENSION CLASS METHODS

These are used internally by Bugzilla to load and set up extensions.
If you are an extension author, you don't need to care about these.

=head2 C<load>

Takes two arguments, the path to F<Extension.pm> and the path to F<Config.pm>,
for an extension. Loads the extension's code packages into memory using
C<require>, does some sanity-checking on the extension, and returns the
package name of the loaded extension.

=head2 C<load_all>

Calls L</load> for every enabled extension installed into Bugzilla,
and returns an arrayref of all the package names that were loaded.
