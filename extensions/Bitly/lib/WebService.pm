# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Bitly::WebService;

use strict;
use warnings;

use base qw(Bugzilla::WebService);

use Bugzilla::CGI;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Search;
use Bugzilla::Search::Quicksearch;
use Bugzilla::Util 'correct_urlbase';
use Bugzilla::WebService::Util 'validate';
use JSON;
use LWP::UserAgent;
use URI;
use URI::Escape;
use URI::QueryParam;

sub _validate_uri {
    my ($self, $params) = @_;

    # extract url from params
    if (!defined $params->{url}) {
        ThrowCodeError(
            'param_required',
            { function => 'Bitly.shorten', param => 'url' }
        );
    }
    my $url = ref($params->{url}) ? $params->{url}->[0] : $params->{url};

    # only allow buglist queries for this bugzilla install
    my $uri = URI->new($url);
    $uri->query(undef);
    $uri->fragment(undef);
    if ($uri->as_string ne correct_urlbase() . 'buglist.cgi') {
        ThrowUserError('bitly_unsupported');
    }

    return URI->new($url);
}

sub shorten {
    my ($self) = shift;
    my $uri = $self->_validate_uri(@_);

    # the list_id is user-specific, remove it
    $uri->query_param_delete('list_id');

    return $self->_bitly($uri);
}

sub list {
    my ($self) = shift;
    my $uri = $self->_validate_uri(@_);

    # map params to cgi vars, converting quicksearch if required
    my $params = $uri->query_param('quicksearch')
        ? Bugzilla::CGI->new(quicksearch($uri->query_param('quicksearch')))->Vars
        : Bugzilla::CGI->new($uri->query)->Vars;

    # execute the search
    my $search = Bugzilla::Search->new(
        params  => $params,
        fields  => ['bug_id'],
        limit   => Bugzilla->params->{max_search_results},
    );
    my $data = $search->data;

    # form a bug_id only url, sanity check the length
    $uri = URI->new(correct_urlbase() . 'buglist.cgi?bug_id=' . join(',', map { $_->[0] } @$data));
    if (length($uri->as_string) > CGI_URI_LIMIT) {
        ThrowUserError('bitly_failure', { message => "Too many bugs returned by search" });
    }

    # shorten
    return $self->_bitly($uri);
}

sub _bitly {
    my ($self, $uri) = @_;

    # form request url
    # http://dev.bitly.com/links.html#v3_shorten
    my $bitly_url = sprintf(
        'https://api-ssl.bitly.com/v3/shorten?access_token=%s&longUrl=%s',
        Bugzilla->params->{bitly_token},
        uri_escape($uri->as_string)
    );

    # is Mozilla::CA isn't installed, skip certificate verification
    eval { require Mozilla::CA };
    $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = $@ ? 0 : 1;

    # request
    my $ua = LWP::UserAgent->new(agent => 'Bugzilla');
    $ua->timeout(10);
    $ua->protocols_allowed(['http', 'https']);
    if (my $proxy_url = Bugzilla->params->{proxy_url}) {
        $ua->proxy(['http', 'https'], $proxy_url);
    }
    else {
        $ua->env_proxy();
    }
    my $response = $ua->get($bitly_url);
    if ($response->is_error) {
        ThrowUserError('bitly_failure', { message => $response->message });
    }
    my $result = decode_json($response->decoded_content);
    if ($result->{status_code} != 200) {
        ThrowUserError('bitly_failure', { message => $result->{status_txt} });
    }

    # return just the short url
    return { url => $result->{data}->{url} };
}

sub rest_resources {
    return [
        qr{^/bitly/shorten$}, {
            GET => {
                method => 'shorten',
            },
        },
        qr{^/bitly/list$}, {
            GET => {
                method => 'list',
            },
        },
    ]
}

1;
