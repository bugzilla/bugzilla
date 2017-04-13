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

use File::Basename;
use File::Spec;
BEGIN {
    require lib;
    my $dir = File::Spec->rel2abs(dirname(__FILE__));
    lib->import($dir, File::Spec->catdir($dir, "lib"), File::Spec->catdir($dir, qw(local lib perl5)));
}

use ExtUtils::MakeMaker 6.55;
use constant BUGZILLA_VERSION => $ENV{BUGZILLA_VERSION} // 42;
use File::Basename;
use File::Spec;

BEGIN {
    if ($ENV{BZ_SILENT_MAKEFILE}) {
        open STDOUT, '>>', File::Spec->devnull;
        open STDERR, '>>', File::Spec->devnull;
    }
}

# PREREQ_PM
my %requires = (
    'CGI'                      => '<= 3.63',
    'CPAN::Meta::Prereqs'      => '2.132830',
    'CPAN::Meta::Requirements' => '2.121',
    'DBI'                      => '1.614',
    'Date::Format'             => '2.23',
    'DateTime'                 => '0.75',
    'DateTime::TimeZone'       => '2.11',
    'Digest::SHA'              => 0,
    'Email::MIME'              => '1.904',
    'Email::Send'              => '1.911',
    'File::Slurp'              => '9999.13',
    'JSON::XS'                 => '2.01',
    'List::MoreUtils'          => $^V > v5.10.1 ? '0.418' : '0.22',
    'Math::Random::ISAAC'      => '1.0.1',
    'Module::Metadata'         => '1.000033',
    'Module::Runtime'          => 0,
    'Moo'                      => 2,
    'Parse::CPAN::Meta'        => '1.44',
    'Template'                 => '2.24',
    'Text::CSV_XS'             => 0,
    'Throwable'                => 0,
    'URI'                      => '1.55',
    'version'                  => '0.87',
    'Taint::Util'              => 0,
);
my %build_requires = (
    'ExtUtils::MakeMaker' => '6.57_07',
);
my %test_requires = (
    'Test::More'         => 0,
    'Pod::Coverage'      => 0,
    'Test::WWW::Selenium' => 0.
);
my %recommends = ( Safe => '2.30' );

# Windows requires some additional modules.
if ( $^O eq 'MSWin32' ) {
    $requires{'Win32'}                            = '0.35';
    $requires{'Win32::API'}                       = '0.55';
    $requires{'DateTime::TimeZone::Local::Win32'} = '1.64';
}

my %optional_features = (
    smtp_auth => {
        prereqs => { runtime => { requires => { 'Authen::SASL' => 0 } } },
        description => 'SMTP Authentication'
    },
    detect_charset => {
        prereqs => {
            runtime =>
                { requires => { 'Encode::Detect' => 0, Encode => '2.21' } }
        },
        description => 'Automatic charset detection for text attachments'
    },
    new_charts => {
        description => 'New Charts',
        prereqs     => {
            runtime =>
                { requires => { 'Chart::Lines' => 'v2.4.10', GD => '1.20' } }
        }
    },
    html_desc => {
        description => 'More HTML in Product/Group Descriptions',
        prereqs     => {
            runtime => {
                requires =>
                    { 'HTML::Parser' => '3.67', 'HTML::Scrubber' => 0 }
            }
        }
    },
    markdown => {
        description => 'Markdown syntax support for comments',
        prereqs     => {
            runtime => { requires => { 'Text::MultiMarkdown' => '1.000034' } }
        }
    },
    pg => {
        prereqs => { runtime => { requires => { 'DBD::Pg' => 'v2.19.3' } } },
        description => 'Postgres database support'
    },
    memcached => {
        description => 'Memcached Support',
        prereqs     => {
            runtime => { requires => { 'Cache::Memcached::Fast' => '0.17' } }
        }
    },
    auth_delegation => {
        description => 'Auth Delegation',
        prereqs => { runtime => { requires => { 'LWP::UserAgent' => 0 } } }
    },
    updates => {
        description => 'Automatic Update Notifications',
        prereqs     => {
            runtime =>
                { requires => { 'LWP::UserAgent' => 0, 'XML::Twig' => 0 } }
        }
    },
    auth_radius => {
        description => 'RADIUS Authentication',
        prereqs => { runtime => { requires => { 'Authen::Radius' => 0 } } }
    },
    documentation => {
        prereqs => {
            runtime => {
                requires =>
                    { 'File::Which' => 0, 'File::Copy::Recursive' => 0 }
            }
        },
        description => 'Documentation',
    },
    xmlrpc => {
        description => 'XML-RPC Interface',
        prereqs     => {
            runtime => {
                requires => {
                    'XMLRPC::Lite' => '0.712',
                    'SOAP::Lite'   => '0.712',
                    'Test::Taint'  => '1.06'
                }
            }
        }
    },
    auth_ldap => {
        prereqs => { runtime => { requires => { 'Net::LDAP' => 0 } } },
        description => 'LDAP Authentication'
    },
    old_charts => {
        prereqs => {
            runtime =>
                { requires => { GD => '1.20', 'Chart::Lines' => 'v2.4.10' } }
        },
        description => 'Old Charts'
    },
    moving => {
        prereqs => {
            runtime => {
                requires => { 'MIME::Parser' => '5.406', 'XML::Twig' => 0 }
            }
        },
        description => 'Move Bugs Between Installations'
    },
    oracle => {
        description => 'Oracle database support',
        prereqs => { runtime => { requires => { 'DBD::Oracle' => '1.19' } } }
    },
    s3 => {
        description => 'Amazon S3 Attachment Storage',
        prereqs => {
            runtime => {
                requires => {
                    'Class::Accessor::Fast' => 0,
                    'XML::Simple' => 0,
                    'URI::Escape' => 0,
                }
            }
        }
    },
    typesniffer => {
        prereqs => {
            runtime => {
                requires =>
                    { 'IO::Scalar' => 0, 'File::MimeInfo::Magic' => 0 }
            }
        },
        description => 'Sniff MIME type of attachments'
    },
    sqlite => {
        prereqs => { runtime => { requires => { 'DBD::SQLite' => '1.29' } } },
        description => 'SQLite database support'
    },
    mysql => {
        description => 'MySQL database support',
        prereqs => { runtime => { requires => { 'DBD::mysql' => '4.037' } } }
    },
    jsonrpc => {
        description => 'JSON-RPC Interface',
        prereqs     => {
            runtime =>
                { requires => { 'JSON::RPC' => '== 1.01', 'Test::Taint' => '1.06' } }
        }
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
    mfa => {
        description => 'Multi-Factor Authentication',
        prereqs     => {
            runtime => {
                requires => {
                    'Auth::GoogleAuth'    => '1.01',
                    'GD::Barcode::QRcode' => '0',
                },
            }
        },
    },
    mod_perl => {
        description => 'mod_perl support under Apache',
        prereqs     => {
            runtime => {
                requires => {
                    'mod_perl2'          => '1.999022',
                    'Apache2::SizeLimit' => '0.96',
                }
            }
        }
    },
    inbound_email => {
        prereqs => {
            runtime => {
                requires => {
                    'Email::MIME::Attachment::Stripper' => 0,
                    'Email::Reply'                => 0,
                }
            }
        },
        description => 'Inbound Email'
    },
    patch_viewer => {
        description => 'Patch Viewer',
        prereqs => { runtime => { requires => { PatchReader => '0.9.6' } } }
    },
    rest => {
        description => 'REST Interface',
        prereqs     => {
            runtime => {
                requires => {
                    'Test::Taint' => '1.06',
                    'JSON::RPC' => '==1.01',
                }
            }
        }
    },
    linux_pid => {
        description => 'Linux::PID for MozReview',
        prereqs => {
            runtime => {
                requires => { 'Linux::Pid' => 0 },
            },
        },
    },
    jobqueue => {
        description => 'Mail Queueing',
        prereqs     => {
            runtime => {
                requires => { TheSchwartz => '1.10', 'Daemon::Generic' => 0 }
            }
        }
    },
    csp => {
        description => 'Content-Security-Policy support',
        prereqs     => {
            runtime => {
                requires => {
                    'Type::Tiny' => 1,
                    'MooX::StrictConstructor' => 0.008,
                }
            }
        }
    },
    elasticsearch => {
        description => 'Elasticsearch-powered searches',
        prereqs => {
            runtime => {
                recommends => {
                    'Term::ProgressBar' => 0,
                },
                requires => {
                    'Search::Elasticsearch' => 0,
                    'IO::Async' => 0,
                    'Role::Tiny' => 0,
                },
            }
        },
    },
);

for my $file ( glob("extensions/*/Config.pm") ) {
    my $dir  = dirname($file);
    my $name = basename($dir);

    next if -f File::Spec->catfile( $dir, "disabled" );
    require $file;
    my $class = "Bugzilla::Extension::$name";
    if ( $class->can("REQUIRED_MODULES") ) {
        foreach my $required_module ( @{ $class->REQUIRED_MODULES() } ) {
            $requires{ $required_module->{module} }
                = $required_module->{version};
        }
    }

    if ( $class->can('OPTIONAL_MODULES') ) {
        my $default_feature = 'extension_' . lc($name) . '_optional';
        foreach my $mod ( @{ $class->OPTIONAL_MODULES } ) {
            my @features
                = $mod->{feature} ? @{ $mod->{feature} } : ($default_feature);
            foreach my $feature (@features) {
                $optional_features{$feature}{prereqs}{runtime}{requires}
                    { $mod->{module} } = $mod->{version} // 0;
            }
        }
    }
}

# BMO Customization
my @bmo_features = grep {
    !m{
        ^
        (?: pg
          | oracle
          | mod_perl
          | sqlite
          | auth_ldap
          | auth_radius
          | smtp_auth
          | linux_pid
          | updates)
        $
    }mxs;
} keys %optional_features;

$optional_features{bmo} = {
    description => 'features that bmo needs',
    prereqs => {
        runtime => {
            requires => {
                map { %{$optional_features{$_}{prereqs}{runtime}{requires}} } @bmo_features
            },
        },
    },
};

WriteMakefile(
    NAME             => 'Bugzilla',
    AUTHOR           => q{Bugzilla Developers <developers@bugzilla.org>},
    VERSION          => BUGZILLA_VERSION,
    ABSTRACT         => 'Bugzilla Bug Tracking System',
    LICENSE          => 'Mozilla_2_0',
    MIN_PERL_VERSION => '5.10.1',
    CONFIGURE_REQUIRES => { 'ExtUtils::MakeMaker' => $build_requires{'ExtUtils::MakeMaker'} },
    PREREQ_PM          => { %requires },
    BUILD_REQUIRES     => { %build_requires },
    TEST_REQUIRES      => { %test_requires },
    META_MERGE => {
        "meta-spec" => {
            url     => "http://search.cpan.org/perldoc?CPAN::Meta::Spec",
            version => "2"
        },
        dynamic_config => 1,
        prereqs        => {
            build   => { requires => { %build_requires } },
            runtime => { requires => { %requires }, recommends => { %recommends } },
            test    => { requires => { %test_requires } },
        },
        optional_features => \%optional_features,
    },
);

sub MY::postamble {
    return <<MAKE;
GEN_CPANFILE_ARGS = -D bmo
cpanfile: MYMETA.json
\t\$(PERLRUN) gen-cpanfile.pl \$(GEN_CPANFILE_ARGS)

META.json: Makefile.PL
\tmake distmeta 2>&1 /dev/null; mv */META.json .

META.yml: Makefile.PL
\tmake distmeta 2>&1 /dev/null; mv */META.yml .
MAKE
}
