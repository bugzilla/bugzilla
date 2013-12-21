# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Auth::Persist::Cookie;
use strict;
use fields qw();

use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::Token;

use List::Util qw(first);

sub new {
    my ($class) = @_;
    my $self = fields::new($class);
    return $self;
}

sub persist_login {
    my ($self, $user) = @_;
    my $dbh = Bugzilla->dbh;
    my $cgi = Bugzilla->cgi;
    my $input_params = Bugzilla->input_params;

    my $ip_addr;
    if ($input_params->{'Bugzilla_restrictlogin'}) {
        $ip_addr = remote_ip();
        # The IP address is valid, at least for comparing with itself in a
        # subsequent login
        trick_taint($ip_addr);
    }

    $dbh->bz_start_transaction();

    my $login_cookie = 
        Bugzilla::Token::GenerateUniqueToken('logincookies', 'cookie');

    $dbh->do("INSERT INTO logincookies (cookie, userid, ipaddr, lastused)
              VALUES (?, ?, ?, NOW())",
              undef, $login_cookie, $user->id, $ip_addr);

    # Issuing a new cookie is a good time to clean up the old
    # cookies.
    $dbh->do("DELETE FROM logincookies WHERE lastused < "
             . $dbh->sql_date_math('LOCALTIMESTAMP(0)', '-',
                                   MAX_LOGINCOOKIE_AGE, 'DAY'));

    $dbh->bz_commit_transaction();

    # Prevent JavaScript from accessing login cookies.
    my %cookieargs = ('-httponly' => 1);

    # Remember cookie only if admin has told so
    # or admin didn't forbid it and user told to remember.
    if ( Bugzilla->params->{'rememberlogin'} eq 'on' ||
         (Bugzilla->params->{'rememberlogin'} ne 'off' &&
          $input_params->{'Bugzilla_remember'} &&
          $input_params->{'Bugzilla_remember'} eq 'on') ) 
    {
        # Not a session cookie, so set an infinite expiry
        $cookieargs{'-expires'} = 'Fri, 01-Jan-2038 00:00:00 GMT';
    }
    if (Bugzilla->params->{'ssl_redirect'}) {
        # Make these cookies only be sent to us by the browser during 
        # HTTPS sessions, if we're using SSL.
        $cookieargs{'-secure'} = 1;
    }

    $cgi->send_cookie(-name => 'Bugzilla_login',
                      -value => $user->id,
                      %cookieargs);
    $cgi->send_cookie(-name => 'Bugzilla_logincookie',
                      -value => $login_cookie,
                      %cookieargs);
}

sub logout {
    my ($self, $param) = @_;

    my $dbh = Bugzilla->dbh;
    my $cgi = Bugzilla->cgi;
    $param = {} unless $param;
    my $user = $param->{user} || Bugzilla->user;
    my $type = $param->{type} || LOGOUT_ALL;

    if ($type == LOGOUT_ALL) {
        $dbh->do("DELETE FROM logincookies WHERE userid = ?",
                 undef, $user->id);
        return;
    }

    # The LOGOUT_*_CURRENT options require the current login cookie.
    # If a new cookie has been issued during this run, that's the current one.
    # If not, it's the one we've received.
    my $cookie = first {$_->name eq 'Bugzilla_logincookie'}
                       @{$cgi->{'Bugzilla_cookie_list'}};
    my $login_cookie;
    if ($cookie) {
        $login_cookie = $cookie->value;
    }
    else {
        $login_cookie = $cgi->cookie("Bugzilla_logincookie") || '';
    }
    trick_taint($login_cookie);

    # These queries use both the cookie ID and the user ID as keys. Even
    # though we know the userid must match, we still check it in the SQL
    # as a sanity check, since there is no locking here, and if the user
    # logged out from two machines simultaneously, while someone else
    # logged in and got the same cookie, we could be logging the other
    # user out here. Yes, this is very very very unlikely, but why take
    # chances? - bbaetz
    if ($type == LOGOUT_KEEP_CURRENT) {
        $dbh->do("DELETE FROM logincookies WHERE cookie != ? AND userid = ?",
                 undef, $login_cookie, $user->id);
    } elsif ($type == LOGOUT_CURRENT) {
        $dbh->do("DELETE FROM logincookies WHERE cookie = ? AND userid = ?",
                 undef, $login_cookie, $user->id);
    } else {
        die("Invalid type $type supplied to logout()");
    }

    if ($type != LOGOUT_KEEP_CURRENT) {
        clear_browser_cookies();
    }

}

sub clear_browser_cookies {
    my $cgi = Bugzilla->cgi;
    $cgi->remove_cookie('Bugzilla_login');
    $cgi->remove_cookie('Bugzilla_logincookie');
    $cgi->remove_cookie('sudo');
}

1;
