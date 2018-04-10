# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Logging;
use 5.10.1;
use strict;
use warnings;

use Log::Log4perl qw(:easy);
use Log::Log4perl::MDC;
use File::Spec::Functions qw(rel2abs catfile);
use Bugzilla::Constants qw(bz_locations);
use English qw(-no_match_vars $PROGRAM_NAME);
use Taint::Util qw(untaint);

sub logfile {
    my ($class, $name) = @_;

    my $file = rel2abs(catfile(bz_locations->{logsdir}, $name));
    untaint($file);
    return $file;
}

sub fields {
    return Log::Log4perl::MDC->get_context->{fields} //= {};
}

BEGIN {
    my $file = $ENV{LOG4PERL_CONFIG_FILE} // 'log4perl-syslog.conf';
    Log::Log4perl::Logger::create_custom_level('NOTICE', 'WARN', 5, 2);
    Log::Log4perl->init(rel2abs($file, bz_locations->{confdir}));
    TRACE("logging enabled in $PROGRAM_NAME");
}

# this is copied from Log::Log4perl's :easy handling,
# except we also export NOTICE.
sub import {
    my $caller_pkg = caller;

    return 1 if $Log::Log4perl::IMPORT_CALLED{$caller_pkg}++;

    # Define default logger object in caller's package
    my $logger = Log::Log4perl->get_logger("$caller_pkg");

    # Define DEBUG, INFO, etc. routines in caller's package
    for (qw(TRACE DEBUG INFO NOTICE WARN ERROR FATAL ALWAYS)) {
        my $level = $_;
        $level = 'OFF' if $level eq 'ALWAYS';
        my $lclevel = lc $_;
        Log::Log4perl::easy_closure_create(
            $caller_pkg,
            $_,
            sub {
                Log::Log4perl::Logger::init_warn()
                  unless $Log::Log4perl::Logger::INITIALIZED or $Log::Log4perl::Logger::NON_INIT_WARNED;
                $logger->{$level}->( $logger, @_, $level );
            },
            $logger
        );
    }

    # Define LOGCROAK, LOGCLUCK, etc. routines in caller's package
    for (qw(LOGCROAK LOGCLUCK LOGCARP LOGCONFESS)) {
        my $method = 'Log::Log4perl::Logger::' . lc $_;

        Log::Log4perl::easy_closure_create(
            $caller_pkg,
            $_,
            sub {
                unshift @_, $logger;
                goto &$method;
            },
            $logger
        );
    }

    # Define LOGDIE, LOGWARN
    Log::Log4perl::easy_closure_create(
        $caller_pkg,
        'LOGDIE',
        sub {
            Log::Log4perl::Logger::init_warn()
              unless $Log::Log4perl::Logger::INITIALIZED or $Log::Log4perl::Logger::NON_INIT_WARNED;
            $logger->{FATAL}->( $logger, @_, 'FATAL' );
            $Log::Log4perl::LOGDIE_MESSAGE_ON_STDERR
              ? CORE::die( Log::Log4perl::Logger::callerline( join '', @_ ) )
              : exit $Log::Log4perl::LOGEXIT_CODE;
        },
        $logger
    );

    Log::Log4perl::easy_closure_create(
        $caller_pkg,
        'LOGEXIT',
        sub {
            Log::Log4perl::Logger::init_warn()
              unless $Log::Log4perl::Logger::INITIALIZED or $Log::Log4perl::Logger::NON_INIT_WARNED;
            $logger->{FATAL}->( $logger, @_, 'FATAL' );
            exit $Log::Log4perl::LOGEXIT_CODE;
        },
        $logger
    );

    Log::Log4perl::easy_closure_create(
        $caller_pkg,
        'LOGWARN',
        sub {
            Log::Log4perl::Logger::init_warn()
              unless $Log::Log4perl::Logger::INITIALIZED or $Log::Log4perl::Logger::NON_INIT_WARNED;
            $logger->{WARN}->( $logger, @_, 'WARN' );
            CORE::warn( Log::Log4perl::Logger::callerline( join '', @_ ) )
              if $Log::Log4perl::LOGDIE_MESSAGE_ON_STDERR;
        },
        $logger
    );
}

1;
