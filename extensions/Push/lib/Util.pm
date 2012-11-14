# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Util;

use strict;
use warnings;

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Util qw(datetime_from trim);
use Data::Dumper;
use Encode;
use JSON ();
use Scalar::Util qw(blessed);
use Time::HiRes;

use base qw(Exporter);
our @EXPORT = qw(
    datetime_to_timestamp
    debug_dump
    get_first_value
    hash_undef_to_empty
    is_public
    mapr
    clean_error
    change_set_id
    canon_email
    to_json from_json
);

# returns true if the specified object is public
sub is_public {
    my ($object) = @_;

    my $default_user = Bugzilla::User->new();

    if ($object->isa('Bugzilla::Bug')) {
        return unless $default_user->can_see_bug($object->bug_id);
        return 1;

    } elsif ($object->isa('Bugzilla::Comment')) {
        return if $object->is_private;
        return unless $default_user->can_see_bug($object->bug_id);
        return 1;

    } elsif ($object->isa('Bugzilla::Attachment')) {
        return if $object->isprivate;
        return unless $default_user->can_see_bug($object->bug_id);
        return 1;

    } else {
        warn "Unsupported class " . blessed($object) . " passed to is_public()\n";
    }

    return 1;
}

# return the first existing value from the hashref for the given list of keys
sub get_first_value {
    my ($rh, @keys) = @_;
    foreach my $field (@keys) {
        return $rh->{$field} if exists $rh->{$field};
    }
    return;
}

# wrapper for map that works on array references
sub mapr(&$) {
    my ($filter, $ra) = @_;
    my @result = map(&$filter, @$ra);
    return \@result;
}


# convert datetime string (from db) to a UTC json friendly datetime
sub datetime_to_timestamp {
    my ($datetime_string) = @_;
    return '' unless $datetime_string;
    return datetime_from($datetime_string, 'UTC')->datetime();
}

# replaces all undef values in a hashref with an empty string (deep)
sub hash_undef_to_empty {
    my ($rh) = @_;
    foreach my $key (keys %$rh) {
        my $value = $rh->{$key};
        if (!defined($value)) {
            $rh->{$key} = '';
        } elsif (ref($value) eq 'HASH') {
            hash_undef_to_empty($value);
        }
    }
}

# debugging methods
sub debug_dump {
    my ($object) = @_;
    local $Data::Dumper::Sortkeys = 1;
    my $output = Dumper($object);
    $output =~ s/</&lt;/g;
    print "<pre>$output</pre>";
}

# removes stacktrace and "at /some/path ..." from errors
sub clean_error {
    my ($error) = @_;
    my $path = bz_locations->{'extensionsdir'};
    $error = $1 if $error =~ /^(.+?) at \Q$path/s;
    $path = '/loader/0x';
    $error = $1 if $error =~ /^(.+?) at \Q$path/s;
    $error =~ s/(^\s+|\s+$)//g;
    return $error;
}

# generate a new change_set id
sub change_set_id {
    return "$$." . Time::HiRes::time();
}

# remove guff from email addresses
sub clean_email {
    my $email = shift;
    $email = trim($email);
    $email = $1 if $email =~ /^(\S+)/;
    $email =~ s/&#64;/@/;
    $email = lc $email;
    return $email;
}

# resolve to canonised email form
# eg. glob+bmo@mozilla.com --> glob@mozilla.com
sub canon_email {
    my $email = shift;
    $email = clean_email($email);
    $email =~ s/^([^\+]+)\+[^\@]+(\@.+)$/$1$2/;
    return $email;
}

# json helpers
sub to_json {
    my ($object, $pretty) = @_;
    if ($pretty) {
        return decode('utf8', JSON->new->utf8(1)->pretty(1)->encode($object));
    } else {
        return JSON->new->ascii(1)->shrink(1)->encode($object);
    }
}

sub from_json {
    my ($json) = @_;
    if (utf8::is_utf8($json)) {
        $json = encode('utf8', $json);
    }
    return JSON->new->utf8(1)->decode($json);
}

1;
