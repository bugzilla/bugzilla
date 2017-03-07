# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Elastic;
use 5.10.1;
use Moo;

use Bugzilla::Elastic::Search;
use Bugzilla::Util qw(trick_taint);

with 'Bugzilla::Elastic::Role::HasClient';
with 'Bugzilla::Elastic::Role::HasIndexName';

sub suggest_users {
    my ($self, $text) = @_;
    my $field = 'suggest_user';
    if ($text =~ /^:(.+)$/) {
        $text = $1;
        $field = 'suggest_nick';
    }

    my $result = eval {
        $self->client->suggest(
            index => $self->index_name,
            body  => {
                $field => {
                    text       => $text,
                    completion => { field => $field, size => 25 },
                }
            }
        );
    };
    if (defined $result) {
        return [ map { $_->{payload} } @{$result->{$field}[0]{options}} ];
    }
    else {
        warn "suggest_users error: $@";
        my $users = Bugzilla::User::match($text, 25, 0);
        return [ map { { real_name => $_->name, name => $_->login } } @$users];
    }
}


1;
