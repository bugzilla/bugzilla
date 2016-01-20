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
# The Initial Developer of the Original Code is Frédéric Buclin.
# Portions created by Frédéric Buclin are Copyright (C) 2009
# Frédéric Buclin. All Rights Reserved.
#
# Contributor(s): 
#   Frédéric Buclin <LpSolit@gmail.com>
#   Max Kanat-Alexander <mkanat@bugzilla.org>

package Bugzilla::Extension::BmpConvert;
use strict;
use base qw(Bugzilla::Extension);

use Image::Magick;
use File::Temp qw(:seekable);
use File::stat qw(stat);

our $VERSION = '1.0';

sub attachment_process_data {
    my ($self, $args) = @_;

    return unless $args->{attributes}->{mimetype} eq 'image/bmp';
    eval {
        _try_convert_bmp_to_png($args);
    };
    warn $@ if $@;
}


# Here be dragons:
# Image::Magick uses dualvars extensively to signal errors.
# The documentation is either confusing or wrong in this regard.
# This is not a great practice. dualvar(0, "foo") is a true value,
# but dualvar(0, "foo") + 0 is not.
# Also dualvar(1, "") is a false value, but dualvar(1, "") > 0 is true.
#
# "When a scalar has both string and numeric components (dualvars), Perl
# prefers to check the string component for boolean truth."
# From https://github.com/chromatic/modern_perl_book/blob/master/sections/coercion.pod
sub _try_convert_bmp_to_png {
    my ($args) = @_;

    my $data = ${$args->{data}};
    my $img = Image::Magick->new(magick => 'bmp');
    my $size;

    if (ref $data) {
        my $read_error = $img->Read(file => \*$data);

        # rewind so it can be read in again by other code
        seek($data, 0, SEEK_SET);

        die "Error reading in BMP: $read_error"
          if $read_error;

        $img->set(magick => 'png');

        my $tmp = File::Temp->new(UNLINK => 1, SUFFIX => '.png');
        my $write_error = $img->Write(file => $tmp);

        die "Error converting BMP to PNG: $write_error"
          if $write_error;

        $tmp->flush;
        $size = stat($tmp->filename)->size;
        die "Error converting BMP to PNG results in empty file"
          if $size == 0;

        $tmp->seek(0, SEEK_SET);
        $data = $tmp;
    }
    else {
        my $parse_error = $img->BlobToImage($data);
        die "Error parsing in BMP: $parse_error"
          if $parse_error;

        $img->set(magick => 'png');
        $data = $img->ImageToBlob();

        die "Error converting BMP to PNG (empty PNG)"
          unless length($data) > 0;

        $size = length($data);
    }

    ${$args->{data}} = $data;
    $args->{attributes}->{mimetype} = 'image/png';
    $args->{attributes}->{filename} =~ s/\.bmp$/.png/i;
    $args->{attributes}->{attach_size} = $size;
}

 __PACKAGE__->NAME;
