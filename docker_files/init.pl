#!/usr/bin/perl
use strict;
use warnings;
use lib qw(/app /opt/bmo/local/lib/perl5);
use Getopt::Long qw(:config gnu_getopt);
use Data::Dumper;
use Bugzilla::Install::Localconfig ();
use Bugzilla::Install::Util qw(install_string);

my %localconfig = (webservergroup => 'app');

my %override = (
    'inbound_proxies'     => 1,
    'shadowdb'            => 1,
    'shadowdbhost'        => 1,
    'shadowdbport'        => 1,
    'shadowdbsock'        => 1
);

# clean env.
foreach my $key (keys %ENV) {
    if ($key =~ /^BMO_(.+)$/) {
        my $name = $1;
        if ($override{$name}) {
            $localconfig{param_override}{$name} = delete $ENV{$key};
        }
        else {
            $localconfig{$name} = delete $ENV{$key};
        }
    }
}

write_localconfig(\%localconfig);
sleep(10);
system('perl', 'checksetup.pl', '--no-templates', '--no-permissions');

my $cmd = shift @ARGV or die "usage: init.pl CMD";
my $method = "run_$cmd";
__PACKAGE__->$method();

sub run_httpd {
    exec("/usr/sbin/httpd", "-DFOREGROUND", "-f", "/opt/bmo/httpd/httpd.conf");
}

sub run_shell {
    exec("/bin/bash", "-l");
}

sub write_localconfig {
    my ($localconfig) = @_;
    no warnings 'once';

    foreach my $var (Bugzilla::Install::Localconfig::LOCALCONFIG_VARS) {
        my $name = $var->{name};
        my $value = $localconfig->{$name};
        if (!defined $value) {
            $var->{default} = &{$var->{default}} if ref($var->{default}) eq 'CODE';
            $localconfig->{$name} = $var->{default};
        }
    }

    my $filename = "/app/localconfig";

    # Ensure output is sorted and deterministic
    local $Data::Dumper::Sortkeys = 1;

    # Re-write localconfig
    open my $fh, ">:utf8", $filename or die "$filename: $!";
    foreach my $var (Bugzilla::Install::Localconfig::LOCALCONFIG_VARS) {
        my $name = $var->{name};
        my $desc = install_string("localconfig_$name", { root => Bugzilla::Install::Localconfig::ROOT_USER });
        chomp($desc);
        # Make the description into a comment.
        $desc =~ s/^/# /mg;
        print $fh $desc, "\n",
                  Data::Dumper->Dump([$localconfig->{$name}],
                                     ["*$name"]), "\n";
   }
   close $fh;
}
