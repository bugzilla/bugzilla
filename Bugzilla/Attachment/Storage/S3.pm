# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Attachment::Storage::S3;

use 5.10.1;
use Moo;

use Bugzilla::Error;
use Bugzilla::S3;

with 'Bugzilla::Attachment::Storage::Base';

has 's3'     => (is => 'ro', lazy => 1);
has 'bucket' => (is => 'ro', lazy => 1);

sub _build_s3 {
  my $self = shift;
  $self->{s3} ||= Bugzilla::S3->new({
    aws_access_key_id     => Bugzilla->params->{aws_access_key_id},
    aws_secret_access_key => Bugzilla->params->{aws_secret_access_key},
    secure                => 1,
  });
  return $self->{s3};
}

sub _build_bucket {
  my $self = shift;
  $self->{bucket} ||= $self->s3->bucket(Bugzilla->params->{s3_bucket});
  return $self->bucket;
}

sub data_type { return 's3'; }

sub set_data {
  my ($self, $data) = @_;
  my $attach_id = $self->attachment->id;

  # If the attachment is larger than attachment_s3_minsize,
  # we instead store it in the database.
  if (Bugzilla->params->{attachment_s3_minsize}
    && $self->attachment->datasize < Bugzilla->params->{attachment_s3_minsize})
  {
    require Bugzilla::Attachment::Storage::Database;
    return Bugzilla::Attachment::Storage::Database->new({attachment => $self->attachment})
      ->set_data($data);
  }

  unless ($self->bucket->add_key($attach_id, $data)) {
    warn "Failed to add attachment $attach_id to S3: "
      . $self->bucket->errstr . "\n";
    ThrowCodeError('s3_add_failed',
      {attach_id => $attach_id, reason => $self->bucket->errstr});
  }

  return $self;
}

sub get_data {
  my ($self)    = @_;
  my $attach_id = $self->attachment->id;
  my $response  = $self->bucket->get_key($attach_id);
  if (!$response) {
    warn "Failed to retrieve attachment $attach_id from S3: "
      . $self->bucket->errstr . "\n";
    ThrowCodeError('s3_get_failed',
      {attach_id => $attach_id, reason => $self->bucket->errstr});
  }
  return $response->{value};
}

sub remove_data {
  my ($self) = @_;
  my $attach_id = $self->attachment->id;
  $self->bucket->delete_key($attach_id)
    or warn "Failed to remove attachment $attach_id from S3: "
    . $self->bucket->errstr . "\n";
  return $self;
}

sub data_exists {
  my ($self) = @_;
  return !!$self->bucket->head_key($self->attachment->id);
}

1;
