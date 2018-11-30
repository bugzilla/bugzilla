# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Logging;

our $VERSION = '20181130.1';

use Bugzilla::Auth;
use Bugzilla::Auth::Persist::Cookie;
use Bugzilla::CGI;
use Bugzilla::Elastic;
use Bugzilla::Config;
use Bugzilla::Constants;
use Bugzilla::DB;
use Bugzilla::Error;
use Bugzilla::Extension;
use Bugzilla::Field;
use Bugzilla::Flag;
use Bugzilla::Hook;
use Bugzilla::Install::Localconfig qw(read_localconfig);
use Bugzilla::Install::Util qw(init_console include_languages);
use Bugzilla::Memcached;
use Bugzilla::Template;
use Bugzilla::Token;
use Bugzilla::User;
use Bugzilla::Util;
use Bugzilla::CPAN;
use Bugzilla::Bloomfilter;

use Date::Parse;
use DateTime::TimeZone;
use Encode;
use File::Basename;
use File::Spec::Functions;
use Safe;
use JSON::XS qw(decode_json);
use Scope::Guard;

use parent qw(Bugzilla::CPAN);

#####################################################################
# Constants
#####################################################################

# This is identical to Install::Util::_cache so that things loaded
# into Install::Util::_cache during installation can be read out
# of request_cache later in installation.
use constant request_cache => Bugzilla::Install::Util::_cache();

#####################################################################
# Global Code
#####################################################################

# Note that this is a raw subroutine, not a method, so $class isn't available.
sub init_page {
    # This is probably not needed, but bugs resulting from a dirty
    # request cache are very annoying (see bug 1347335)
    # and this is not an expensive operation.
    clear_request_cache();
    if (Bugzilla->usage_mode == USAGE_MODE_CMDLINE) {
        init_console();
    }
    elsif (Bugzilla->params->{'utf8'}) {
        binmode STDOUT, ':utf8';
    }

    if (i_am_cgi()) {
        Bugzilla::Logging->fields->{remote_ip} = remote_ip();
    }

    # Because this function is run live from perl "use" commands of
    # other scripts, we're skipping the rest of this function if we get here
    # during a perl syntax check (perl -c, like we do during the
    # 001compile.t test).
    return if $^C;

    my $script = basename($0);

    # Because of attachment_base, attachment.cgi handles this itself.
    if ($script ne 'attachment.cgi') {
        do_ssl_redirect_if_required();
    }
}

#####################################################################
# Subroutines and Methods
#####################################################################

my $preload_templates = 0;
sub preload_templates {
    $preload_templates = 1;

    delete request_cache->{template};
    template();
    return 1;
}

sub template {
    request_cache->{template} //= Bugzilla::Template->create(preload => $preload_templates);
    request_cache->{template}->{_is_main} = 1;

    return request_cache->{template};
}

sub template_inner {
    my (undef, $lang) = @_;
    my $cache = request_cache;
    my $current_lang = $cache->{template_current_lang}->[0];
    $lang ||= $current_lang || '';
    my %options = (language => $lang, preload => $preload_templates);
    return $cache->{"template_inner_$lang"} ||= Bugzilla::Template->create(%options);
}

sub extensions {
    my $cache = request_cache;
    if (!$cache->{extensions}) {
        my $extension_packages = Bugzilla::Extension->load_all();
        my @extensions;
        foreach my $package (@$extension_packages) {
            my $extension = $package->new();
            if ($extension->enabled) {
                push(@extensions, $extension);
            }
        }
        $cache->{extensions} = \@extensions;
    }
    return $cache->{extensions};
}

sub cgi {
    return request_cache->{cgi} ||= Bugzilla::CGI->new;
}

sub input_params {
    my ($class, $params) = @_;
    my $cache = request_cache;
    # This is how the WebService and other places set input_params.
    if (defined $params) {
        $cache->{input_params} = $params;
    }
    return $cache->{input_params} if defined $cache->{input_params};

    # Making this scalar makes it a tied hash to the internals of $cgi,
    # so if a variable is changed, then it actually changes the $cgi object
    # as well.
    $cache->{input_params} = $class->cgi->Vars;
    return $cache->{input_params};
}

sub localconfig {
    return $_[0]->process_cache->{localconfig} ||= read_localconfig();
}

sub params {
    return request_cache->{params} ||= Bugzilla::Config::read_param_file();
}

sub get_param_with_override {
    my ($class, $name) = @_;
    return $class->localconfig->{param_override}{$name} // $class->params->{$name};
}

sub user {
    return request_cache->{user} ||= new Bugzilla::User;
}

sub set_user {
    my (undef, $new_user, %option) = @_;

    if ($option{scope_guard}) {
        my $old_user = request_cache->{user};
        request_cache->{user} = $new_user;
        return Scope::Guard->new(
            sub {
                request_cache->{user} = $old_user;
            }
        )
    }
    else {
        request_cache->{user} = $new_user;
    }
}

sub sudoer {
    return request_cache->{sudoer};
}

sub sudo_request {
    my (undef, $new_user, $new_sudoer) = @_;
    request_cache->{user}   = $new_user;
    request_cache->{sudoer} = $new_sudoer;
    # NOTE: If you want to log the start of an sudo session, do it here.
}

sub page_requires_login {
    return request_cache->{page_requires_login};
}

sub github_secret {
    my ($class) = @_;
    my $cache = request_cache;
    my $cgi   = $class->cgi;

    $cache->{github_secret} //= $cgi->cookie('github_secret') // generate_random_password(256);

    return $cache->{github_secret};
}

sub passwdqc {
    my ($class) = @_;
    require Data::Password::passwdqc;

    my $cache  = request_cache;
    my $params = $class->params;

    return $cache->{passwdqc} if $cache->{passwdqc};

    my @min = map { $_ eq 'undef' ? undef : $_ }
        split( /\s*,\s*/, $params->{passwdqc_min} );

    return $cache->{passwdqc} = Data::Password::passwdqc->new(
        min              => \@min,
        max              => $params->{passwdqc_max},
        passphrase_words => $params->{passwdqc_passphrase_words},
        match_length     => $params->{passwdqc_match_length},
        random_bits      => $params->{passwdqc_random_bits},
    );
}

sub assert_password_is_secure {
    my ( $class, $password1 ) = @_;

    my $pwqc = $class->passwdqc;
    ThrowUserError( 'password_insecure', { reason => $pwqc->reason } )
        unless $pwqc->validate_password($password1);
}

sub assert_passwords_match {
    my ( $class, $password1, $password2 ) = @_;

    ThrowUserError('password_mismatch') if $password1 ne $password2;
}

sub login {
    my ($class, $type) = @_;

    return $class->user if $class->user->id;

    my $authorizer = new Bugzilla::Auth();
    $type = LOGIN_REQUIRED if $class->cgi->param('GoAheadAndLogIn');

    if (!defined $type || $type == LOGIN_NORMAL) {
        $type = $class->params->{'requirelogin'} ? LOGIN_REQUIRED : LOGIN_NORMAL;
    }

    # Allow templates to know that we're in a page that always requires
    # login.
    if ($type == LOGIN_REQUIRED) {
        request_cache->{page_requires_login} = 1;
    }

    my $authenticated_user = $authorizer->login($type);

    if (i_am_cgi() && $authenticated_user->id) {
        Bugzilla::Logging->fields->{user_id} = $authenticated_user->id;
    }

    # At this point, we now know if a real person is logged in.

    # Check if a password reset is required
    my $cgi = Bugzilla->cgi;
    my $script_name = $cgi->script_name;
    my $do_logout   = $cgi->param('logout');

    if ( $authenticated_user->password_change_required ) {
        # We cannot show the password reset UI for API calls, so treat those as
        # a disabled account.
        if ( i_am_webservice() ) {
            ThrowUserError( "account_disabled", { disabled_reason => $authenticated_user->password_change_reason } );
        }

        # only allow the reset-password and token pages to handle requests
        # (tokens handles the 'forgot password' process)
        # otherwise redirect user to the reset-password page.
        if ( $script_name !~ m#/(?:reset_password|token)\.cgi$# && !$do_logout ) {
            my $self_url     = trim($cgi->self_url);
            my $sig_type     = 'prev_url:' . $authenticated_user->id;
            my $self_url_sig = issue_hash_sig($sig_type, $self_url);
            my $redir_url    = URI->new( Bugzilla->localconfig->{urlbase} . "reset_password.cgi" );
            $redir_url->query_form(prev_url => $self_url, prev_url_sig => $self_url_sig);
            print $cgi->redirect($redir_url);
            exit;
        }
    }
    elsif ( !i_am_webservice() && $authenticated_user->in_mfa_group && !$authenticated_user->mfa ) {

        # decide if the user needs a warning or to be blocked.
        my $date          = $authenticated_user->mfa_required_date('UTC');
        my $grace_period  = Bugzilla->params->{mfa_group_grace_period};
        my $expired       = defined $date && $date < DateTime->now;
        my $on_mfa_page   = $script_name eq '/userprefs.cgi' && $cgi->param('tab') eq 'mfa';
        my $on_token_page = $script_name eq '/token.cgi';

        Bugzilla->request_cache->{mfa_warning} = 1;
        Bugzilla->request_cache->{mfa_grace_period_expired} = $expired;
        Bugzilla->request_cache->{on_mfa_page} = $on_mfa_page;

        if ( $grace_period == 0 || $expired) {
            if ( !( $on_mfa_page || $on_token_page || $do_logout ) ) {
                print Bugzilla->cgi->redirect("userprefs.cgi?tab=mfa");
                exit;
            }
        }
        else {
            my $dbh = Bugzilla->dbh_main;
            my $date = $dbh->sql_date_math( 'NOW()', '+', '?', 'DAY' );
            my ($mfa_required_date) = $dbh->selectrow_array( "SELECT $date", undef, $grace_period );
            $authenticated_user->set_mfa_required_date($mfa_required_date);
            $authenticated_user->update();
        }
    }

    # We must now check to see if an sudo session is in progress.
    # For a session to be in progress, the following must be true:
    # 1: There must be a logged in user
    # 2: That user must be in the 'bz_sudoer' group
    # 3: There must be a valid value in the 'sudo' cookie
    # 4: A Bugzilla::User object must exist for the given cookie value
    # 5: That user must NOT be in the 'bz_sudo_protect' group
    my $token = $class->cgi->cookie('sudo');
    if (defined $authenticated_user && $token) {
        my ($user_id, $date, $sudo_target_id) = Bugzilla::Token::GetTokenData($token);
        if (!$user_id
            || $user_id != $authenticated_user->id
            || !detaint_natural($sudo_target_id)
            || (time() - str2time($date) > MAX_SUDO_TOKEN_AGE))
        {
            $class->cgi->remove_cookie('sudo');
            ThrowUserError('sudo_invalid_cookie');
        }

        my $sudo_target = new Bugzilla::User($sudo_target_id);
        if ($authenticated_user->in_group('bz_sudoers')
            && defined $sudo_target
            && !$sudo_target->in_group('bz_sudo_protect'))
        {
            $class->set_user($sudo_target);
            request_cache->{sudoer} = $authenticated_user;
            # And make sure that both users have the same Auth object,
            # since we never call Auth::login for the sudo target.
            $sudo_target->set_authorizer($authenticated_user->authorizer);

            # NOTE: If you want to do any special logging, do it here.
        }
        else {
            delete_token($token);
            $class->cgi->remove_cookie('sudo');
            ThrowUserError('sudo_illegal_action', { sudoer => $authenticated_user,
                                                    target_user => $sudo_target });
        }
    }
    else {
        $class->set_user($authenticated_user);
    }

    if (Bugzilla->sudoer) {
        Bugzilla->sudoer->update_last_seen_date();
    } else {
        $class->user->update_last_seen_date();
    }

    # If Mojo native app is requesting login, we need to possibly redirect
    my $C = $Bugzilla::Quantum::CGI::C;
    if ($C->session->{override_login_target}) {
      my $mojo_url = Mojo::URL->new($C->session->{override_login_target});
      $mojo_url->query($C->session->{cgi_params});
      $C->redirect_to($mojo_url);
    }

    return $class->user;
}

sub logout {
    my ($class, $option) = @_;

    # If we're not logged in, go away
    return unless $class->user->id;

    $option = LOGOUT_CURRENT unless defined $option;
    Bugzilla::Auth::Persist::Cookie->logout({type => $option});
    $class->logout_request() unless $option eq LOGOUT_KEEP_CURRENT;
}

sub logout_user {
    my ($class, $user) = @_;
    # When we're logging out another user we leave cookies alone, and
    # therefore avoid calling Bugzilla->logout() directly.
    Bugzilla::Auth::Persist::Cookie->logout({user => $user});
}

# just a compatibility front-end to logout_user that gets a user by id
sub logout_user_by_id {
    my ($class, $id) = @_;
    my $user = new Bugzilla::User($id);
    $class->logout_user($user);
}

# hack that invalidates credentials for a single request
sub logout_request {
    my $class = shift;
    delete request_cache->{user};
    delete request_cache->{sudoer};
    # We can't delete from $cgi->cookie, so logincookie data will remain
    # there. Don't rely on it: use Bugzilla->user->login instead!
}

sub job_queue {
    require Bugzilla::JobQueue;
    return request_cache->{job_queue} ||= Bugzilla::JobQueue->new();
}

sub dbh {
    my ($class) = @_;
    # If we're not connected, then we must want the main db
    return request_cache->{dbh} ||= $class->dbh_main;
}

sub dbh_main {
    return request_cache->{dbh_main} ||= Bugzilla::DB::connect_main();
}

sub languages {
    return Bugzilla::Install::Util::supported_languages();
}

sub current_language {
    return request_cache->{current_language} ||= (include_languages())[0];
}

sub error_mode {
    my (undef, $newval) = @_;
    if (defined $newval) {
        request_cache->{error_mode} = $newval;
    }
    return request_cache->{error_mode}
        || (i_am_cgi() ? ERROR_MODE_WEBPAGE : ERROR_MODE_DIE);
}

# This is used only by Bugzilla::Error to throw errors.
sub _json_server {
    my (undef, $newval) = @_;
    if (defined $newval) {
        request_cache->{_json_server} = $newval;
    }
    return request_cache->{_json_server};
}

sub usage_mode {
    my ($class, $newval) = @_;
    if (defined $newval) {
        if ($newval == USAGE_MODE_BROWSER) {
            $class->error_mode(ERROR_MODE_WEBPAGE);
        }
        elsif ($newval == USAGE_MODE_CMDLINE) {
            $class->error_mode(ERROR_MODE_DIE);
        }
        elsif ($newval == USAGE_MODE_XMLRPC) {
            $class->error_mode(ERROR_MODE_DIE_SOAP_FAULT);
        }
        elsif ($newval == USAGE_MODE_JSON) {
            $class->error_mode(ERROR_MODE_JSON_RPC);
        }
        elsif ($newval == USAGE_MODE_EMAIL) {
            $class->error_mode(ERROR_MODE_DIE);
        }
        elsif ($newval == USAGE_MODE_TEST) {
            $class->error_mode(ERROR_MODE_TEST);
        }
        elsif ($newval == USAGE_MODE_REST) {
            $class->error_mode(ERROR_MODE_REST);
        }
        elsif ($newval == USAGE_MODE_MOJO) {
            $class->error_mode(ERROR_MODE_MOJO);
        }
        else {
            ThrowCodeError('usage_mode_invalid',
                           {'invalid_usage_mode', $newval});
        }
        request_cache->{usage_mode} = $newval;
    }
    return request_cache->{usage_mode}
        || (i_am_cgi()? USAGE_MODE_BROWSER : USAGE_MODE_CMDLINE);
}

sub installation_mode {
    my (undef, $newval) = @_;
    (request_cache->{installation_mode} = $newval) if defined $newval;
    return request_cache->{installation_mode}
        || INSTALLATION_MODE_INTERACTIVE;
}

sub installation_answers {
    my (undef, $filename) = @_;
    if ($filename) {
        my $s = new Safe;
        $s->rdo($filename);

        die "Error reading $filename: $!" if $!;
        die "Error evaluating $filename: $@" if $@;

        # Now read the param back out from the sandbox
        request_cache->{installation_answers} = $s->varglob('answer');
    }
    return request_cache->{installation_answers} || {};
}

sub switch_to_shadow_db {
    my $class = shift;

    if (!request_cache->{dbh_shadow}) {
        if ($class->get_param_with_override('shadowdb')) {
            request_cache->{dbh_shadow} = Bugzilla::DB::connect_shadow();
        } else {
            request_cache->{dbh_shadow} = $class->dbh_main;
        }
    }

    request_cache->{dbh} = request_cache->{dbh_shadow};
    # we have to return $class->dbh instead of {dbh} as
    # {dbh_shadow} may be undefined if no shadow DB is used
    # and no connection to the main DB has been established yet.
    return $class->dbh;
}

sub switch_to_main_db {
    my $class = shift;

    request_cache->{dbh} = $class->dbh_main;
    return $class->dbh_main;
}

sub log_user_request {
    my ($class, $bug_id, $attach_id, $action) = @_;

    return unless (i_am_cgi() || i_am_webservice())
                  && Bugzilla->params->{log_user_requests};

    my $cgi         = $class->cgi;
    my $user_id     = $class->user->id;
    my $request_url = $cgi->request_uri // '';
    my $method      = $cgi->request_method;
    my $user_agent  = $cgi->user_agent // '';
    my $script_name = $cgi->script_name;
    my $server      = "web";

    if ($script_name =~ /rest\.cgi/) {
        $server = $script_name =~ /BzAPI/ ? "bzapi" : "rest";
    }
    elsif ($script_name =~ /xmlrpc\.cgi/) {
        $server = "xmlrpc";
    }
    elsif ($script_name =~ /jsonrpc\.cgi/) {
        $server = "jsonrpc";
    }

    my @params = ($user_id, remote_ip(), $user_agent, $request_url, $method, $bug_id, $attach_id, $action, $server);
    foreach my $param (@params) {
        trick_taint($param) if defined $param;
    }

    eval {
        local request_cache->{dbh};
        $class->switch_to_main_db();
        $class->dbh->do("INSERT INTO user_request_log
                         (user_id, ip_address, user_agent, request_url,
                         method, timestamp, bug_id, attach_id, action, server)
                         VALUES (?, ?, ?, ?, ?, NOW(), ?, ?, ?, ?)", undef, @params);
    };
    warn $@ if $@;
}

sub is_shadow_db {
    my $class = shift;
    return request_cache->{dbh} != $class->dbh_main;
}

sub fields {
    my (undef, $criteria) = @_;
    $criteria ||= {};
    my $cache = request_cache;

    # We create an advanced cache for fields by type, so that we
    # can avoid going back to the database for every fields() call.
    # (And most of our fields() calls are for getting fields by type.)
    #
    # We also cache fields by name, because calling $field->name a few
    # million times can be slow in calling code, but if we just do it
    # once here, that makes things a lot faster for callers.
    if (!defined $cache->{fields}) {
        my @all_fields = Bugzilla::Field->get_all;
        my (%by_name, %by_type);
        foreach my $field (@all_fields) {
            my $name = $field->name;
            $by_type{$field->type}->{$name} = $field;
            $by_name{$name} = $field;
        }
        $cache->{fields} = { by_type => \%by_type, by_name => \%by_name };
    }

    my $fields = $cache->{fields};
    my %requested;
    if (my $types = delete $criteria->{type}) {
        $types = ref($types) ? $types : [$types];
        %requested = map { %{ $fields->{by_type}->{$_} || {} } } @$types;
    }
    else {
        %requested = %{ $fields->{by_name} };
    }

    my $do_by_name = delete $criteria->{by_name};

    # Filtering before returning the fields based on
    # the criterias.
    foreach my $filter (keys %$criteria) {
        foreach my $field (keys %requested) {
            if ($requested{$field}->$filter != $criteria->{$filter}) {
                delete $requested{$field};
            }
        }
    }

    return $do_by_name ? \%requested
        : [sort { $a->sortkey <=> $b->sortkey || $a->name cmp $b->name } values %requested];
}

sub active_custom_fields {
    my (undef, $params) = @_;
    my $cache_id = 'active_custom_fields';
    my $can_cache = ! exists $params->{bug_id};
    if ($params) {
        $cache_id .= ($params->{product} ? '_p' . $params->{product}->id : '') .
                     ($params->{component} ? '_c' . $params->{component}->id : '');
        $cache_id .= ':noext' if $params->{skip_extensions};
    }
    if (!$can_cache || !exists request_cache->{$cache_id}) {
        my $fields = Bugzilla::Field->match({ custom => 1, obsolete => 0, skip_extensions => 1 });
        Bugzilla::Hook::process('active_custom_fields',
                                { fields => \$fields, params => $params });
        if ($can_cache) {
            request_cache->{$cache_id} = $fields;
        } else {
            return @$fields;
        }
    }
    return @{request_cache->{$cache_id}};
}

sub has_flags {

    if (!defined request_cache->{has_flags}) {
        request_cache->{has_flags} = Bugzilla::Flag->any_exist;
    }
    return request_cache->{has_flags};
}

sub local_timezone {
    return $_[0]->process_cache->{local_timezone}
             ||= DateTime::TimeZone->new(name => 'local');
}

# Send messages to syslog for the auditing systems (eg. mozdef) to pick up.
sub audit {
    my (undef, $message) = @_;
    state $logger = Log::Log4perl->get_logger("audit");
    $logger->notice(encode_utf8($message));
}

sub clear_request_cache {
    my (undef, %option) = @_;
    my $request_cache = request_cache();
    my @except        = $option{except} ? @{ $option{except} } : ();

    %{ $request_cache } = map { $_ => $request_cache->{$_} } @except;
}

# This is a per-process cache.  Under mod_cgi it's identical to the
# request_cache.  When using mod_perl, items in this cache live until the
# worker process is terminated.
our $_process_cache = {};

sub process_cache {
    return $_process_cache;
}

# This is a memcached wrapper, which provides cross-process and cross-system
# caching.
sub memcached {
    return request_cache->{memcached} ||= Bugzilla::Memcached->_new();
}

# Connector to the Datadog metrics collection daemon.
sub datadog {
    my ($class, $namespace) = @_;
    my $host      = $class->localconfig->{datadog_host};
    my $port      = $class->localconfig->{datadog_port};

    $namespace //= '';

    if ($class->has_feature('datadog') && $host) {
        require DataDog::DogStatsd;
        return request_cache->{datadog}{$namespace} //= DataDog::DogStatsd->new(
            host      => $host,
            port      => $port,
            namespace => $namespace ? "$namespace." : '',
        );
    }
    else {
        return undef;
    }
}

sub elastic {
    my ($class) = @_;
    $class->process_cache->{elastic} //= Bugzilla::Elastic->new();
}

sub check_rate_limit {
    my ($class, $name, $ip) = @_;
    my $params = Bugzilla->params;
    if ($params->{rate_limit_active}) {
        my $rules = decode_json($params->{rate_limit_rules});
        my $limit = $rules->{$name};
        unless ($limit) {
             warn "no rules for $name!";
             return 0;
        }
        if (Bugzilla->memcached->should_rate_limit("$name:$ip", @$limit)) {
            my $action = 'block';
            my $filter = Bugzilla::Bloomfilter->lookup("rate_limit_whitelist");
            if ($filter && $filter->test($ip)) {
                $action = 'ignore';
            }
            my $limit = join("/", @$limit);
            Bugzilla->audit("[rate_limit] action=$action, ip=$ip, limit=$limit, name=$name");
            if ($action eq 'block') {
                $Bugzilla::Quantum::CGI::C->block_ip($ip);
                ThrowUserError("rate_limit");
            }
        }
    }
}

sub markdown_parser {
    require Bugzilla::Markdown::GFM;
    require Bugzilla::Markdown::GFM::Parser;
    return request_cache->{markdown_parser}
        ||= Bugzilla::Markdown::GFM::Parser->new( {extensions => [qw( autolink tagfilter table strikethrough)] } );
}

# Private methods

# Per-process cleanup. Note that this is a plain subroutine, not a method,
# so we don't have $class available.
*cleanup = \&_cleanup;
sub _cleanup {
    return if $^C;

    # BMO - allow "end of request" processing
    Bugzilla::Hook::process('request_cleanup');
    Bugzilla::Bug->CLEANUP;

    my $main   = Bugzilla->request_cache->{dbh_main};
    my $shadow = Bugzilla->request_cache->{dbh_shadow};
    foreach my $dbh ($main, $shadow) {
        next if !$dbh;
        $dbh->bz_rollback_transaction() if $dbh->bz_in_transaction;
    }
    clear_request_cache();

    Log::Log4perl::MDC->remove();
}

our ($caller_package, $caller_file) = caller;
init_page() if $caller_package eq 'main' && $caller_package !~ /^Test/ && $caller_file =~ /\.t$/;

END {
    cleanup() if $caller_package eq 'main';
}

1;

__END__

=head1 NAME

Bugzilla - Semi-persistent collection of various objects used by scripts
and modules

=head1 SYNOPSIS

  use Bugzilla;

  sub someModulesSub {
    Bugzilla->dbh->prepare(...);
    Bugzilla->template->process(...);
  }

=head1 DESCRIPTION

Several Bugzilla 'things' are used by a variety of modules and scripts. This
includes database handles, template objects, and so on.

This module is a singleton intended as a central place to store these objects.
This approach has several advantages:

=over 4

=item *

They're not global variables, so we don't have issues with them staying around
with mod_perl

=item *

Everything is in one central place, so it's easy to access, modify, and maintain

=item *

Code in modules can get access to these objects without having to have them
all passed from the caller, and the caller's caller, and....

=item *

We can reuse objects across requests using mod_perl where appropriate (eg
templates), whilst destroying those which are only valid for a single request
(such as the current user)

=back

Note that items accessible via this object are demand-loaded when requested.

For something to be added to this object, it should either be able to benefit
from persistence when run under mod_perl (such as the a C<template> object),
or should be something which is globally required by a large ammount of code
(such as the current C<user> object).

=head1 METHODS

Note that all C<Bugzilla> functionality is method based; use C<Bugzilla-E<gt>dbh>
rather than C<Bugzilla::dbh>. Nothing cares about this now, but don't rely on
that.

=over 4

=item C<template>

The current C<Template> object, to be used for output

=item C<template_inner>

If you ever need a L<Bugzilla::Template> object while you're already
processing a template, use this. Also use it if you want to specify
the language to use. If no argument is passed, it uses the last
language set. If the argument is "" (empty string), the language is
reset to the current one (the one used by Bugzilla->template).

=item C<cgi>

The current C<cgi> object. Note that modules should B<not> be using this in
general. Not all Bugzilla actions are cgi requests. Its useful as a convenience
method for those scripts/templates which are only use via CGI, though.

=item C<input_params>

When running under the WebService, this is a hashref containing the arguments
passed to the WebService method that was called. When running in a normal
script, this is a hashref containing the contents of the CGI parameters.

Modifying this hashref will modify the CGI parameters or the WebService
arguments (depending on what C<input_params> currently represents).

This should be used instead of L</cgi> in situations where your code
could be being called by either a normal CGI script or a WebService method,
such as during a code hook.

B<Note:> When C<input_params> represents the CGI parameters, any
parameter specified more than once (like C<foo=bar&foo=baz>) will appear
as an arrayref in the hash, but any value specified only once will appear
as a scalar. This means that even if a value I<can> appear multiple times,
if it only I<does> appear once, then it will be a scalar in C<input_params>,
not an arrayref.

=item C<user>

Default C<Bugzilla::User> object if there is no currently logged in user or
if the login code has not yet been run.  If an sudo session is in progress,
the C<Bugzilla::User> corresponding to the person who is being impersonated.
If no session is in progress, the current C<Bugzilla::User>.

=item C<set_user>

Allows you to directly set what L</user> will return. You can use this
if you want to bypass L</login> for some reason and directly "log in"
a specific L<Bugzilla::User>. Be careful with it, though!

=item C<sudoer>

C<undef> if there is no currently logged in user, the currently logged in user
is not in the I<sudoer> group, or there is no session in progress.  If an sudo
session is in progress, returns the C<Bugzilla::User> object corresponding to
the person who logged in and initiated the session.  If no session is in
progress, returns the C<Bugzilla::User> object corresponding to the currently
logged in user.

=item C<sudo_request>
This begins an sudo session for the current request.  It is meant to be
used when a session has just started.  For normal use, sudo access should
normally be set at login time.

=item C<login>

Logs in a user, returning a C<Bugzilla::User> object, or C<undef> if there is
no logged in user. See L<Bugzilla::Auth|Bugzilla::Auth>, and
L<Bugzilla::User|Bugzilla::User>.

=item C<page_requires_login>

If the current page always requires the user to log in (for example,
C<enter_bug.cgi> or any page called with C<?GoAheadAndLogIn=1>) then
this will return something true. Otherwise it will return false. (This is
set when you call L</login>.)

=item C<logout($option)>

Logs out the current user, which involves invalidating user sessions and
cookies. Three options are available from
L<Bugzilla::Constants|Bugzilla::Constants>: LOGOUT_CURRENT (the
default), LOGOUT_ALL or LOGOUT_KEEP_CURRENT.

=item C<logout_user($user)>

Logs out the specified user (invalidating all his sessions), taking a
Bugzilla::User instance.

=item C<logout_by_id($id)>

Logs out the user with the id specified. This is a compatibility
function to be used in callsites where there is only a userid and no
Bugzilla::User instance.

=item C<logout_request>

Essentially, causes calls to C<Bugzilla-E<gt>user> to return C<undef>. This has the
effect of logging out a user for the current request only; cookies and
database sessions are left intact.

=item C<fields>

This is the standard way to get arrays or hashes of L<Bugzilla::Field>
objects when you need them. It takes the following named arguments
in a hashref:

=over

=item C<by_name>

If false (or not specified), this method will return an arrayref of
the requested fields.

If true, this method will return a hashref of fields, where the keys
are field names and the valules are L<Bugzilla::Field> objects.

=item C<type>

Either a single C<FIELD_TYPE_*> constant or an arrayref of them. If specified,
the returned fields will be limited to the types in the list. If you don't
specify this argument, all fields will be returned.

=back

=item C<error_mode>

Call either C<Bugzilla->error_mode(Bugzilla::Constants::ERROR_MODE_DIE)>
or C<Bugzilla->error_mode(Bugzilla::Constants::ERROR_MODE_DIE_SOAP_FAULT)> to
change this flag's default of C<Bugzilla::Constants::ERROR_MODE_WEBPAGE> and to
indicate that errors should be passed to error mode specific error handlers
rather than being sent to a browser and finished with an exit().

This is useful, for example, to keep C<eval> blocks from producing wild HTML
on errors, making it easier for you to catch them.
(Remember to reset the error mode to its previous value afterwards, though.)

C<Bugzilla->error_mode> will return the current state of this flag.

Note that C<Bugzilla->error_mode> is being called by C<Bugzilla->usage_mode> on
usage mode changes.

=item C<usage_mode>

Call either C<Bugzilla->usage_mode(Bugzilla::Constants::USAGE_MODE_CMDLINE)>
or C<Bugzilla->usage_mode(Bugzilla::Constants::USAGE_MODE_XMLRPC)> near the
beginning of your script to change this flag's default of
C<Bugzilla::Constants::USAGE_MODE_BROWSER> and to indicate that Bugzilla is
being called in a non-interactive manner.

This influences error handling because on usage mode changes, C<usage_mode>
calls C<Bugzilla->error_mode> to set an error mode which makes sense for the
usage mode.

C<Bugzilla->usage_mode> will return the current state of this flag.

=item C<installation_mode>

Determines whether or not installation should be silent. See
L<Bugzilla::Constants> for the C<INSTALLATION_MODE> constants.

=item C<installation_answers>

Returns a hashref representing any "answers" file passed to F<checksetup.pl>,
used to automatically answer or skip prompts.

=item C<dbh>

The current database handle. See L<DBI>.

=item C<dbh_main>

The main database handle. See L<DBI>.

=item C<languages>

Currently installed languages.
Returns a reference to a list of RFC 1766 language tags of installed languages.

=item C<current_language>

The currently active language.

=item C<switch_to_shadow_db>

Switch from using the main database to using the shadow database.

=item C<switch_to_main_db>

Change the database object to refer to the main database.

=item C<params>

The current Parameters of Bugzilla, as a hashref. If C<data/params>
does not exist, then we return an empty hashref. If C<data/params>
is unreadable or is not valid perl, we C<die>.

=item C<local_timezone>

Returns the local timezone of the Bugzilla installation,
as a DateTime::TimeZone object. This detection is very time
consuming, so we cache this information for future references.

=item C<job_queue>

Returns a L<Bugzilla::JobQueue> that you can use for queueing jobs.
Will throw an error if job queueing is not correctly configured on
this Bugzilla installation.

=item C<feature>

Tells you whether or not a specific feature is enabled. For names
of features, see C<OPTIONAL_MODULES> in C<Bugzilla::Install::Requirements>.

=item C<audit>

Feeds the provided message into our centralised auditing system.

=item C<markdown_parser>

Returns a L<Bugzilla::Markdown::GFM::Parser> with the default extensions
loaded (autolink, tagfilter, table, and strikethrough).

=back

=head1 B<CACHING>

Bugzilla has several different caches available which provide different
capabilities and lifetimes.

The keys of all caches are unregulated; use of prefixes is suggested to avoid
collisions.

=over

=item B<Request Cache>

The request cache is a hashref which supports caching any perl variable for the
duration of the current request. At the end of the current request the contents
of this cache are cleared.

Examples of its use include caching objects to avoid re-fetching the same data
from the database, and passing data between otherwise unconnected parts of
Bugzilla.

=over

=item C<request_cache>

Returns a hashref which can be checked and modified to store any perl variable
for the duration of the current request.

=item C<clear_request_cache>

Removes all entries from the C<request_cache>.

=back

=item B<Process Cache>

The process cache is a hashref which support caching of any perl variable. If
Bugzilla is configured to run using Apache mod_perl, the contents of this cache
are persisted across requests for the lifetime of the Apache worker process
(which varies depending on the SizeLimit configuration in mod_perl.pl).

If Bugzilla isn't running under mod_perl, the process cache's contents are
cleared at the end of the request.

The process cache is only suitable for items which never change while Bugzilla
is running (for example the path where Bugzilla is installed).

=over

=item C<process_cache>

Returns a hashref which can be checked and modified to store any perl variable
for the duration of the current process (mod_perl) or request (mod_cgi).

=back

=item B<Memcached>

If Memcached is installed and configured, Bugzilla can use it to cache data
across requests and between webheads. Unlike the request and process caches,
only scalars, hashrefs, and arrayrefs can be stored in Memcached.

Memcached integration is only required for large installations of Bugzilla -- if
you have multiple webheads then configuring Memcached is recommended.

=over

=item C<memcached>

Returns a C<Bugzilla::Memcached> object. An object is always returned even if
Memcached is not available.

See the documentation for the C<Bugzilla::Memcached> module for more
information.

=back

=back
