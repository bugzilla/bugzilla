# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# The Initial Developer of the Original Code is Netscape Communications
# Corporation. Portions created by Netscape are
# Copyright (C) 1998 Netscape Communications Corporation. All
# Rights Reserved.
#
# Contributor(s): Terry Weissman <terry@mozilla.org>
#                 Dawn Endico <endico@mozilla.org>
#                 Dan Mosedale <dmose@mozilla.org>
#                 Joe Robins <jmrobins@tgix.com>
#                 Jacob Steenhagen <jake@bugzilla.org>
#                 J. Paul Reed <preed@sigkill.com>
#                 Bradley Baetz <bbaetz@student.usyd.edu.au>
#                 Joseph Heenan <joseph@heenan.me.uk>
#                 Erik Stambaugh <erik@dasbistro.com>
#                 Frédéric Buclin <LpSolit@gmail.com>
#

package Bugzilla::Config::Attachment;

use strict;

use Bugzilla::Config::Common;

our $sortkey = 400;

sub get_param_list {
    my $class = shift;
    my @param_list = (
        {
            name    => 'allow_attachment_display',
            type    => 'b',
            default => 0
        },
        {
            name    => 'attachment_base',
            type    => 't',
            default => '',
            checker => \&check_urlbase
        },
        {
            name    => 'allow_attachment_deletion',
            type    => 'b',
            default => 0
        },
        {
            name    => 'maxattachmentsize',
            type    => 't',
            default => '1000',
            checker => \&check_maxattachmentsize
        },
        {
            name    => 'attachment_storage',
            type    => 's',
            choices => ['database', 'filesystem', 's3'],
            default => 'database',
            checker => \&check_storage
        },
        {
            name    => 's3_bucket',
            type    => 't',
            default => '',
        },
        {
            name    => 'aws_access_key_id',
            type    => 't',
            default => '',
        },
        {
            name    => 'aws_secret_access_key',
            type    => 't',
            default => '',
        },
    );
    return @param_list;
}

sub check_params {
    my ($class, $params) = @_;
    return unless $params->{attachment_storage} eq 's3';

    if ($params->{s3_bucket} eq ''
        || $params->{aws_access_key_id} eq ''
        || $params->{aws_secret_access_key} eq ''
    ) {
        return "You must set s3_bucket, aws_access_key_id, and aws_secret_access_key when attachment_storage is set to S3";
    }
    return '';
}

sub check_storage {
    my ($value, $param) = (@_);
    my $check_multi = check_multi($value, $param);
    return $check_multi if $check_multi;

    if ($value eq 's3') {
        return Bugzilla->feature('s3')
            ? ''
            : 'The perl modules required for S3 support are not installed';
    }
    else {
        return '';
    }
}

1;
