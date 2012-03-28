# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::TellUsMore::Process;

use strict;
use warnings;

use Bugzilla::Bug;
use Bugzilla::Component;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Hook;
use Bugzilla::Product;
use Bugzilla::User;
use Bugzilla::Util;
use Bugzilla::Version;

use Bugzilla::Extension::TellUsMore::Constants;

use Data::Dumper;
use File::Basename;
use MIME::Base64;
use Safe;

sub new {
    my $invocant = shift;
    my $class = ref($invocant) || $invocant;
    my $object = {};
    bless($object, $class);
    return $object;
}

sub execute {
    my ($self, $token) = @_;
    my $dbh = Bugzilla->dbh;

    my ($bug, $user, $is_new_user);
    Bugzilla->error_mode(ERROR_MODE_DIE);
    eval {
        $self->_delete_stale_issues();
        my ($mail, $params) = $self->_deserialise_token($token);

        $dbh->bz_start_transaction();

        $self->_fix_invalid_params($params);

        ($user, $is_new_user) = $self->_get_user($mail, $params);

        $bug = $self->_create_bug($user, $params);
        $self->_post_bug_hook($bug);

        $self->_delete_token($token);
        $dbh->bz_commit_transaction();

        $self->_send_mail($bug, $user);
    };
    $self->{error} = $@;
    Bugzilla->error_mode(ERROR_MODE_WEBPAGE);
    return $self->{error} ? undef : ($bug, $is_new_user);
}

sub error {
    my ($self) = @_;
    return $self->{error};
}

sub _delete_stale_issues {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;

    # delete issues older than TOKEN_EXPIRY_DAYS

    $dbh->do("
        DELETE FROM tell_us_more
         WHERE creation_ts < NOW() - " .
               $dbh->sql_interval(TOKEN_EXPIRY_DAYS, 'DAY')
    );
}

sub _deserialise_token {
    my ($self, $token) = @_;
    my $dbh = Bugzilla->dbh;

    # validate token

    trick_taint($token);
    my ($mail, $params) = $dbh->selectrow_array(
        "SELECT mail,content FROM tell_us_more WHERE token=?",
        undef, $token
    );
    ThrowUserError('token_does_not_exist') unless $mail;

    # deserialise, return ($mail, $params)
   
    my $compartment = Safe->new();
    $compartment->reval($params)
        || ThrowUserError('token_does_not_exist');
    $params = ${$compartment->varglob('VAR1')};

    return ($mail, $params);
}

sub _fix_invalid_params {
    my ($self, $params) = @_;

    # silently adjust any params which are no longer valid
    # so we don't lose the submission

    my $product = Bugzilla::Product->new({ name => TARGET_PRODUCT })
        || ThrowUserError('invalid_product_name', { product => TARGET_PRODUCT });

    # component --> general

    my $component = Bugzilla::Component->new({ product => $product, name => $params->{component} })
        || Bugzilla::Component->new({ product => $product, name => DEFAULT_COMPONENT })
        || ThrowUserError('tum_invalid_component', { product => TARGET_PRODUCT, name => DEFAULT_COMPONENT });
    $params->{component} = $component->name;
    
    # version --> unspecified

    my $version = Bugzilla::Version->new({ product => $product, name => $params->{version} })
        || Bugzilla::Version->new({ product => $product, name => DEFAULT_VERSION });
    $params->{version} = $version->name;
}

sub _get_user {
    my ($self, $mail, $params) = @_;

    # return existing bmo user

    my $user = Bugzilla::User->new({ name => $mail });
    return ($user, 0) if $user;

    # or create new user

    $user = Bugzilla::User->create({
        login_name => $mail,
        cryptpassword => '*',
        realname => $params->{creator_name},
    });
    return ($user, 1);
}

sub _create_bug {
    my ($self, $user, $params) = @_;
    my $template = Bugzilla->template;
    my $vars = {};

    # login as the user

    Bugzilla->set_user($user);

    # create the bug

    my $create = {
        product => $params->{product},
        component => $params->{component},
        short_desc => $params->{summary},
        comment => $params->{description},
        version => $params->{version},
        rep_platform => $params->{rep_platform},
        op_sys => $params->{op_sys},
        bug_severity => $params->{bug_severity},
        priority => $params->{priority},
        bug_file_loc => $params->{bug_file_loc},
    };
    if ($params->{group}) {
        $create->{groups} = [ $params->{group} ];
    };

    my $bug = Bugzilla::Bug->create($create);

    # add attachments

    foreach my $attachment (@{$params->{attachments}}) {
        $self->_add_attachment($bug, $attachment);
    }
    if (scalar @{$params->{attachments}}) {
        $bug->update();
    }

    return $bug;
}

sub _add_attachment {
    my ($self, $bug, $params) = @_;
    my $dbh = Bugzilla->dbh;

    # init

    my $timestamp = $dbh->selectrow_array('SELECT creation_ts FROM bugs WHERE bug_id=?', undef, $bug->bug_id);
    my $data = decode_base64($params->{content});

    my $description;
    if ($params->{description}) {
        $description = $params->{description};
    } else {
        $description = $params->{filename};
        $description =~ s/\\/\//g;
        $description = basename($description);
    }

    # trigger content-type auto detection

    Bugzilla->input_params->{'contenttypemethod'} = 'autodetect';

    # add attachment

    my $attachment = Bugzilla::Attachment->create({
        bug => $bug,
        creation_ts => $timestamp,
        data => $data,
        description => $description,
        filename => $params->{filename},
        mimetype => $params->{content_type},
    });

    # add comment

    $bug->add_comment('', {
        isprivate => 0,
        type => CMT_ATTACHMENT_CREATED,
        extra_data => $attachment->id,
    });
}

sub _post_bug_hook {
    my ($self, $bug) = @_;

    # trigger post_bug_after_creation hook

    my $vars = {
        id => $bug->bug_id,
        bug => $bug,
    };
    Bugzilla::Hook::process('post_bug_after_creation', { vars => $vars });
}

sub _send_mail {
    my ($self, $bug, $user) = @_;

    # send new-bug email

    Bugzilla::BugMail::Send($bug->bug_id, { changer => $user });
}

sub _delete_token {
    my ($self, $token) = @_;
    my $dbh = Bugzilla->dbh;

    # delete token

    trick_taint($token);
    $dbh->do('DELETE FROM tell_us_more WHERE token=?', undef, $token);
}

1;

