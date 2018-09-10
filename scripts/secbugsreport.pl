#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
#
# Usage secbugsreport.pl YYYY MM DD, e.g. secbugsreport.pl $(date +'%Y %m %d')

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Component;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Mailer;
use Bugzilla::Report::SecurityRisk;

use DateTime;
use URI;
use JSON::MaybeXS;

BEGIN { Bugzilla->extensions }
Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

exit 0 unless Bugzilla->params->{report_secbugs_active};
exit 0 unless defined $ARGV[0] && defined $ARGV[1] && defined $ARGV[2];

my $html;
my $template     = Bugzilla->template();
my $end_date     = DateTime->new( year => $ARGV[0], month => $ARGV[1], day => $ARGV[2] );
my $start_date   = $end_date->clone()->subtract( months => 6 );
my $report_week  = $end_date->ymd('-');
my $products     = decode_json( Bugzilla->params->{report_secbugs_products} );
my $sec_keywords = [ 'sec-critical', 'sec-high' ];
my $report       = Bugzilla::Report::SecurityRisk->new(
    start_date   => $start_date,
    end_date     => $end_date,
    products     => $products,
    sec_keywords => $sec_keywords
);
my $vars = {
    urlbase         => Bugzilla->localconfig->{urlbase},
    report_week     => $report_week,
    products        => $products,
    sec_keywords    => $sec_keywords,
    results         => $report->results,
    build_bugs_link => \&build_bugs_link,
};

$template->process( 'reports/email/security-risk.html.tmpl', $vars, \$html )
    or ThrowTemplateError( $template->error() );

# For now, only send HTML email.
my $email = Email::MIME->create(
    header_str => [
        From    => Bugzilla->params->{'mailfrom'},
        To      => Bugzilla->params->{report_secbugs_emails},
        Subject => "Security Bugs Report for $report_week"
    ],
    attributes => {
        content_type => 'text/html',
        charset      => 'UTF-8',
        encoding     => 'quoted-printable',
    },
    body_str => $html,
);

MessageToMTA($email);

sub build_bugs_link {
    my ( $arr, $product ) = @_;
    my $uri = URI->new( Bugzilla->localconfig->{urlbase} . 'buglist.cgi' );
    $uri->query_param( bug_id => ( join ',', @$arr ) );
    $uri->query_param( product => $product ) if $product;
    return $uri->as_string;
}
