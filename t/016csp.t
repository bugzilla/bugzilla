# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

#################
#Bugzilla Test 4#
####Templates####

use 5.14.0;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5 t);

use Test::More;
use File::Find;
use Support::Templates;
use List::MoreUtils qw(any);
use Text::Balanced qw(gen_extract_tagged extract_multiple);

unless ($ENV{CSP_TESTING}) {
  plan(skip_all => "CSP tests not yet default");
  exit;
}

my @event_attrs = qw(
  onabort onafterprint onbeforeprint onbeforeunload onblur oncanplay oncanplaythrough onchange onclick oncontextmenu
  oncopy oncuechange oncut ondblclick ondrag ondragend ondragenter ondragleave ondragover ondragstart ondrop
  ondurationchange onemptied onended onerror onfocus onhashchange oninput oninvalid onkeydown onkeypress onkeyup onload
  onloadeddata onloadedmetadata onloadstart onmessage onmousedown onmousemove onmouseout onmouseover onmouseup
  onmousewheel onoffline ononline onpagehide onpageshow onpaste onpause onplay onplaying onpopstate onprogress
  onratechange onreset onresize onscroll onsearch onseeked onseeking onselect onshow onstalled onstorage onsubmit
  onsuspend ontimeupdate ontoggle onunload onvolumechange onwaiting onwheel
);

my %score;

sub wanted {
  my $name = $File::Find::name;

  return unless /\.html\.tmpl$/;
  return unless -f $name;
  open my $fh, '<', $name or return;
  my $data = do { local $/ = undef; scalar <$fh> };
  close $fh;

  my $tt_parser = gen_extract_tagged("\\[%", "%\\]", undef, {bad => ["\\[%"]});
  my @tt_matches = extract_multiple($data, [$tt_parser]);

  my $found_tt_javascript  = 0;
  my $found_tt_onload      = 0;
  my $found_script_content = 0;
  my @found_event_attr;
  foreach my $match (@tt_matches) {
    if ($match =~ /^\[%/) {
      if ($match =~ /javascript\s+=\s+/) {
        $found_tt_javascript = 1;
        $score{$name}++;
      }
      elsif ($match =~ /onload\s*=/) {
        $found_tt_onload = 1;
        $score{$name}++;
      }
    }
    else {
      foreach my $event_attr (@event_attrs) {
        if ($match =~ /\Q$event_attr\E\s*=\s*['"]/s) {
          push @found_event_attr, $event_attr;
          $score{$name}++;
        }
      }
      my $tag_parser = gen_extract_tagged();
      while (my @tag = $tag_parser->($match)) {
        last unless defined $tag[0];

        if ($tag[3] && $tag[3] =~ /<script/) {
          if ($tag[4]) {
            $score{$name}++;
            $found_script_content = 1;
          }
        }

      }
    }
  }

  my $found_javascript_link = $data =~ /javascript:\S/;
  $score{$name}++ if $found_javascript_link;

  my $found_problems
    = $found_tt_javascript
    || $found_tt_onload
    || @found_event_attr
    || $found_script_content
    || $found_javascript_link;
  ok(!$found_problems, "checking $name");
  if ($found_problems) {
    my $msg = "problems:\n";
    $msg .= "  found javascript tt var\n" if $found_tt_javascript;
    $msg .= "  found onload tt var\n"     if $found_tt_onload;
    $msg .= "  found event attributes: " . join(", ", @found_event_attr) . "\n"
      if @found_event_attr;
    $msg .= "  found script content\n"   if $found_script_content;
    $msg .= "  found javascript: link\n" if $found_javascript_link;
    diag $msg;
  }
}

sub check_for_javascript {
  my ($block) = @_;
  diag $block;
  return '';
}

diag @include_paths;
find({no_chdir => 1, wanted => \&wanted}, @include_paths);

# print out a json file so we can see how bad we're doing.
if (my $score_file = $ENV{CSP_SCORE_FILE}) {
  require JSON::XS;
  diag "writing scores to $score_file";
  open my $score_fh, '>', $score_file;
  print $score_fh JSON::XS->new->pretty->canonical(1)->encode(\%score);
  close $score_fh;
}

done_testing();
