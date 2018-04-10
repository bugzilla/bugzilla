# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Error;

use 5.10.1;
use strict;
use warnings;

use base qw(Exporter);

## no critic (Modules::ProhibitAutomaticExportation)
our @EXPORT = qw( ThrowCodeError ThrowTemplateError ThrowUserError ThrowErrorPage);
## use critic

use Bugzilla::Constants;
use Bugzilla::WebService::Constants;
use Bugzilla::Util;

use Carp;
use Data::Dumper;
use Date::Format;
use Scalar::Util qw(blessed);

# We cannot use $^S to detect if we are in an eval(), because mod_perl
# already eval'uates everything, so $^S = 1 in all cases under mod_perl!
sub _in_eval {
    my $in_eval = 0;
    for (my $stack = 1; my $sub = (caller($stack))[3]; $stack++) {
        last if $sub =~ /^ModPerl/;
        $in_eval = 1 if $sub =~ /^\(eval\)/;
    }
    return $in_eval;
}

sub _throw_error {
    my ($name, $error, $vars, $logfunc) = @_;
    $vars ||= {};
    $vars->{error} = $error;

    # Make sure any transaction is rolled back (if supported).
    # If we are within an eval(), do not roll back transactions as we are
    # eval'uating some test on purpose.
    my $dbh = eval { Bugzilla->dbh };
    $dbh->bz_rollback_transaction() if ($dbh && $dbh->bz_in_transaction() && !_in_eval());

    my $template = Bugzilla->template;
    my $message;

    # There are some tests that throw and catch a lot of errors,
    # and calling $template->process over and over for those errors
    # is too slow. So instead, we just "die" with a dump of the arguments.
    if (Bugzilla->error_mode != ERROR_MODE_TEST && !$Bugzilla::Template::is_processing) {
        $template->process($name, $vars, \$message)
          || ThrowTemplateError($template->error());
    }

    # Let's call the hook first, so that extensions can override
    # or extend the default behavior, or add their own error codes.
    require Bugzilla::Hook;
    Bugzilla::Hook::process('error_catch', { error => $error, vars => $vars,
                                             message => \$message });

    if ($Bugzilla::Template::is_processing) {
        my ($type) = $name =~ /^global\/(user|code)-error/;
        $type //= 'unknown';
        die Template::Exception->new("bugzilla.$type.$error", $vars);
    }

    if (Bugzilla->error_mode == ERROR_MODE_WEBPAGE) {
        my $cgi = Bugzilla->cgi;
        $cgi->close_standby_message('text/html', 'inline', 'error', 'html');
        $template->process($name, $vars)
          || ThrowTemplateError($template->error());
        print $cgi->multipart_final() if $cgi->{_multipart_in_progress};
        $logfunc->("webpage error: $error");
    }
    elsif (Bugzilla->error_mode == ERROR_MODE_TEST) {
        die Dumper($vars);
    }
    elsif (Bugzilla->error_mode == ERROR_MODE_DIE) {
        die "$message\n";
    }
    elsif (Bugzilla->error_mode == ERROR_MODE_DIE_SOAP_FAULT
           || Bugzilla->error_mode == ERROR_MODE_JSON_RPC
           || Bugzilla->error_mode == ERROR_MODE_REST)
    {
        # Clone the hash so we aren't modifying the constant.
        my %error_map = %{ WS_ERROR_CODE() };
        Bugzilla::Hook::process('webservice_error_codes',
                                { error_map => \%error_map });
        my $code = $error_map{$error};
        if (!$code) {
            $code = ERROR_UNKNOWN_FATAL if $name =~ /code/i;
            $code = ERROR_UNKNOWN_TRANSIENT if $name =~ /user/i;
        }

        if (Bugzilla->error_mode == ERROR_MODE_DIE_SOAP_FAULT) {
            $logfunc->("XMLRPC error: $error ($code)");
            die SOAP::Fault->faultcode($code)->faultstring($message);
        }
        else {
            my $server = Bugzilla->_json_server;

            my $status_code = 0;
            if (Bugzilla->error_mode == ERROR_MODE_REST) {
                my %status_code_map = %{ REST_STATUS_CODE_MAP() };
                $status_code = $status_code_map{$code} || $status_code_map{'_default'};
                $logfunc->("REST error: $error (HTTP $status_code, internal code $code)");
            }
            else {
                my $fake_code = 100000 + $code;
                $logfunc->("JSONRPC error: $error ($fake_code)");
            }
            # Technically JSON-RPC isn't allowed to have error numbers
            # higher than 999, but we do this to avoid conflicts with
            # the internal JSON::RPC error codes.
            $server->raise_error(code        => 100000 + $code,
                                 status_code => $status_code,
                                 message     => $message,
                                 id          => $server->{_bz_request_id},
                                 version     => $server->version);
            # Most JSON-RPC Throw*Error calls happen within an eval inside
            # of JSON::RPC. So, in that circumstance, instead of exiting,
            # we die with no message. JSON::RPC checks raise_error before
            # it checks $@, so it returns the proper error.
            die if _in_eval();
            $server->response($server->error_response_header);
        }
    }

    exit;
}

sub _add_vars_to_logging_fields {
    my ($vars) = @_;

    foreach my $key (keys %$vars) {
        Bugzilla::Logging->fields->{"var_$key"} = $vars->{$key};
    }
}

sub _make_logfunc {
    my ($type) = @_;
    my $logger = Log::Log4perl->get_logger("Bugzilla.Error.$type");
    return sub {
        local $Log::Log4perl::caller_depth = $Log::Log4perl::caller_depth + 3;
        if ($type eq 'User') {
            $logger->warn(@_);
        }
        else {
            $logger->error(@_);
        }
    };
}


sub ThrowUserError {
    my ($error, $vars) = @_;
    my $logfunc = _make_logfunc('User');
    _add_vars_to_logging_fields($vars);

    _throw_error( 'global/user-error.html.tmpl', $error, $vars, $logfunc);
}

sub ThrowCodeError {
    my ($error, $vars) = @_;
    my $logfunc = _make_logfunc('Code');
    _add_vars_to_logging_fields($vars);

    _throw_error( 'global/code-error.html.tmpl', $error, $vars, $logfunc );
}

sub ThrowTemplateError {
    my ($template_err) = @_;
    my $dbh = eval { Bugzilla->dbh };
    # Make sure the transaction is rolled back (if supported).
    $dbh->bz_rollback_transaction() if $dbh && $dbh->bz_in_transaction();

    if (blessed($template_err) && $template_err->isa('Template::Exception')) {
        my $type = $template_err->type;
        if ($type =~ /^bugzilla\.(code|user)\.(.+)/) {
            _throw_error("global/$1-error.html.tmpl", $2, $template_err->info);
            return;
        }
    }

    my $vars = {};
    if (Bugzilla->error_mode == ERROR_MODE_DIE) {
        die("error: template error: $template_err");
    }

    # mod_perl overrides exit to call die with this string
    # we never want to display this to the user
    exit if $template_err =~ /\bModPerl::Util::exit\b/;

    state $logger = Log::Log4perl->get_logger('Bugzilla.Error.Template');
    $logger->error($template_err);

    $vars->{'template_error_msg'} = $template_err;
    $vars->{'error'} = "template_error";

    $vars->{'template_error_msg'} =~ s/ at \S+ line \d+\.\s*$//;

    my $template = Bugzilla->template;

    # Try a template first; but if this one fails too, fall back
    # on plain old print statements.
    if (!$template->process("global/code-error.html.tmpl", $vars)) {
        my $maintainer = html_quote(Bugzilla->params->{'maintainer'});
        my $error = html_quote($vars->{'template_error_msg'});
        my $error2 = html_quote($template->error());
        print <<END;
        <tt>
          <p>
            Bugzilla has suffered an internal error:
          </p>
          <p>
            $error
          </p>
          <!-- template error, no real need to show this to the user
          $error2
          -->
          <p>
            The <a href="mailto:$maintainer">Bugzilla maintainers</a> have
            been notified of this error.
          </p>
        </tt>
END
    }
    exit;
}

sub ThrowErrorPage {
    # BMO customisation for bug 659231
    my ($template_name, $message) = @_;

    my $dbh = Bugzilla->dbh;
    $dbh->bz_rollback_transaction() if $dbh->bz_in_transaction();

    if (Bugzilla->error_mode == ERROR_MODE_DIE) {
        die("error: $message");
    }

    if (Bugzilla->error_mode == ERROR_MODE_DIE_SOAP_FAULT
           || Bugzilla->error_mode == ERROR_MODE_JSON_RPC)
    {
        my $code = ERROR_UNKNOWN_TRANSIENT;
        if (Bugzilla->error_mode == ERROR_MODE_DIE_SOAP_FAULT) {
            die SOAP::Fault->faultcode($code)->faultstring($message);
        } else {
            my $server = Bugzilla->_json_server;
            $server->raise_error(code    => 100000 + $code,
                                 message => $message,
                                 id      => $server->{_bz_request_id},
                                 version => $server->version);
            die if _in_eval();
            $server->response($server->error_response_header);
        }
    } else {
        my $cgi = Bugzilla->cgi;
        my $template = Bugzilla->template;
        my $vars = {};
        $vars->{message} = $message;
        print $cgi->header();
        $template->process($template_name, $vars)
          || ThrowTemplateError($template->error());
        exit;
    }
}

1;

__END__

=head1 NAME

Bugzilla::Error - Error handling utilities for Bugzilla

=head1 SYNOPSIS

  use Bugzilla::Error;

  ThrowUserError("error_tag",
                 { foo => 'bar' });

=head1 DESCRIPTION

Various places throughout the Bugzilla codebase need to report errors to the
user. The C<Throw*Error> family of functions allow this to be done in a
generic and localizable manner.

These functions automatically unlock the database tables, if there were any
locked. They will also roll back the transaction, if it is supported by
the underlying DB.

=head1 FUNCTIONS

=over 4

=item C<ThrowUserError>

This function takes an error tag as the first argument, and an optional hashref
of variables as a second argument. These are used by the
I<global/user-error.html.tmpl> template to format the error, using the passed
in variables as required.

=item C<ThrowCodeError>

This function is used when an internal check detects an error of some sort.
This usually indicates a bug in Bugzilla, although it can occur if the user
manually constructs urls without correct parameters.

This function's behaviour is similar to C<ThrowUserError>, except that the
template used to display errors is I<global/code-error.html.tmpl>. In addition
if the hashref used as the optional second argument contains a key I<variables>
then the contents of the hashref (which is expected to be another hashref) will
be displayed after the error message, as a debugging aid.

=item C<ThrowTemplateError>

This function should only be called if a C<template-<gt>process()> fails.
It tries another template first, because often one template being
broken or missing doesn't mean that they all are. But it falls back to
a print statement as a last-ditch error.

=back

=head1 SEE ALSO

L<Bugzilla|Bugzilla>
