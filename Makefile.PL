#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# This file has detailed POD docs, do "perldoc checksetup.pl" to see them.

######################################################################
# Initialization
######################################################################

use 5.10.1;
use strict;
use warnings;
use lib qw(. lib local/lib/perl5);

use ExtUtils::MakeMaker 6.55;
use Bugzilla::Constants qw(BUGZILLA_VERSION);
use File::Basename;
use File::Spec;

# META.json and META.yml exist only for the benefit of older
# installs where cpanm can't get the optional features out of Makefile.PL
# Unfortunately having META.json and META.yml commited to the repo is weird
# and MakeMaker always prefers their content to the internal data (unless CPAN::META
# is not installed). 
# Since we (Bugzilla) require this cludge, we hide the files from MakeMaker.
BEGIN {
    warn "Hiding META.{json,yml} from MakeMaker...\n";
    rename('META.json', 'META.json.hide') || unlink("META.json");
    rename('META.yml', 'META.yml.hide') || unlink("META.yml");
}

END {
    warn "Unhiding META.{json,yml}...\n";
    rename('META.json.hide', 'META.json');
    rename('META.yml.hide', 'META.yml');
}



# PREREQ_PM
my %requires = (
    'CGI'                 => '3.51',
    'DBI'                 => '1.614',
    'Date::Format'        => '2.23',
    'DateTime'            => '0.75',
    'DateTime::TimeZone'  => '1.64',
    'Digest::SHA'         => 0,
    'Email::MIME'         => '1.904',
    'Email::Sender'       => '1.300011',
    'File::Slurp'         => '9999.13',
    'JSON::XS'            => '2.01',
    'List::MoreUtils'     => '0.32',
    'Math::Random::ISAAC' => '1.0.1',
    'Template'            => '2.24',
    'URI'                 => '1.55',
);

my %optional_features = (
    features => {
        prereqs => { runtime => { requires => { 'CPAN::Meta::Check' => 0, 'Module::Runtime' => 0, 'CPAN::Meta' => 0, }, }, },
        description => "Base support for Features"
    },
    smtp_auth => {
        prereqs     => { runtime => { requires => { 'Authen::SASL' => 0 } } },
        description => 'SMTP Authentication'
    },
    detect_charset => {
        prereqs => { runtime => { requires => { 'Encode::Detect' => 0, Encode => '2.21' } } },
        description => 'Automatic charset detection for text attachments'
    },
    new_charts => {
        description => 'New Charts',
        prereqs     => { runtime => { requires => { 'Chart::Lines' => 'v2.4.10', GD => '1.20' } } }
    },
    html_desc => {
        description => 'More HTML in Product/Group Descriptions',
        prereqs     => { runtime => { requires => { 'HTML::Parser' => '3.67', 'HTML::Scrubber' => 0 } } }
    },
    markdown => {
        description => 'Markdown syntax support for comments',
        prereqs     => { runtime => { requires => { 'Text::MultiMarkdown' => '1.000034' } } }
    },
    pg => {
        prereqs     => { runtime => { requires => { 'DBD::Pg' => 'v2.19.3' } } },
        description => 'Postgres database support'
    },
    memcached => {
        description => 'Memcached Support',
        prereqs     => { runtime => { requires => { 'Cache::Memcached::Fast' => '0.17' } } }
    },
    auth_delegation => {
        description => 'Auth Delegation',
        prereqs     => { runtime => { requires => { 'LWP::UserAgent' => 0 } } }
    },
    updates => {
        description => 'Automatic Update Notifications',
        prereqs     => { runtime => { requires => { 'LWP::UserAgent' => 0, 'XML::Twig' => 0 } } }
    },
    auth_radius => {
        description => 'RADIUS Authentication',
        prereqs     => { runtime => { requires => { 'Authen::Radius' => 0 } } }
    },
    documentation => {
        prereqs => { runtime => { requires => { 'File::Which' => 0, 'File::Copy::Recursive' => 0 } } },
        description => 'Documentation',
    },
    xmlrpc => {
        description => 'XML-RPC Interfaze',
        prereqs     => {
            runtime =>
                { requires => { 'XMLRPC::Lite' => '0.712', 'SOAP::Lite' => '0.712', 'Test::Taint' => '1.06' } }
        }
    },
    auth_ldap => {
        prereqs     => { runtime => { requires => { 'Net::LDAP' => 0 } } },
        description => 'LDAP Authentication'
    },
    old_charts => {
        prereqs     => { runtime => { requires => { GD => '1.20', 'Chart::Lines' => 'v2.4.10' } } },
        description => 'Old Charts'
    },
    moving => {
        prereqs => { runtime => { requires => { 'MIME::Parser' => '5.406', 'XML::Twig' => 0 } } },
        description => 'Move Bugs Between Installations'
    },
    oracle => {
        description => 'Oracle database support',
        prereqs     => { runtime => { requires => { 'DBD::Oracle' => '1.19' } } }
    },
    typesniffer => {
        prereqs => { runtime => { requires => { 'IO::Scalar' => 0, 'File::MimeInfo::Magic' => 0 } } },
        description => 'Sniff MIME type of attachments'
    },
    sqlite => {
        prereqs     => { runtime => { requires => { 'DBD::SQLite' => '1.29' } } },
        description => 'SQLite database support'
    },
    smtp_ssl => {
        prereqs     => { runtime => { requires => { 'Net::SMTP::SSL' => '1.01' } } },
        description => 'SSL Support for SMTP'
    },
    mysql => {
        description => 'MySQL database support',
        prereqs     => { runtime => { requires => { 'DBD::mysql' => '4.001' } } }
    },
    jsonrpc => {
        description => 'JSON-RPC Interface',
        prereqs     => { runtime => { requires => { 'JSON::RPC' => 0, 'Test::Taint' => '1.06' } } }
    },
    graphical_reports => {
        description => 'Graphical Reports',
        prereqs     => {
            runtime => {
                requires => {
                    'GD::Text'                    => 0,
                    'Template::Plugin::GD::Image' => 0,
                    'GD::Graph'                   => 0,
                    GD                            => '1.20',
                }
            }
        }
    },
    mod_perl => {
        description => 'mod_perl support under Apache',
        prereqs     => { runtime => { requires => { 'mod_perl2' => '0' } } }
    },
    inbound_email => {
        prereqs     => { runtime => { requires => { 'Email::Reply' => 0, 'HTML::FormatText::WithLinks' => '0.13' } } },
        description => 'Inbound Email'
    },
    patch_viewer => {
        description => 'Patch Viewer',
        prereqs     => { runtime => { requires => { PatchReader => 'v0.9.6' } } }
    },
    rest => {
        description => 'REST Interface',
        prereqs     => {
            runtime => {
                requires => {
                    'Test::Taint'     => '1.06',
                    'HTTP::Request'   => 0,
                    'HTTP::Response'  => 0,
                    Moo               => 2,
                    'Module::Runtime' => 0
                }
            }
        }
    },
    jobqueue => {
        description => 'Mail Queueing',
        prereqs     => { runtime => { requires => { TheSchwartz => '1.1', 'Daemon::Generic' => 0 } } }
    },
    psgi => {
        description => 'Plack/PSGI support',
        prereqs     => {
            runtime => { requires => { Plack => '1.0031', 'CGI::Compile' => 0, 'CGI::Emulate::PSGI' => 0 } }
        }
    },
);

for my $file (glob("extensions/*/Config.pm")) {
    my $dir = dirname($file);
    my $name = basename($dir);

    next if -f File::Spec->catfile($dir, "disabled");
    require $file;
    my $class = "Bugzilla::Extension::$name";
    if ($class->can("REQUIRED_MODULES")) {
        foreach my $required_module (@{ $class->REQUIRED_MODULES() }) {
            $requires{$required_module->{module}} = $required_module->{version};
        }
    }

    if ($class->can('OPTIONAL_MODULES')) {
        my $default_feature = 'extension_' . lc($name) . '_optional';
        foreach my $mod (@{ $class->OPTIONAL_MODULES }) {
            my @features    = $mod->{feature} ? @{$mod->{feature}} : ($default_feature);
            foreach my $feature (@features) {
                $optional_features{$feature}{prereqs}{runtime}{requires}{$mod->{module}} = $mod->{version} // 0;
            }
        }
    }
}

WriteMakefile(
    NAME               => 'Bugzilla',
    AUTHOR             => q{Bugzilla Developers <developers@bugzilla.org>},
    VERSION            => BUGZILLA_VERSION,
    ABSTRACT           => 'Bugzilla Bug Tracking System',
    LICENSE            => 'Mozilla_2_0',
    MIN_PERL_VERSION   => '5.10.1',
    CONFIGURE_REQUIRES => { 'ExtUtils::MakeMaker' => '6.55' },
    PREREQ_PM          => \%requires,
    TEST_REQUIRES => { 'Test::More' => 0, 'Pod::Coverage' => 0, 'Test::Perl::Critic' => 0, },
    META_MERGE    => {
        "meta-spec"       => { url => "http://search.cpan.org/perldoc?CPAN::Meta::Spec", version => "2" },
        dynamic_config    => 1,
        optional_features => \%optional_features,
    },
);

sub MY::postamble {
    return <<MAKE;
GEN_CPANFILE_ARGS = -A -U mod_perl -U oracle
cpanfile: MYMETA.json
\t\$(PERLRUN) gen-cpanfile.pl \$(GEN_CPANFILE_ARGS)
MAKE
}
