#!/usr/bin/perl
use 5.10.1;
use strict;
use warnings;

use File::Basename qw(basename dirname);
use File::Spec::Functions qw(catdir rel2abs);
use Cwd qw(realpath);

BEGIN {
    require lib;
    my $dir = realpath( catdir(dirname(__FILE__), '..') );
    lib->import( $dir, catdir( $dir, 'lib' ), catdir( $dir, qw(local lib perl5) ) );
    chdir $dir or die "chdir $dir failed: $!";
}

use autodie;
use Bugzilla;
use English qw(-no_match_vars $PROGRAM_NAME);
use IPC::System::Simple qw(runx capture);
use JSON::MaybeXS qw(decode_json);
use LWP::Simple qw(get);
use LWP::UserAgent;
use MIME::Base64 qw(decode_base64);
use URI::QueryParam;
use URI;

my $github_repo  = "https://github.com/mozilla-bteam/bmo";
my $version_info = decode_json(get('https://bugzilla.mozilla.org/__version__'));
my $tag          = 'release-' . Bugzilla->VERSION;
my $prod_tag     = "release-$version_info->{version}";
my $tag_url      = "$github_repo/tree/$tag";

my @log = capture(qw(git log --oneline), "$prod_tag..HEAD");
die "nothing to commit\n" unless @log;
chomp @log;

my @revisions;
foreach my $line (@log) {
    say $line;
    my ($revision, $message);
    unless ( ( $revision, $message ) = $line =~ /^(\S+) (.+)$/ ) {
        warn "skipping $line\n";
        next;
    }

    my @bug_ids;
    if ($message =~ /\bBug (\d+)/i) {
        push @bug_ids, $1;
    }

    if (!@bug_ids) {
        warn "skipping $line (no bug)\n";
        next;
    }

    foreach my $bug_id (@bug_ids) {
        my $duplicate = 0;
        foreach my $revisions (@revisions) {
            if ($revisions->{bug_id} == $bug_id) {
                $duplicate = 1;
                last;
            }
        }
        next if $duplicate;

        my $bug = fetch_bug($bug_id);
        if ($bug->{status} eq 'RESOLVED' && $bug->{resolution} ne 'FIXED') {
            next;
        }
        if ($bug->{summary} =~ /\bbackport\s+(?:upstream\s+)?bug\s+(\d+)/i) {
            my $upstream = $1;
            $bug->{summary} = fetch_bug($upstream)->{summary};
        }
        push @revisions, {
            hash    => $revision,
            bug_id  => $bug_id,
            summary => $bug->{summary},
        };
    }
}
if (!@revisions) {
    die "no new revisions.  make sure you run this script before production is updated.\n";
}
else {
    @revisions = reverse @revisions;
}

my $first_revision = $revisions[0]->{hash};
my $last_revision  = $revisions[-1]->{hash};

mkdir 'build_info' unless -d 'build_info';
chdir 'build_info';

say "write tag.txt";
open my $tag_fh, '>', 'tag.txt';
say $tag_fh $tag;
close $tag_fh;

say 'write bug.push.txt';

open my $bug_fh, '>', 'bug.push.txt';
say $bug_fh 'https://bugzilla.mozilla.org/enter_bug.cgi?product=bugzilla.mozilla.org&component=Infrastructure&short_desc=push+updated+bugzilla.mozilla.org+live';
say $bug_fh "revisions: $first_revision - $last_revision";
foreach my $revision (@revisions) {
    say $bug_fh "bug $revision->{bug_id} : $revision->{summary}";
}
close $bug_fh;

say 'write blog.push.txt';

open my $blog_fh, '>', 'blog.push.txt';
say $blog_fh "[release tag]($tag_url)\n";
say $blog_fh "the following changes have been pushed to bugzilla.mozilla.org:\n<ul>";
foreach my $revision (@revisions) {
    printf $blog_fh '<li>[<a href="https://bugzilla.mozilla.org/show_bug.cgi?id=%s" target="_blank">%s</a>] %s</li>%s',
        $revision->{bug_id}, $revision->{bug_id}, html_escape($revision->{summary}), "\n";
}
say $blog_fh '</ul>';
say $blog_fh q{discuss these changes on <a href="https://lists.mozilla.org/listinfo/tools-bmo" target="_blank">mozilla.tools.bmo</a>.};
close $blog_fh;

say 'write email.push.txt';

open my $email_fh, '>', 'email.push.txt';
say $email_fh "the following changes have been pushed to bugzilla.mozilla.org:\n";
say $email_fh "(tag: $tag_url)\n";
foreach my $revision (@revisions) {
    printf $email_fh "https://bugzil.la/%s : %s\n", $revision->{bug_id}, $revision->{summary};
}
close $email_fh;

say 'write wiki.push.txt';

open my $wiki_fh, '>', 'wiki.push.txt';
say $wiki_fh 'https://wiki.mozilla.org/BMO/Recent_Changes';
say $wiki_fh '== ' . DateTime->now->set_time_zone('UTC')->ymd('-') . " ==\n";
say $wiki_fh "[$tag_url $tag]";
foreach my $revision (@revisions) {
    printf $wiki_fh "* {{bug|%s}} %s\n", $revision->{bug_id}, $revision->{summary};
}
close $wiki_fh;

sub html_escape {
    my ($s) = @_;
    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    return $s;
}

use constant BUG_FIELDS => [qw(
    id
    product
    version
    target_milestone
    summary
    status
    resolution
    assigned_to
)];

sub fetch_bug {
    my ($bug_id) = @_;
    die 'missing id' unless $bug_id;

    my $response = _get( 'bug/' . $bug_id, { include_fields => BUG_FIELDS, } );
    return $response->{bugs}->[0];
}

sub _get {
    my ($endpoint, $args) = @_;
    my $ua = LWP::UserAgent->new( agent => $PROGRAM_NAME );
    $args //= {};

    if (exists $args->{include_fields} && ref($args->{include_fields})) {
        $args->{include_fields} = join ',', @{ $args->{include_fields} };
    }

    my $uri = URI->new('https://bugzilla.mozilla.org/rest/' . $endpoint);
    foreach my $name (sort keys %$args) {
        $uri->query_param($name => $args->{$name});
    }

    my $request = HTTP::Request->new('GET', $uri->as_string);
    $request->header( Content_Type       => 'application/json' );
    $request->header( Accept             => 'application/json' );
    if ( $ENV{BMO_API_KEY} ) {
        $request->header( X_Bugzilla_API_Key => $ENV{BMO_API_KEY} );
    }

    my $response = $ua->request($request);
    if ($response->code !~ /^2/) {
        my $error = $response->message;
        my $ok = eval {
            $error = decode_json($response->decoded_content)->{message};
            1;
        };
        $error = $@ unless $ok;
        die $error . "\n";
    }
    return decode_json($response->decoded_content);
}
