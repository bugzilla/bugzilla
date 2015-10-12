# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::MFA::Duo;
use strict;
use parent 'Bugzilla::MFA';

use Bugzilla::DuoWeb;
use Bugzilla::Error;

sub can_verify_inline {
    return 0;
}

sub enroll {
    my ($self, $params) = @_;

    $self->property_set('user', $params->{username});
}

sub prompt {
    my ($self, $vars) = @_;
    my $template = Bugzilla->template;

    $vars->{sig_request} = Bugzilla::DuoWeb::sign_request(
        Bugzilla->params->{duo_ikey},
        Bugzilla->params->{duo_skey},
        Bugzilla->params->{duo_akey},
        $self->property_get('user'),
    );

    print Bugzilla->cgi->header();
    $template->process('mfa/duo/verify.html.tmpl', $vars)
        || ThrowTemplateError($template->error());
}

sub check {
    my ($self, $params) = @_;

    return if Bugzilla::DuoWeb::verify_response(
        Bugzilla->params->{duo_ikey},
        Bugzilla->params->{duo_skey},
        Bugzilla->params->{duo_akey},
        $params->{sig_response}
    );
    ThrowUserError('mfa_bad_code');
}

1;
