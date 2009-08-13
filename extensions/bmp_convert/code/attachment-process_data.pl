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
# Contributor(s): Frédéric Buclin <LpSolit@gmail.com>

use strict;

use Image::Magick;
use Bugzilla;

my $args = Bugzilla->hook_args;
return unless $args->{attributes}->{mimetype} eq 'image/bmp';

my $data = ${$args->{data}};
my $img = Image::Magick->new(magick=>'bmp');

# $data is a filehandle.
if (ref $data) {
    $img->Read(file => \*$data);
    $img->set(magick=>'png');
    $img->Write(file => \*$data);
}
# $data is a blob.
else {
    $img->BlobToImage($data);
    $img->set(magick=>'png');
    $data = $img->ImageToBlob();
}

${$args->{data}} = $data;
$args->{attributes}->{mimetype} = 'image/png';
$args->{attributes}->{filename} =~ s/^(.+)\.bmp$/$1.png/i;
undef $img;
