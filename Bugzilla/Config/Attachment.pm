# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Config::Attachment;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Config::Common;

our $sortkey = 400;

sub get_param_list {
  my $class      = shift;
  my @param_list = (
    {name => 'allow_attachment_display',  type => 'b', default => 0},
    {name => 'allow_attachment_deletion', type => 'b', default => 0},
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
    {name => 's3_bucket',             type => 't', default => '',},
    {name => 'aws_access_key_id',     type => 't', default => '',},
    {name => 'aws_secret_access_key', type => 't', default => '',},
  );
  return @param_list;
}

sub check_params {
  my ($class, $params) = @_;
  return '' unless $params->{attachment_storage} eq 's3';

  if ( $params->{s3_bucket} eq ''
    || $params->{aws_access_key_id} eq ''
    || $params->{aws_secret_access_key} eq '')
  {
    return
      "You must set s3_bucket, aws_access_key_id, and aws_secret_access_key when attachment_storage is set to S3";
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
