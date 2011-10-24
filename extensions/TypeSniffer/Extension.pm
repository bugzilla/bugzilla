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
# The Original Code is the TypeSniffer Bugzilla Extension.
#
# The Initial Developer of the Original Code is The Mozilla Foundation.
# Portions created by the Initial Developer are Copyright (C) 2010 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Gervase Markham <gerv@mozilla.org>

package Bugzilla::Extension::TypeSniffer;
use strict;
use base qw(Bugzilla::Extension);

use File::MimeInfo::Magic;
use IO::Scalar;

our $VERSION = '0.02';
################################################################################
# This extension uses magic to guess MIME types for data where the browser has
# told us it's application/octet-stream (probably because there's no file 
# extension, or it's a text type with a non-.txt file extension).
################################################################################
sub attachment_process_data {
    my ($self, $args) = @_;
    my $attributes = $args->{'attributes'};
    my $params = Bugzilla->input_params;
    
    # If we have autodetected application/octet-stream from the Content-Type
    # header, let's have a better go using a sniffer.
    if ($params->{'contenttypemethod'} &&
        $params->{'contenttypemethod'} eq 'autodetect' &&
        $attributes->{'mimetype'} eq 'application/octet-stream') 
    {
        # data is either a filehandle, or the data itself
        my $fh = ${$args->{'data'}};
        if (!ref($fh)) {
            $fh = IO::Scalar->new(\$fh);
        }

        my $mimetype = mimetype($fh);
        if ($mimetype) {
            $attributes->{'mimetype'} = $mimetype;
        }
    }
}

__PACKAGE__->NAME;
