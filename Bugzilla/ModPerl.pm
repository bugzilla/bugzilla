# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::ModPerl;

use 5.10.1;
use strict;
use warnings;

use File::Find ();
use Cwd ();
use Carp ();

# We don't need (or want) to use Bugzilla's template subclass.
# it is easier to reason with the code without all the extra things Bugzilla::Template adds
# (and there might be side-effects, since this code is loaded very early in the httpd startup)
use Template ();

sub apache_config {
    my ($class, $cgi_path) = @_;

    Carp::croak "\$cgi_path is required" unless $cgi_path;

    my %htaccess;
    $cgi_path = Cwd::realpath($cgi_path);
    my $wanted = sub {
        package File::Find;
        our ($name, $dir);

        if ($name =~ m#/\.htaccess$#) {
            open my $fh, '<', $name or die "cannot open $name $!";
            my $contents = do {
                local $/ = undef;
                <$fh>;
            };
            close $fh;
            $htaccess{$dir} = { file => $name, contents => $contents, dir => $dir };
        }
    };

    File::Find::find( { wanted => $wanted, no_chdir => 1 }, $cgi_path );
    my $template = Template->new;
    my $conf;
    my %vars = (
        root_htaccess  => delete $htaccess{$cgi_path},
        htaccess_files => [ map { $htaccess{$_} } sort { length $a <=> length $b } keys %htaccess ],
        cgi_path       => $cgi_path,
    );
    $template->process(\*DATA, \%vars, \$conf);

    return $conf;
}

1;

__DATA__
# Make sure each httpd child receives a different random seed (bug 476622).
# Bugzilla::RNG has one srand that needs to be called for
# every process, and Perl has another. (Various Perl modules still use
# the built-in rand(), even though we never use it in Bugzilla itself,
# so we need to srand() both of them.)
PerlChildInitHandler "sub { Bugzilla::RNG::srand(); srand(); }"

<Directory "[% cgi_path %]">
    AddHandler perl-script .cgi
    # No need to PerlModule these because they're already defined in mod_perl.pl
    PerlResponseHandler Bugzilla::ModPerl::ResponseHandler
    PerlCleanupHandler Bugzilla::ModPerl::CleanupHandler Apache2::SizeLimit
    PerlOptions +ParseHeaders
    Options +ExecCGI +FollowSymLinks
    DirectoryIndex index.cgi index.html
    AllowOverride none
    # from [% root_htaccess.file %]
    [% root_htaccess.contents FILTER indent %]
</Directory>

# directory rules for all the other places we have .htaccess files
[% FOREACH htaccess IN htaccess_files %]
# from [% htaccess.file %]
<Directory "[% htaccess.dir %]">
    [% htaccess.contents FILTER indent %]
</Directory>
[% END %]
