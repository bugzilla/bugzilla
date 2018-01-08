# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# -*- Mode: perl; indent-tabs-mode: nil -*-

package QA::Util;

use strict;
use Data::Dumper;
use Test::More;
use Test::WWW::Selenium;
use MIME::Base64 qw(decode_base64);
use Sys::Hostname qw(hostname);
use Socket qw(inet_ntoa);
use WWW::Selenium::Util qw(server_is_running);
use URI;

# Fixes wide character warnings
BEGIN {
    my $builder = Test::More->builder;
    binmode $builder->output,         ":encoding(utf8)";
    binmode $builder->failure_output, ":encoding(utf8)";
    binmode $builder->todo_output,    ":encoding(utf8)";
}

use base qw(Exporter);
@QA::Util::EXPORT = qw(
    trim
    url_quote
    random_string

    log_in
    logout
    file_bug_in_product
    create_bug
    edit_bug
    edit_bug_and_return
    go_to_bug
    go_to_home
    go_to_admin
    edit_product
    add_product
    open_advanced_search_page
    set_parameters
    screenshot_page

    get_selenium
    get_rpc_clients

    WAIT_TIME
    CHROME_MODE
);

# How long we wait for pages to load.
use constant WAIT_TIME => 60000;
use constant CONF_FILE =>  $ENV{BZ_QA_CONF_FILE} // "../config/selenium_test.conf";
use constant CHROME_MODE => 1;
use constant NDASH => chr(0x2013);

#####################
# Utility Functions #
#####################

sub random_string {
    my $size = shift || 30; # default to 30 chars if nothing specified
    return join("", map{ ('0'..'9','a'..'z','A'..'Z')[rand 62] } (1..$size));
}

# Remove consecutive as well as leading and trailing whitespaces.
sub trim {
    my ($str) = @_;
    if ($str) {
      $str =~ s/[\r\n\t\s]+/ /g;
      $str =~ s/^\s+//g;
      $str =~ s/\s+$//g;
    }
    return $str;
}

# This originally came from CGI.pm, by Lincoln D. Stein
sub url_quote {
    my ($toencode) = (@_);
    $toencode =~ s/([^a-zA-Z0-9_\-.])/uc sprintf("%%%02x",ord($1))/eg;
    return $toencode;
}

###################
# Setup Functions #
###################

sub get_config {
    # read the test configuration file
    my $conf_file = CONF_FILE;
    my $config = do($conf_file)
        or die "can't read configuration '$conf_file': $!$@";
    my $uri = URI->new($config->{browser_url});
    if (my $ip_packed = gethostbyname($uri->host)) {
        my $ip = inet_ntoa($ip_packed);
        $uri->host($ip);
        $config->{browser_ip_url} = "$uri";
    }
    else {
        die "unable to find ip for $config->{browser_url}\n";
    }
    return $config;
}

sub get_selenium {
    my $chrome_mode = shift;
    my $config = get_config();

    if (!server_is_running) {
        die "Selenium Server isn't running!";
    }

    my $sel = Test::WWW::Selenium->new(
        host        => $config->{host},
        port        => $config->{port},
        browser     => $chrome_mode ? $config->{experimental_browser_launcher} : $config->{browser},
        browser_url => $config->{browser_url}
    );

    return ($sel, $config);
}

sub get_xmlrpc_client {
    my $config = get_config();
    my $xmlrpc_url = $config->{browser_url} . "/" .
                     $config->{bugzilla_installation} . "/xmlrpc.cgi";

    require QA::RPC::XMLRPC;
    my $rpc = new QA::RPC::XMLRPC(proxy => $xmlrpc_url);
    return ($rpc, $config);
}

sub get_jsonrpc_client {
    my ($get_mode) = @_;
    require QA::RPC::JSONRPC;
    my $rpc = new QA::RPC::JSONRPC();
    # If we don't set a long timeout, then the Bug.add_comment test
    # where we add a too-large comment fails.
    $rpc->transport->timeout(180);
    $rpc->version($get_mode ? '1.1' : '1.0');
    $rpc->bz_get_mode($get_mode);
    return $rpc;
}

sub get_rpc_clients {
    my ($xmlrpc, $config) = get_xmlrpc_client();
    my $jsonrpc = get_jsonrpc_client();
    my $jsonrpc_get = get_jsonrpc_client('GET');
    return ($config, $xmlrpc, $jsonrpc, $jsonrpc_get);
}

################################
# Helpers for Selenium Scripts #
################################

sub go_to_home {
    my ($sel, $config) = @_;
    $sel->open_ok("/$config->{bugzilla_installation}/", undef, "Go to the home page");
    $sel->set_speed(500);
    $sel->title_is("Bugzilla Main Page");
}

sub screenshot_page {
    my ($sel, $filename) = @_;
    open my $fh, '>:raw', $filename or die "unable to write $filename: $!";
    binmode $fh;
    print $fh decode_base64($sel->capture_entire_page_screenshot_to_string());
    close $fh;
}

# Go to the home/login page and log in.
sub log_in {
    my ($sel, $config, $user) = @_;

    $sel->open_ok("/$config->{bugzilla_installation}/login", undef, "Go to the home page");
    $sel->title_is("Log in to Bugzilla");
    $sel->type_ok("Bugzilla_login", $config->{"${user}_user_login"}, "Enter $user login name");
    $sel->type_ok("Bugzilla_password", $config->{"${user}_user_passwd"}, "Enter $user password");
    $sel->click_ok("log_in", undef, "Submit credentials");
    $sel->wait_for_page_to_load(WAIT_TIME);
    $sel->title_is("Bugzilla Main Page", "User is logged in");
}

# Log out. Will fail if you are not logged in.
sub logout {
    my $sel = shift;

    $sel->click_ok("link=Log out", undef, "Logout");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Logged Out");
}

# Display the bug form to enter a bug in the given product.
sub file_bug_in_product {
    my ($sel, $product, $classification) = @_;
    my $config = get_config();

    $classification ||= "Unclassified";
    $sel->click_ok('//*[@class="link-file"]//a', undef, "Go create a new bug");
    $sel->wait_for_page_to_load(WAIT_TIME);
    my $title = $sel->get_title();
    if ($sel->is_text_present("Select Classification")) {
        ok(1, "More than one enterable classification available. Display them in a list");
        $sel->click_ok("link=$classification", undef, "Choose $classification");
        $sel->wait_for_page_to_load(WAIT_TIME);
        $title = $sel->get_title();
    }
    if ($sel->is_text_present("Which product is affected by the problem")) {
        ok(1, "Which product is affected by the problem");
        $sel->click_ok("link=Other Products", undef, "Choose full product list");
        $sel->wait_for_page_to_load(WAIT_TIME);
        $title = $sel->get_title();
    }
    if ($sel->is_text_present($product)) {
        ok(1, "Display the list of enterable products");
        $sel->open_ok("/" . $config->{bugzilla_installation} . "/enter_bug.cgi?product=$product&format=__default__", undef, "Choose product $product");
        $sel->wait_for_page_to_load(WAIT_TIME);
    }
    else {
        ok(1, "Only one product available in $classification. Skipping the 'Choose product' page.")
    }
    $sel->title_is("Enter Bug: $product", "Display form to enter bug data");
    # Always make sure all fields are visible
    if ($sel->is_element_present('//input[@value="Show Advanced Fields"]')) {
        $sel->click_ok('//input[@value="Show Advanced Fields"]');
    }
}

sub create_bug {
    my ($sel, $bug_summary) = @_;
    my $ndash = NDASH;

    $sel->click_ok('commit');
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    my $bug_id = $sel->get_value('//input[@name="id" and @type="hidden"]');
    $sel->title_like(qr/$bug_id $ndash( \(.*\))? $bug_summary/, "Bug $bug_id created with summary '$bug_summary'");
    return $bug_id;
}

sub edit_bug {
    my ($sel, $bug_id, $bug_summary, $options) = @_;
    my $btn_id = $options ? $options->{id} : 'commit';
    $sel->click_ok($btn_id);
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->is_text_present_ok("Changes submitted for bug $bug_id");
}

sub edit_bug_and_return {
    my ($sel, $bug_id, $bug_summary, $options) = @_;
    my $ndash = NDASH;
    edit_bug($sel, $bug_id, $bug_summary, $options);
    $sel->click_ok("//a[contains(\@href, 'show_bug.cgi?id=$bug_id')]");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("$bug_id $ndash $bug_summary", "Returning back to bug $bug_id");
}

# Go to show_bug.cgi.
sub go_to_bug {
    my ($sel, $bug_id) = @_;

    $sel->type_ok("quicksearch_top", $bug_id);
    $sel->submit("header-search");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    my $bug_title = $sel->get_title();
    utf8::encode($bug_title) if utf8::is_utf8($bug_title);
    $sel->title_like(qr/^$bug_id /, $bug_title);
}

# Go to admin.cgi.
sub go_to_admin {
    my $sel = shift;

    $sel->click_ok("link=Administration", undef, "Go to the Admin page");
    $sel->wait_for_page_to_load(WAIT_TIME);
    $sel->title_like(qr/^Administer your installation/, "Display admin.cgi");
}

# Go to editproducts.cgi and display the given product.
sub edit_product {
    my ($sel, $product, $classification) = @_;

    $classification ||= "Unclassified";
    go_to_admin($sel);
    $sel->click_ok("link=Products", undef, "Go to the Products page");
    $sel->wait_for_page_to_load(WAIT_TIME);
    my $title = $sel->get_title();
    if ($title eq "Select Classification") {
        ok(1, "More than one enterable classification available. Display them in a list");
        $sel->click_ok("link=$classification", undef, "Choose $classification");
        $sel->wait_for_page_to_load(WAIT_TIME);
    }
    else {
        $sel->title_is("Select product", "Display the list of enterable products");
    }
    $sel->click_ok("link=$product", undef, "Choose $product");
    $sel->wait_for_page_to_load(WAIT_TIME);
    $sel->title_is("Edit Product '$product'", "Display properties of $product");
}

sub add_product {
    my ($sel, $classification) = @_;

    $classification ||= "Unclassified";
    go_to_admin($sel);
    $sel->click_ok("link=Products", undef, "Go to the Products page");
    $sel->wait_for_page_to_load(WAIT_TIME);
    my $title = $sel->get_title();
    if ($title eq "Select Classification") {
        ok(1, "More than one enterable classification available. Display them in a list");
        $sel->click_ok("//a[contains(\@href, 'editproducts.cgi?action=add&classification=$classification')]",
                       undef, "Add product to $classification");
    }
    else {
        $sel->title_is("Select product", "Display the list of enterable products");
        $sel->click_ok("link=Add", undef, "Add a new product");
    }
    $sel->wait_for_page_to_load(WAIT_TIME);
    $sel->title_is("Add Product", "Display the new product form");
}

sub open_advanced_search_page {
    my $sel = shift;

    $sel->click_ok('//*[@class="link-search"]//a');
    $sel->wait_for_page_to_load(WAIT_TIME);
    my $title = $sel->get_title();
    if ($title eq "Simple Search") {
        ok(1, "Display the simple search form");
        $sel->click_ok("link=Advanced Search");
        $sel->wait_for_page_to_load(WAIT_TIME);
    }
    $sel->title_is("Search for bugs", "Display the Advanced search form");
}

# $params is a hashref of the form:
# {section1 => { param1 => {type => '(text|select)', value => 'foo'},
#                param2 => {type => '(text|select)', value => 'bar'},
#                param3 => undef },
#  section2 => { param4 => ...},
# }
# section1, section2, ... is the name of the section
# param1, param2, ... is the name of the parameter (which must belong to the given section)
# type => 'text' is for text fields
# type => 'select' is for drop-down select fields
# undef is for radio buttons (in which case the parameter must be the ID of the radio button)
# value => 'foo' is the value of the parameter (either text or label)
sub set_parameters {
    my ($sel, $params) = @_;

    go_to_admin($sel);
    $sel->click_ok("link=Parameters", undef, "Go to the Config Parameters page");
    $sel->wait_for_page_to_load(WAIT_TIME);
    $sel->title_is("Configuration: General");
    my $last_section = "General";

    foreach my $section (keys %$params) {
        if ($section ne $last_section) {
            $sel->click_ok("link=$section");
            $sel->wait_for_page_to_load_ok(WAIT_TIME);
            $sel->title_is("Configuration: $section");
            $last_section = $section;
        }
        my $param_list = $params->{$section};
        foreach my $param (keys %$param_list) {
            my $data = $param_list->{$param};
            if (defined $data) {
                my $type = $data->{type};
                my $value = $data->{value};

                if ($type eq 'text') {
                    $sel->type_ok($param, $value);
                }
                elsif ($type eq 'select') {
                    $sel->select_ok($param, "label=$value");
                }
                else {
                    ok(0, "Unknown parameter type: $type");
                }
            }
            else {
                # If the value is undefined, then the param name is
                # the ID of the radio button.
                $sel->click_ok($param);
            }
        }
        $sel->click_ok('//input[@type="submit" and @value="Save Changes"]', undef, "Save Changes");
        $sel->wait_for_page_to_load_ok(WAIT_TIME);
        $sel->title_is("Parameters Updated");
    }
}

1;

__END__
