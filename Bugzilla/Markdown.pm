# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Markdown;
use 5.10.1;
use Moo;

use Encode;
use Mojo::DOM;
use Mojo::Util qw(trim);
use HTML::Escape qw(escape_html);
use List::MoreUtils qw(any);

has 'markdown_parser' => (is => 'lazy');
has 'bugzilla_shorthand' => (
  is      => 'ro',
  default => sub {
    require Bugzilla::Template;
    \&Bugzilla::Template::quoteUrls;
  }
);

sub _build_markdown_parser {
  if (Bugzilla->has_feature('alien_cmark')) {
    require Bugzilla::Markdown::GFM;
    require Bugzilla::Markdown::GFM::Parser;
    return Bugzilla::Markdown::GFM::Parser->new({
      hardbreaks    => 1,
      validate_utf8 => 1,
      safe          => 1,
      extensions    => [qw( autolink tagfilter table strikethrough )],
    });
  }
  else {
    return undef;
  }
}

my $MARKDOWN_OFF = quotemeta '#[markdown(off)]';
sub render_html {
  my ($self, $markdown, $bug, $comment, $user) = @_;
  my $parser = $self->markdown_parser;
  return escape_html($markdown) unless $parser;

  # This makes sure we never handle > foo text in the shortcuts code.
  local $Bugzilla::Template::COLOR_QUOTES = 0;

  if ($markdown =~ /^\s*$MARKDOWN_OFF\n/s) {
    my $text = $self->bugzilla_shorthand->(trim($markdown), $bug);
    my $dom = Mojo::DOM->new($text);
    $dom->find('*')->each(sub {
      my ($e) = @_;
      my $attr = $e->attr;
      foreach my $key (keys %$attr) {
        $attr->{$key} =~ s/\s+/ /gs;
      }
    });
    $text = $dom->to_string;
    my @p = split(/\n{2,}/, $text);
    my $html = join("\n", map { s/\n/<br>\n/gs; "<p>$_</p>\n" } @p );
    return $html;
  }

  $markdown =~ s{<(?!https?://)}{&lt;}gs;

  my @valid_text_parent_tags = ('h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'p', 'li', 'td');
  my @bad_tags               = qw( img );
  my $bugzilla_shorthand     = $self->bugzilla_shorthand;
  my $html                   = decode('UTF-8', $parser->render_html($markdown));

  my $dom = Mojo::DOM->new($html);
  $dom->find(join(', ', @bad_tags))->map('remove');

  $dom->find("a[href]")->grep(\&_is_external_link)->map(attr => rel => 'nofollow');
  $dom->find(join ', ', @valid_text_parent_tags)->map(sub {
    my $node = shift;
    $node->descendant_nodes->map(sub {
      my $child = shift;
      if ( $child->type eq 'text'
        && $child->children->size == 0
        && any { $child->parent->tag eq $_ } @valid_text_parent_tags)
      {
        my $text = $child->content;
        $child->replace(Mojo::DOM->new($bugzilla_shorthand->($text, $bug)));
      }
      return $child;
    });
    return $node;
  });
  return $dom->to_string;

}

sub _is_external_link {
  # the urlbase, without the trailing /
  state $urlbase = substr(Bugzilla->localconfig->urlbase, 0, -1);

  return index($_->attr('href'), $urlbase) != 0;
}


1;
