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
use Bugzilla::RNG;
use Bugzilla::Test::Selenium;
use Selenium::Firefox::Profile;
use URI;
use URI::Escape;
use URI::QueryParam;

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
  get_config
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
  check_page_load

  WAIT_TIME
  CHROME_MODE
);

# How long we wait for pages to load.
use constant WAIT_TIME => 60000;
use constant CONF_FILE => $ENV{BZ_QA_CONF_FILE}
  // "../config/selenium_test.conf";
use constant CHROME_MODE => 1;

#####################
# Utility Functions #
#####################

sub random_string {
  my $size = shift || 30;    # default to 30 chars if nothing specified
  return
    join("", map { ('0' .. '9', 'a' .. 'z', 'A' .. 'Z')[Bugzilla::RNG::rand 62] } (1 .. $size));
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
  my $config    = do($conf_file)
    or die "can't read configuration '$conf_file': $!$@";
  my $uri = URI->new($config->{browser_url});
  if (my $ip_packed = gethostbyname($uri->host)) {
    my $ip = inet_ntoa($ip_packed);
    $uri->host($ip);
    $config->{browser_ip_url} = "$uri";
  }
  else {
    die "unable to find IP for $config->{browser_url}\n";
  }
  return $config;
}

sub get_selenium {
  my $chrome_mode = shift;
  my $config      = get_config();

  my $sel = Bugzilla::Test::Selenium->new({
    driver_args => {
      base_url   => $config->{browser_url},
      browser    => 'firefox',
      version    => '',
      javascript => 1
    }
    });

  $sel->driver->set_timeout('implicit', 600);
  $sel->driver->set_timeout('page load', 60000);

  return ($sel, $config);
}

sub get_xmlrpc_client {
  my $config = get_config();
  my $xmlrpc_url
    = $config->{browser_url}
    . "/xmlrpc.cgi";

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
  my $jsonrpc     = get_jsonrpc_client();
  my $jsonrpc_get = get_jsonrpc_client('GET');
  return ($config, $xmlrpc, $jsonrpc, $jsonrpc_get);
}

################################
# Helpers for Selenium Scripts #
################################

sub go_to_home {
  my ($sel) = @_;
  $sel->open_ok("/home", undef, "Go to the home page");
  $sel->wait_for_page_to_load(WAIT_TIME);
  $sel->title_is("Bugzilla Main Page");
}

sub screenshot_page {
  my ($sel, $filename) = @_;
  open my $fh, '>:raw', $filename or die "unable to write $filename: $!";
  binmode $fh;
  print $fh decode_base64($sel->driver->screenshot());
  close $fh;
}

# Go to the home/login page and log in.
sub log_in {
  my ($sel, $config, $user) = @_;

  $sel->open_ok("/login", undef, "Go to the home page");
  $sel->title_is("Log in to Bugzilla");
  $sel->type_ok(
    "Bugzilla_login",
    $config->{"${user}_user_login"},
    "Enter $user login name"
  );
  $sel->type_ok(
    "Bugzilla_password",
    $config->{"${user}_user_passwd"},
    "Enter $user password"
  );
  $sel->click_ok("log_in", undef, "Submit credentials");
  $sel->wait_for_page_to_load(WAIT_TIME);
  $sel->title_is("Bugzilla Main Page", "User is logged in");
}

# Log out. Will fail if you are not logged in.
sub logout {
  my $sel = shift;
  $sel->open_ok('/logout', undef, "Logout");
  $sel->wait_for_page_to_load_ok(WAIT_TIME);
  $sel->title_is("Logged Out");
}

# Display the bug form to enter a bug in the given product.
sub file_bug_in_product {
  my ($sel, $product, $classification) = @_;
  my $config = get_config();

  $sel->add_cookie('TUI',
    'expert_fields=1&history_query=1&people_query=1&information_query=1&custom_search_query=1'
  );

  $classification ||= "Unclassified";
  $sel->click_ok('//*[@class="link-file"]//a', undef, "Go create a new bug");
  $sel->wait_for_page_to_load(WAIT_TIME);

  # Use normal bug form instead of helper
  if ($sel->is_text_present('Switch to the standard bug entry form')) {
    $sel->click_ok('//a[@id="advanced_link"]', undef, 'Switch to the standard bug entry form');
  }

  my $title = $sel->get_title();
  if ($sel->is_text_present("Select Classification")) {
    ok(1,
      "More than one enterable classification available. Display them in a list");
    $sel->click_ok("link=$classification", undef, "Choose $classification");
    $sel->wait_for_page_to_load(WAIT_TIME);
    $title = $sel->get_title();
  }
  if ($sel->is_text_present("Which product is affected by the problem")) {
    ok(1, "Which product is affected by the problem");
    $sel->click_ok('//a/span[contains(text(),"Other Products")]', undef, "Choose full product list");
    $sel->wait_for_page_to_load(WAIT_TIME);
    $title = $sel->get_title();
  }
  if ($sel->is_text_present($product)) {
    ok(1, "Display the list of enterable products");
    $sel->open_ok("/enter_bug.cgi?product=$product&format=__default__",
      undef,
      "Choose product $product"
    );
    $sel->wait_for_page_to_load(WAIT_TIME);
  }
  else {
    ok(1,
      "Only one product available in $classification. Skipping the 'Choose product' page."
    );
  }
  $sel->title_is("Enter Bug: $product", "Display form to enter bug data");
  sleep(1); # FIXME: Delay for slow page performance

  # Select the defect type by default
  # `check_ok()` doesn't work here because the checkbox is invisible
  $sel->driver->execute_script('
    document.querySelector(\'input[name="bug_type"][value="defect"]\').checked = true;
  ');
}

sub create_bug {
  my ($sel, $bug_summary) = @_;
  $sel->click_ok('commit');
  $sel->wait_for_page_to_load_ok(WAIT_TIME);
  my $bug_id = $sel->find_element('//input[@name="id" and @type="hidden"]')->get_value();
  $sel->title_like(
    qr/$bug_id -( \(.*\))? $bug_summary/,
    "Bug $bug_id created with summary '$bug_summary'"
  );
  return $bug_id;
}

sub edit_bug {
  my ($sel, $bug_id, $bug_summary, $options) = @_;
  my $btn_id = $options ? $options->{id} : 'bottom-save-btn';
  $sel->click_ok($btn_id);
  $sel->wait_for_page_to_load_ok(WAIT_TIME);
  $sel->is_text_present_ok("Changes submitted for bug $bug_id");
}

sub edit_bug_and_return {
  my ($sel, $bug_id, $bug_summary, $options) = @_;
  edit_bug($sel, $bug_id, $bug_summary, $options);
  go_to_bug($sel, $bug_id);
}

# Go to show_bug.cgi.
sub go_to_bug {
  my ($sel, $bug_id, $no_edit) = @_;

  $sel->type_ok("quicksearch_top", $bug_id);
  $sel->driver->find_element('//*[@id="quicksearch_top"]')->submit;
  $sel->wait_for_page_to_load_ok(WAIT_TIME);
  check_page_load($sel,
    qq{http://HOSTNAME/show_bug.cgi?id=$bug_id});
  my $bug_title = $sel->get_title();
  utf8::encode($bug_title) if utf8::is_utf8($bug_title);
  $sel->title_like(qr/^$bug_id /, $bug_title);
  sleep(1); # FIXME: Sometimes we try to click edit bug before it is ready so wait a second
  $sel->click_ok('mode-btn-readonly', 'Click Edit Bug') if !$no_edit;
  $sel->click_ok('action-menu-btn', 'Expand action menu');
  $sel->click_ok('action-expand-all', 'Expand all modal panels');
}

# Go to admin.cgi.
sub go_to_admin {
  my $sel = shift;

  $sel->open_ok("/admin.cgi", undef, "Go to the Admin page");
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
    ok(1,
      "More than one enterable classification available. Display them in a list");
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
    ok(1,
      "More than one enterable classification available. Display them in a list");
    $sel->click_ok(
      "//a[contains(\@href, '/editproducts.cgi?action=add&classification=$classification')]",
      undef,
      "Add product to $classification"
    );
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

  $sel->add_cookie('TUI',
    'expert_fields=1&history_query=1&people_query=1&information_query=1&custom_search_query=1'
  );
  $sel->click_ok('//*[@class="link-search"]//a');
  $sel->wait_for_page_to_load(WAIT_TIME);
  my $title = $sel->get_title();
  if ($title eq "Simple Search") {
    ok(1, "Display the simple search form");
    $sel->click_ok("link=Advanced Search");
    $sel->wait_for_page_to_load(WAIT_TIME);
  }
  $sel->remove_all_selections('classification');
  sleep(1); # FIXME: Delay for slow page performance
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
  $sel->title_is("Parameters: General");
  my $last_section = "General";

  foreach my $section (keys %$params) {
    if ($section ne $last_section) {
      $sel->click_ok("link=$section");
      $sel->wait_for_page_to_load_ok(WAIT_TIME);
      $sel->title_is("Parameters: $section");
      $last_section = $section;
    }
    my $param_list = $params->{$section};
    foreach my $param (keys %$param_list) {
      my $data = $param_list->{$param};
      if (defined $data) {
        my $type  = $data->{type};
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
    $sel->click_ok('//input[@type="submit" and @value="Save Changes"]',
      undef, "Save Changes");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Parameters Updated");
  }
}

my @ANY_KEYS = qw( t token list_id );

sub check_page_load {
  my ($sel, $expected) = @_;
  # FIXME: For some reason in some cases I need this otherwise
  # it thinks it is still on the previous page
  sleep(2);
  my $expected_uri = URI->new($expected);
  my $uri = URI->new($sel->get_location);

  foreach my $u ($expected_uri, $uri) {
    $u->host('HOSTNAME:8000');
    # Remove list id from newquery param
    if ($u->query_param('newquery')) {
      my $newquery = $u->query_param('newquery');
      $newquery =~ s/list_id=[^&]+//g;
      $u->query_param(newquery => $newquery);
    }
    foreach my $any_key (@ANY_KEYS) {
      if ($u->query_param($any_key)) {
        $u->query_param($any_key => '__ANYTHING__');
      }
    }
  }

  if ($expected_uri->query_param('id') and $expected_uri->query_param('id') eq '__BUG_ID__') {
    $uri->query_param('id' => '__BUG_ID__');
  }

  if ($expected_uri->query_param('list_id') and $expected_uri->query_param('list_id') eq '__LIST_ID__') {
    $uri->query_param('list_id' => '__LIST_ID__');
  }

  # When comparing two URIs, we need the query params to be in the same order
  # otherwise the comparison fails even when the params are the same.
  fix_query_order($uri);
  fix_query_order($expected_uri);

  my ($pkg, $file, $line) = caller;
  is($uri, $expected_uri, "checking location on $file line $line");
}

sub fix_query_order {
  my ($uri) = @_;
  my $query_hash = $uri->query_form_hash();
  my @out        = ();
  for my $key (sort keys %{$query_hash}) {
    if (ref $query_hash->{$key}) {
      for my $value (@{$query_hash->{$key}}) {
        push @out, sprintf("%s=%s", uri_escape_utf8($key), uri_escape_utf8($value));
      }
    }
    else {
      push @out,
        sprintf("%s=%s", uri_escape_utf8($key), uri_escape_utf8($query_hash->{$key}));
    }
  }
  my $query_string = join '&', @out;
  $uri->query($query_string);
}

1;

__END__
