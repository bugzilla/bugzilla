#!/usr/bin/env perl
use 5.10.1;
use strict;
use warnings;
use autodie;
use constant DRIVER => 'Test::Selenium::Remote::Driver';

use Test::More 1.302;
#use constant DRIVER => 'Test::Selenium::Chrome';
BEGIN { plan skip_all => "these tests only run in CI" unless $ENV{CI} && $ENV{CIRCLE_JOB} eq 'test_bmo' };

use ok DRIVER;

my $ADMIN_LOGIN  = $ENV{BZ_TEST_ADMIN} // 'admin@mozilla.bugs';
my $ADMIN_PW_OLD = $ENV{BZ_TEST_ADMIN_PASS} // 'Te6Oovohch';
my $ADMIN_PW_NEW = $ENV{BZ_TEST_ADMIN_NEWPASS} // 'she7Ka8t';

my @require_env = qw(
    BZ_BASE_URL
    BZ_TEST_NEWBIE
    BZ_TEST_NEWBIE_PASS
);

if (DRIVER =~ /Remote/) {
    push @require_env, qw( TWD_HOST TWD_PORT );
}
my @missing_env = grep { ! exists $ENV{$_} } @require_env;
BAIL_OUT("Missing env: @missing_env") if @missing_env;

eval {
    my $sel = DRIVER->new(base_url => $ENV{BZ_BASE_URL});
    $sel->set_implicit_wait_timeout(600);

    login_ok($sel, $ADMIN_LOGIN, $ADMIN_PW_OLD);

    change_password($sel, $ADMIN_PW_OLD, 'Ju9shiePhie6', 'zeeKuj0leib7');
    $sel->title_is("Passwords Don't Match");
    $sel->body_text_contains('The two passwords you entered did not match.');

    change_password($sel, $ADMIN_PW_OLD . "x", "newpassword2", "newpassword2");
    $sel->title_is("Incorrect Old Password");

    change_password($sel, $ADMIN_PW_OLD, "password", "password");
    $sel->title_is("Password Fails Requirements");

    change_password($sel, $ADMIN_PW_OLD, $ADMIN_PW_NEW, $ADMIN_PW_NEW);
    $sel->title_is("User Preferences");
    logout_ok($sel);

    login_ok($sel, $ADMIN_LOGIN, $ADMIN_PW_NEW);

    # we don't protect against password re-use
    change_password($sel, $ADMIN_PW_NEW, $ADMIN_PW_OLD, $ADMIN_PW_OLD);
    $sel->title_is("User Preferences");
    logout_ok($sel);

    login_ok($sel, $ENV{BZ_TEST_NEWBIE}, $ENV{BZ_TEST_NEWBIE_PASS});

    $sel->get_ok("/editusers.cgi");
    $sel->title_is("Authorization Required");
    logout_ok($sel);

    login_ok($sel, $ADMIN_LOGIN, $ADMIN_PW_OLD);

    toggle_require_password_change($sel, $ENV{BZ_TEST_NEWBIE});
    logout_ok($sel);

    login($sel, $ENV{BZ_TEST_NEWBIE}, $ENV{BZ_TEST_NEWBIE_PASS});
    $sel->title_is('Password change required');
    click_and_type($sel, "old_password", $ENV{BZ_TEST_NEWBIE_PASS});
    click_and_type($sel, "new_password1", "password");
    click_and_type($sel, "new_password2", "password");
    submit($sel, '//input[@id="submit"]');
    $sel->title_is('Password Fails Requirements');

    $sel->go_back_ok();
    $sel->title_is('Password change required');
    click_and_type($sel, "old_password", $ENV{BZ_TEST_NEWBIE_PASS});
    click_and_type($sel, "new_password1", "!!" . $ENV{BZ_TEST_NEWBIE_PASS});
    click_and_type($sel, "new_password2", "!!" . $ENV{BZ_TEST_NEWBIE_PASS});
    submit($sel, '//input[@id="submit"]');
    $sel->title_is('Password Changed');
    change_password(
        $sel,
        "!!" . $ENV{BZ_TEST_NEWBIE_PASS},
        $ENV{BZ_TEST_NEWBIE_PASS},
        $ENV{BZ_TEST_NEWBIE_PASS}
    );
    $sel->title_is("User Preferences");

    $sel->get_ok("/userprefs.cgi?tab=account");
    $sel->title_is("User Preferences");
    click_link($sel, "I forgot my password");
    $sel->body_text_contains(
        ["A token for changing your password has been emailed to you.",
         "Follow the instructions in that email to change your password."],
    );
    my $token = get_token();
    ok($token, "got a token from resetting password");
    $sel->get_ok("/token.cgi?t=$token&a=cfmpw");
    $sel->title_is('Change Password');
    click_and_type($sel, "password", "nopandas");
    click_and_type($sel, "matchpassword", "nopandas");
    submit($sel, '//input[@id="update"]');
    $sel->title_is('Password Fails Requirements');
    $sel->go_back_ok();
    $sel->title_is('Change Password');
    click_and_type($sel, "password", '??' . $ENV{BZ_TEST_NEWBIE_PASS});
    click_and_type($sel, "matchpassword", '??' . $ENV{BZ_TEST_NEWBIE_PASS});
    submit($sel, '//input[@id="update"]');
    $sel->title_is('Password Changed');
    $sel->get_ok("/token.cgi?t=$token&a=cfmpw");
    $sel->title_is('Token Does Not Exist');
    $sel->get_ok("/login");
    $sel->title_is('Log in to Bugzilla');
    login_ok($sel, $ENV{BZ_TEST_NEWBIE}, "??" . $ENV{BZ_TEST_NEWBIE_PASS});
    change_password(
        $sel,
        "??" . $ENV{BZ_TEST_NEWBIE_PASS},
        $ENV{BZ_TEST_NEWBIE_PASS},
        $ENV{BZ_TEST_NEWBIE_PASS}
    );
    $sel->title_is("User Preferences");

    logout_ok($sel);
    open my $fh, '>', '/app/data/mailer.testfile';
    close $fh;

    $sel->get('/createaccount.cgi');
    $sel->title_is('Create a new Bugzilla account');
    click_and_type($sel, 'login', $ENV{BZ_TEST_NEWBIE2});
    $sel->find_element('//input[@id="etiquette"]', 'xpath')->click();
    submit($sel, '//input[@value="Create Account"]');
    $sel->title_is("Request for new user account '$ENV{BZ_TEST_NEWBIE2}' submitted");
    my ($create_token) = search_mailer_testfile(
        qr{/token\.cgi\?t=([^&]+)&a=request_new_account}xs
    );
    $sel->get("/token.cgi?t=$create_token&a=request_new_account");
    click_and_type($sel, 'passwd1', $ENV{BZ_TEST_NEWBIE2_PASS});
    click_and_type($sel, 'passwd2', $ENV{BZ_TEST_NEWBIE2_PASS});
    submit($sel, '//input[@value="Create"]');

    $sel->title_is('Bugzilla Main Page');
    $sel->body_text_contains(
        ["The user account $ENV{BZ_TEST_NEWBIE2} has been created",
         "successfully"]
    );
};
if ($@) {
    fail("got exception $@");
}
done_testing();

sub submit {
    my ($sel, $xpath) = @_;
    $sel->find_element($xpath, 'xpath')->submit();
}

sub get_token {
    my $token;
    my $count = 0;
    do {
        sleep 1 if $count++;
        open my $fh, '<', '/app/data/mailer.testfile';
        my $content = do {
            local $/ = undef;
            <$fh>;
        };
        ($token) = $content =~ m!/token\.cgi\?t=3D([^&]+)&a=3Dcfmpw!s;
        close $fh;
    } until $token || $count > 60;
    return $token;
}

sub search_mailer_testfile {
    my ($regexp) = @_;
    my $content = "";
    my @result;
    my $count = 0;
    do {
        sleep 1 if $count++;
        open my $fh, '<', '/app/data/mailer.testfile';
        $content .= do {
            local $/ = undef;
            <$fh>;
        };
        close $fh;
        my $decoded = $content;
        $decoded =~ s/\r\n/\n/gs;
        $decoded =~ s/=\n//gs;
        $decoded =~ s/=([[:xdigit:]]{2})/chr(hex($1))/ges;
        @result = $decoded =~ $regexp;
    } until @result || $count > 60;
    return @result;
}

sub click_and_type {
    my ($sel, $name, $text) = @_;

    eval {
        my $el = $sel->find_element(qq{//input[\@name="$name"]}, 'xpath');
        $el->click();
        $sel->send_keys_to_active_element($text);
        pass("found $name and typed $text");
    };
    if ($@) {
        fail("failed to find $name");
    }
}

sub click_link {
    my ($sel, $text) = @_;
    my $el = $sel->find_element($text, 'link_text');
    $el->click();
}

sub change_password {
    my ($sel, $old, $new1, $new2) = @_;
    $sel->get_ok("/userprefs.cgi?tab=account");
    $sel->title_is("User Preferences");
    click_and_type($sel, "old_password", $old);
    click_and_type($sel, "new_password1", $new1);
    click_and_type($sel, "new_password2", $new2);
    submit($sel, '//input[@value="Submit Changes"]');
}

sub toggle_require_password_change {
    my ($sel, $login) = @_;
    $sel->get_ok("/editusers.cgi");
    $sel->title_is("Search users");
    click_and_type($sel, 'matchstr', $login);
    submit($sel, '//input[@id="search"]');
    $sel->title_is("Select user");
    click_link($sel, $login);
    $sel->find_element('//input[@id="password_change_required"]')->click;
    submit($sel, '//input[@id="update"]');
    $sel->title_is("User $login updated");
}

sub login {
    my ($sel, $login, $password) = @_;

    $sel->get_ok("/login");
    $sel->title_is("Log in to Bugzilla");
    click_and_type($sel, 'Bugzilla_login', $login);
    click_and_type($sel, 'Bugzilla_password', $password);
    submit($sel, '//input[@name="GoAheadAndLogIn"]');
}

sub login_ok {
    my ($sel) = @_;
    login(@_);
    $sel->title_is('Bugzilla Main Page');
}

sub logout_ok {
    my ($sel) = @_;
    $sel->get_ok('/index.cgi?logout=1');
    $sel->title_is("Logged Out");
}
