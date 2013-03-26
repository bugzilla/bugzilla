# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Arecibo;

use strict;
use warnings;

use base qw(Exporter);
our @EXPORT = qw(
    arecibo_handle_error
    arecibo_generate_id
    arecibo_should_notify
);

use Apache2::Log;
use Apache2::SubProcess;
use Carp;
use Data::Dumper;
use Email::Date::Format qw(email_gmdate);
use File::Temp;
use LWP::UserAgent;
use Sys::Hostname;

use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::WebService::Constants;

use constant CONFIG => {
    # 'types' maps from the error message to types and priorities
    types => [
        {
            type  => 'the_schwartz',
            boost => -10,
            match => [
                qr/TheSchwartz\.pm/,
            ],
        },
        {
            type  => 'database_error',
            boost => -10,
            match => [
                qr/DBD::mysql/,
                qr/Can't connect to the database/,
            ],
        },
        {
            type  => 'patch_reader',
            boost => +5,
            match => [
                qr#/PatchReader/#,
            ],
        },
        {
            type  => 'uninitialized_warning',
            boost => 0,
            match => [
                qr/Use of uninitialized value/,
            ],
        },
    ],

    # 'codes' lists the code-errors which are sent to arecibo
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

    # any error messages matching these regex's will not be sent to arecibo
    ignore => [
        qr/Software caused connection abort/,
        qr/Could not check out .*\/cvsroot/,
    ],
};

sub arecibo_generate_id {
    return sprintf("%s.%s", (time), $$);
}

sub arecibo_should_notify {
    my $code_error = shift;
    return grep { $_ eq $code_error } @{CONFIG->{codes}};
}

sub arecibo_handle_error {
    my $class = shift;
    my @message = split(/\n/, shift);
    my $id = arecibo_generate_id();

    my $is_error = $class eq 'error';
    if ($class ne 'error' && $class ne 'warning') {
        # it's a code-error
        return 0 unless arecibo_should_notify($class);
        $is_error = 1;
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
        local $Carp::CarpInternal{'Bugzilla::Error'}   = 1;
        local $Carp::CarpInternal{'Bugzilla::Arecibo'} = 1;
        $traceback = Carp::longmess();
    }

    # strip timestamp
    foreach my $line (@message) {
        $line =~ s/^\[[^\]]+\] //;
    }
    my $message = join(" ", map { trim($_) } grep { $_ ne '' } @message);

    # don't send to arecibo unless configured
    my $arecibo_server = Bugzilla->params->{arecibo_server} || '';
    my $send_to_arecibo = $arecibo_server ne '';

    # web service filtering
    if ($send_to_arecibo
        && (Bugzilla->error_mode == ERROR_MODE_DIE_SOAP_FAULT || Bugzilla->error_mode == ERROR_MODE_JSON_RPC))
    {
        my ($code) = $message =~ /^(-?\d+): /;
        if ($code
            && !($code == ERROR_UNKNOWN_FATAL || $code == ERROR_UNKNOWN_TRANSIENT))
        {
            $send_to_arecibo = 0;
        }
    }

    # message content filtering
    if ($send_to_arecibo) {
        foreach my $re (@{CONFIG->{ignore}}) {
            if ($message =~ $re) {
                $send_to_arecibo = 0;
                last;
            }
        }
    }

    # log to apache's error_log
    if ($send_to_arecibo) {
        $message .= " [#$id]";
    } else {
        $traceback =~ s/\n/ /g;
        $message .= " $traceback";
    }
    _write_to_error_log($message, $is_error);

    return 0 unless $send_to_arecibo;

    # set the error type and priority from the message content
    $message = join("\n", grep { $_ ne '' } @message);
    my $type = '';
    my $priority = $class eq 'error' ? 3 : 10;
    foreach my $rh_type (@{CONFIG->{types}}) {
        foreach my $re (@{$rh_type->{match}}) {
            if ($message =~ $re) {
                $type = $rh_type->{type};
                $priority += $rh_type->{boost};
                last;
            }
        }
        last if $type ne '';
    }
    $type ||= $class;
    $priority = 1 if $priority < 1;
    $priority = 10 if $priority > 10;

    my $username = '';
    eval { $username = Bugzilla->user->login };

    my $request = '';
    foreach my $name (sort { lc($a) cmp lc($b) } keys %ENV) {
        $request .= "$name=$ENV{$name}\n";
    }
    chomp($request);

    my $data = [
        ip         => remote_ip(),
        msg        => $message,
        priority   => $priority,
        server     => hostname(),
        request    => $request,
        status     => '500',
        timestamp  => email_gmdate(),
        traceback  => $traceback,
        type       => $type,
        uid        => $id,
        url        => Bugzilla->cgi->self_url,
        user_agent => $ENV{HTTP_USER_AGENT},
        username   => $username,
    ];

    my $fh = File::Temp->new( UNLINK => 0 );
    if (!$fh) {
        warn "Failed to create temp file: $!\n";
        return;
    }
    print $fh Dumper($data);
    close($fh) or die $!;
    my $filename = $fh->filename;

    my $command = bz_locations()->{'cgi_path'} . "/arecibo.pl '$filename' &";
    system($command);
    return 1;
}

sub _write_to_error_log {
    my ($message, $is_error) = @_;
    if ($ENV{MOD_PERL}) {
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

sub _arecibo_die_handler {
    my $message = shift;
    $message =~ s/^undef error - //;

    # avoid recursion, and check for CGI::Carp::die failures
    my $in_cgi_carp_die = 0;
    for (my $stack = 1; my $sub = (caller($stack))[3]; $stack++) {
        return if $sub =~ /:_arecibo_die_handler$/;
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
        arecibo_handle_error('error', $message);

        # and call the normal error management
        # (ISE for web pages, error response for web services, etc)
        CORE::die($message);
    }
    exit;
}

sub install_arecibo_handler {
    require CGI::Carp;
    CGI::Carp::set_die_handler(\&_arecibo_die_handler);
    $main::SIG{__WARN__} = sub {
        return if _in_eval();
        arecibo_handle_error('warning', shift);
    };
}

BEGIN {
    if ($ENV{SCRIPT_NAME} || $ENV{MOD_PERL}) {
        install_arecibo_handler();
    }
}

1;
