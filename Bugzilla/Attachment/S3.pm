# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Attachment::S3;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Error;
use Bugzilla::S3;

sub new {
  my $s3 = Bugzilla::S3->new({
    aws_access_key_id     => Bugzilla->params->{aws_access_key_id},
    aws_secret_access_key => Bugzilla->params->{aws_secret_access_key},
    secure                => 1,
  });
  return
    bless({s3 => $s3, bucket => $s3->bucket(Bugzilla->params->{s3_bucket}),},
    shift);
}

sub store {
  my ($self, $attach_id, $data) = @_;
  unless ($self->{bucket}->add_key($attach_id, $data)) {
    warn "Failed to add attachment $attach_id to S3: "
      . $self->{bucket}->errstr . "\n";
    ThrowCodeError('s3_add_failed',
      {attach_id => $attach_id, reason => $self->{bucket}->errstr});
  }
}

sub retrieve {
  my ($self, $attach_id) = @_;
  my $response = $self->{bucket}->get_key($attach_id);
  if (!$response) {
    warn "Failed to retrieve attachment $attach_id from S3: "
      . $self->{bucket}->errstr . "\n";
    ThrowCodeError('s3_get_failed',
      {attach_id => $attach_id, reason => $self->{bucket}->errstr});
  }
  return $response->{value};
}

sub remove {
  my ($self, $attach_id) = @_;
  $self->{bucket}->delete_key($attach_id)
    or warn "Failed to remove attachment $attach_id from S3: "
    . $self->{bucket}->errstr . "\n";
}

sub exists {
  my ($self, $attach_id) = @_;
  return !!$self->{bucket}->head_key($attach_id);
}

1;
