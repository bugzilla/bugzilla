# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::TellUsMore::WebService;

use strict;
use warnings;

use base qw(Bugzilla::WebService Bugzilla::Extension);

use Bugzilla::Component;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Mailer;
use Bugzilla::Product;
use Bugzilla::User;
use Bugzilla::UserAgent;
use Bugzilla::Util;
use Bugzilla::Version;

use Bugzilla::Extension::TellUsMore::Constants;

use Data::Dumper;
use Email::MIME;
use MIME::Base64;

sub submit {
    my ($self, $params) = @_;
    my $dbh = Bugzilla->dbh;

    # validation

    my $user = Bugzilla->login(LOGIN_REQUIRED);
    if ($user->email ne TELL_US_MORE_LOGIN) {
        ThrowUserError('tum_auth_failure');
    }

    if (Bugzilla->params->{disable_bug_updates}) {
        ThrowUserError('tum_updates_disabled');
    }

    $self->_validate_params($params);
    $self->_set_missing_params($params);

    my $creator = $self->_get_user($params->{creator});
    if ($creator && $creator->disabledtext ne '') {
        ThrowUserError('tum_account_disabled', { user => $creator });
    }

    $self->_validate_rate($params);

    # create transient entry and email

    $dbh->bz_start_transaction();
    my $token = Bugzilla::Token::GenerateUniqueToken('tell_us_more', 'token');
    my $id = $self->_insert($params, $token);
    my $email = $self->_generate_email($params, $token, $creator);
    $dbh->bz_commit_transaction();

    # send email

    MessageToMTA($email);
    
    # done, return the id from the tell_us_more table

    return $id;
}

sub _validate_params {
    my ($self, $params) = @_;

    $self->_validate_mandatory($params, 'Submission', MANDATORY_BUG_FIELDS);
    $self->_remove_invalid_fields($params, MANDATORY_BUG_FIELDS, OPTIONAL_BUG_FIELDS);

    if (!validate_email_syntax($params->{creator})) {
        ThrowUserError('illegal_email_address', { addr => $params->{creator} });
    }

    if ($params->{attachments}) {
        if (scalar @{$params->{attachments}} > MAX_ATTACHMENT_COUNT) {
            ThrowUserError('tum_too_many_attachments', { max => MAX_ATTACHMENT_COUNT });
        }
        my $i = 0;
        foreach my $attachment (@{$params->{attachments}}) {
            $i++;
            $self->_validate_mandatory($attachment, "Attachment $i", MANDATORY_ATTACH_FIELDS);
            $self->_remove_invalid_fields($attachment, MANDATORY_ATTACH_FIELDS, OPTIONAL_ATTACH_FIELDS);
            if (length(decode_base64($attachment->{content})) > MAX_ATTACHMENT_SIZE * 1024) {
                ThrowUserError('tum_attachment_too_large', { filename => $attachment->{filename}, max => MAX_ATTACHMENT_SIZE });
            }
        }
    }

    # products are mapped to components of the target-product

    Bugzilla::Component->new({ name => $params->{product}, product => $self->_target_product })
        || ThrowUserError('invalid_product_name', { product => $params->{product} });
}

sub _set_missing_params {
    my ($self, $params) = @_;

    # set the product and component correctly

    $params->{component} = $params->{product};
    $params->{product} = TARGET_PRODUCT;

    # priority, bug_severity

    $params->{priority} = Bugzilla->params->{defaultpriority};
    $params->{bug_severity} = Bugzilla->params->{defaultseverity};

    # map invalid versions to 'unspecified'

    if (!$params->{version}) {
        $params->{version} = DEFAULT_VERSION;
    } else {
        Bugzilla::Version->new({ product => $self->_target_product, name => $params->{version} })
            || ($params->{version} = DEFAULT_VERSION);
    }

    # set url

    $params->{bug_file_loc} = $params->{url};

    # detect the opsys and platform from user_agent

    $ENV{HTTP_USER_AGENT} = $params->{user_agent};
    $params->{rep_platform} = detect_platform();
    $params->{op_sys} = detect_op_sys();

    # set group based on restricted

    $params->{group} = $params->{restricted} ? SECURITY_GROUP : '';
    delete $params->{restricted};
}

sub _get_user {
    my ($self, $email) = @_;

    return Bugzilla::User->new({ name => $email });
}

sub _insert {
    my ($self, $params, $token) = @_;
    my $dbh = Bugzilla->dbh;

    local $Data::Dumper::Purity = 1;
    local $Data::Dumper::Sortkeys = 1;
    my $content = Dumper($params);
    trick_taint($content);

    my $sth = $dbh->prepare('
        INSERT INTO tell_us_more(token, mail, creation_ts, content)
        VALUES(?, ?, ?, ?)
    ');
    $sth->bind_param(1, $token);
    $sth->bind_param(2, $params->{creator});
    $sth->bind_param(3, $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)'));
    $sth->bind_param(4, $content, $dbh->BLOB_TYPE);
    $sth->execute();

    return $dbh->bz_last_key('tell_us_more', 'id');
}

sub _generate_email {
    my ($self, $params, $token, $user) = @_;

    # create email parts

    my $template = Bugzilla->template_inner;
    my ($message_header, $message_text, $message_html);
    my $vars = {
        token_url => correct_urlbase() . 'page.cgi?id=tellusmore.html&token=' . url_quote($token),
        recipient_email => $params->{creator},
        recipient_name => ($user ? $user->name : $params->{creator_name}),
    };

    my $prefix = $user ? 'existing' : 'new';
    $template->process("email/$prefix-account.header.tmpl", $vars, \$message_header)
        || ThrowCodeError('template_error', { template_error_msg => $template->error() });
    $template->process("email/$prefix-account.txt.tmpl", $vars, \$message_text)
        || ThrowCodeError('template_error', { template_error_msg => $template->error() });
    $template->process("email/$prefix-account.html.tmpl", $vars, \$message_html)
        || ThrowCodeError('template_error', { template_error_msg => $template->error() });

    # create email object

    my @parts = (
        Email::MIME->create(
            attributes => { content_type => "text/plain" },
            body => $message_text,
        ),
        Email::MIME->create(
            attributes => { content_type => "text/html" },
            body => $message_html,
        ),
    );
    my $email = new Email::MIME("$message_header\n");
    $email->content_type_set('multipart/alternative');
    $email->parts_set(\@parts);

    return $email;
}

sub _validate_mandatory {
    my ($self, $params, $name, @fields) = @_;

    my @missing_fields;
    foreach my $field (@fields) {
        if (!exists $params->{$field} || $params->{$field} eq '') {
            push @missing_fields, $field;
        }
    }

    if (scalar @missing_fields) {
        ThrowUserError('tum_missing_fields', { name => $name, missing => \@missing_fields });
    }
}

sub _remove_invalid_fields {
    my ($self, $params, @valid_fields) = @_;

    foreach my $field (keys %$params) {
        if (!grep { $_ eq $field } @valid_fields) {
            delete $params->{$field};
        }
    }
}

sub _validate_rate {
    my ($self, $params) = @_;
    my $dbh = Bugzilla->dbh;

    my ($report_count) = $dbh->selectrow_array('
        SELECT COUNT(*)
          FROM tell_us_more
         WHERE mail = ?
               AND creation_ts >= NOW() - ' . $dbh->sql_interval(1, 'MINUTE')
        , undef, $params->{creator}
    );
    if ($report_count + 1 > MAX_REPORTS_PER_MINUTE) {
        ThrowUserError('tum_rate_exceeded', { max => MAX_REPORTS_PER_MINUTE });
    }
}

sub _target_product {
    my ($self) = @_;

    my $product = Bugzilla::Product->new({ name => TARGET_PRODUCT })
        || ThrowUserError('invalid_product_name', { product => TARGET_PRODUCT });
    return $product;
}

1;
