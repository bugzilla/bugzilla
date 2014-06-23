# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Sentry;

use strict;
use warnings;

use base qw(Exporter);
our @EXPORT = qw(
    sentry_handle_error
    sentry_should_notify
);

use Carp;
use Data::Dumper;
use DateTime;
use File::Temp;
use LWP::UserAgent;
use Sys::Hostname;
use URI;

use Bugzilla::Constants;
use Bugzilla::RNG qw(irand);
use Bugzilla::Util;
use Bugzilla::WebService::Constants;

use constant CONFIG => {
    # 'codes' lists the code-errors which are sent to sentry
    codes => [qw(
        bug_error
        chart_datafile_corrupt
        chart_dir_nonexistent
        chart_file_open_fail
        illegal_content_type_method
        jobqueue_insert_failed
        ldap_bind_failed
        mail_send_error
        template_error
        token_generation_error
    )],

    # any error/warning messages matching these regex's will not be logged or
    # sent to sentry
    ignore => [
        qr/^compiled template :\s*$/,
        qr/^Use of uninitialized value \$compiled in concatenation \(\.\) or string/,
    ],

    # any error/warning messages matching these regex's will be logged but not
    # sent to sentry
    sentry_ignore => [
        qr/Software caused connection abort/,
        qr/Could not check out .*\/cvsroot/,
        qr/Unicode character \S+ is illegal/,
        qr/Lost connection to MySQL server during query/,
        qr/Call me again when you have some data to chart/,
        qr/relative paths are not allowed/,
    ],

    # (ab)use the logger to classify error/warning types
    logger => [
        {
            match => [
                qr/DBD::mysql/,
                qr/Can't connect to the database/,
            ],
            logger => 'database_error',
        },
        {
            match  => [ qr/PatchReader/ ],
            logger => 'patchreader',
        },
        {
            match  => [ qr/Use of uninitialized value/ ],
            logger => 'uninitialized_warning',
        },
    ],
};

sub sentry_generate_id {
    return sprintf('%04x%04x%04x%04x%04x%04x%04x%04x',
        irand(0xffff), irand(0xffff),
        irand(0xffff),
        irand(0x0fff) | 0x4000,
        irand(0x3fff) | 0x8000,
        irand(0xffff), irand(0xffff), irand(0xffff)
    );
}

sub sentry_should_notify {
    my $code_error = shift;
    return grep { $_ eq $code_error } @{ CONFIG->{codes} };
}

sub sentry_handle_error {
    my $level = shift;
    my @message = split(/\n/, shift);
    my $id = sentry_generate_id();

    my $is_error = $level eq 'error';
    if ($level ne 'error' && $level ne 'warning') {
        # it's a code-error
        return 0 unless sentry_should_notify($level);
        $is_error = 1;
        $level = 'error';
    }

    # build traceback
    my $traceback;
    {
        # for now don't show function arguments, in case they contain
        # confidential data.  waiting on bug 700683
        #local $Carp::MaxArgLen  = 256;
        #local $Carp::MaxArgNums = 0;
        local $Carp::MaxArgNums = -1;
        local $Carp::CarpInternal{'CGI::Carp'} = 1;
        local $Carp::CarpInternal{'Bugzilla::Error'} = 1;
        local $Carp::CarpInternal{'Bugzilla::Sentry'} = 1;
        $traceback = trim(Carp::longmess());
    }

    # strip timestamp
    foreach my $line (@message) {
        $line =~ s/^\[[^\]]+\] //;
    }
    my $message = join(" ", map { trim($_) } grep { $_ ne '' } @message);

    # message content filtering
    foreach my $re (@{ CONFIG->{ignore} }) {
        return 0 if $message =~ $re;
    }

    # determine logger
    my $logger;
    foreach my $config (@{ CONFIG->{logger} }) {
        foreach my $re (@{ $config->{match} }) {
            if ($message =~ $re) {
                $logger = $config->{logger};
                last;
            }
        }
        last if $logger;
    }
    $logger ||= $level;

    # don't send to sentry unless configured
    my $send_to_sentry = Bugzilla->params->{sentry_uri} ? 1 : 0;

    # web service filtering
    if ($send_to_sentry
        && (Bugzilla->error_mode == ERROR_MODE_DIE_SOAP_FAULT || Bugzilla->error_mode == ERROR_MODE_JSON_RPC))
    {
        my ($code) = $message =~ /^(-?\d+): /;
        if ($code
            && !($code == ERROR_UNKNOWN_FATAL || $code == ERROR_UNKNOWN_TRANSIENT))
        {
            $send_to_sentry = 0;
        }
    }

    # message content filtering
    if ($send_to_sentry) {
        foreach my $re (@{ CONFIG->{sentry_ignore} }) {
            if ($message =~ $re) {
                $send_to_sentry = 0;
                last;
            }
        }
    }

    # for now, don't send patchreader errors to sentry
    $send_to_sentry = 0
        if $logger eq 'patchreader';

    # log to apache's error_log
    if ($send_to_sentry) {
        _write_to_error_log("$message [#$id]", $is_error);
    } else {
        $traceback =~ s/\n/ /g;
        _write_to_error_log("$message $traceback", $is_error);
    }

    return 0 unless $send_to_sentry;

    my $user_data = undef;
    eval {
        my $user = Bugzilla->user;
        if ($user->id) {
            $user_data = {
                id   => $user->login,
                name => $user->name,
            };
        }
    };

    my $uri = URI->new(Bugzilla->cgi->self_url);
    $uri->query(undef);

    my $data = {
        event_id    => $id,
        message     => $message,
        timestamp   => DateTime->now->iso8601(),
        level       => $level,
        platform    => 'Other',
        logger      => $logger,
        server_name => hostname(),
        'sentry.interfaces.User' => $user_data,
        'sentry.interfaces.Http' => {
            url             => $uri->as_string,
            method          => $ENV{REQUEST_METHOD},
            query_string    => $ENV{QUERY_STRING},
            env             => \%ENV,
        },
        extra       => {
            stacktrace      => $traceback,
        },
    };

    my $fh = File::Temp->new( UNLINK => 0 );
    if (!$fh) {
        warn "Failed to create temp file: $!\n";
        return;
    }
    print $fh Dumper($data);
    close($fh) or die $!;
    my $filename = $fh->filename;

    my $command = bz_locations()->{'cgi_path'} . "/sentry.pl '$filename' &";
    system($command);
    return 1;
}

sub _write_to_error_log {
    my ($message, $is_error) = @_;
    if ($ENV{MOD_PERL}) {
        require Apache2::Log;
        if ($is_error) {
            Apache2::ServerRec::log_error($message);
        } else {
            Apache2::ServerRec::warn($message);
        }
    } else {
        print STDERR "$message\n";
    }
}

# lifted from Bugzilla::Error
sub _in_eval {
    my $in_eval = 0;
    for (my $stack = 1; my $sub = (caller($stack))[3]; $stack++) {
        last if $sub =~ /^ModPerl/;
        last if $sub =~ /^Bugzilla::Template/;
        $in_eval = 1 if $sub =~ /^\(eval\)/;
    }
    return $in_eval;
}

sub _sentry_die_handler {
    my $message = shift;
    $message =~ s/^undef error - //;

    # avoid recursion, and check for CGI::Carp::die failures
    my $in_cgi_carp_die = 0;
    for (my $stack = 1; my $sub = (caller($stack))[3]; $stack++) {
        return if $sub =~ /:_sentry_die_handler$/;
        $in_cgi_carp_die = 1 if $sub =~ /CGI::Carp::die$/;
    }

    return if _in_eval();

    # mod_perl overrides exit to call die with this string
    exit if $message =~ /\bModPerl::Util::exit\b/;

    my $nested_error = '';
    my $is_compilation_failure = $message =~ /\bcompilation (aborted|failed)\b/i;

    # if we are called via CGI::Carp::die chances are something is seriously
    # wrong, so skip trying to use ThrowTemplateError
    if (!$in_cgi_carp_die && !$is_compilation_failure) {
        eval { Bugzilla::Error::ThrowTemplateError($message) };
        $nested_error = $@ if $@;
    }

    if ($is_compilation_failure ||
        $in_cgi_carp_die ||
        ($nested_error && $nested_error !~ /\bModPerl::Util::exit\b/)
    ) {
        sentry_handle_error('error', $message);

        # and call the normal error management
        # (ISE for web pages, error response for web services, etc)
        CORE::die($message);
    }
    exit;
}

sub install_sentry_handler {
    require CGI::Carp;
    CGI::Carp::set_die_handler(\&_sentry_die_handler);
    $main::SIG{__WARN__} = sub {
        return if _in_eval();
        sentry_handle_error('warning', shift);
    };
}

BEGIN {
    if ($ENV{SCRIPT_NAME} || $ENV{MOD_PERL}) {
        install_sentry_handler();
    }
}

1;
