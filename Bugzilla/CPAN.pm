# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::CPAN;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Constants qw(bz_locations);
use Bugzilla::Install::Requirements qw(check_cpan_feature);

BEGIN {
    my $json_xs_ok = eval {
        require JSON::XS;
        require JSON;
        JSON->VERSION("2.5");
        1;
    };
    if ($json_xs_ok) {
        $ENV{PERL_JSON_BACKEND} = 'JSON::XS';
    }
}

use constant _CAN_HAS_FEATURE => eval {
    require CPAN::Meta::Prereqs;
    require CPAN::Meta::Requirements;
    require Module::Metadata;
    require Module::Runtime;
    CPAN::Meta::Prereqs->VERSION('2.132830');
    CPAN::Meta::Requirements->VERSION('2.121');
    Module::Metadata->VERSION('1.000019');
    1;
};

my (%FEATURE, %FEATURE_LOADED);

sub cpan_meta {
    my ($class) = @_;
    my $dir  = bz_locations()->{libpath};
    my $file = File::Spec->catfile($dir, 'MYMETA.json');
    state $CPAN_META;

    return $CPAN_META if $CPAN_META;

    if (-f $file) {
        open my $meta_fh, '<', $file or die "unable to open $file: $!";
        my $str = do { local $/ = undef; scalar <$meta_fh> };
        # detaint
        $str =~ /^(.+)$/s; $str = $1;
        close $meta_fh;

        return $CPAN_META = CPAN::Meta->load_json_string($str);
    }
    else {
        require Bugzilla::Error;
        Bugzilla::Error::ThrowCodeError('cpan_meta_missing');
    }
}

sub cpan_requirements {
    my ($class, $prereqs) = @_;
    if ($prereqs->can('merged_requirements')) {
        return $prereqs->merged_requirements( [ 'configure', 'runtime' ], ['requires'] );
    }
    else {
        my $req = CPAN::Meta::Requirements->new;
        $req->add_requirements( $prereqs->requirements_for('configure', 'requires') );
        $req->add_requirements( $prereqs->requirements_for('runtime', 'requires') );
        return $req;
    }
}

sub has_feature {
    my ($class, $feature_name) = @_;

    return 0 unless _CAN_HAS_FEATURE;
    return $FEATURE{$feature_name} if exists $FEATURE{ $feature_name };

    my $meta = $class->cpan_meta;
    my $feature = eval { $meta->feature($feature_name) };
    unless ($feature) {
        require Bugzilla::Error;
        Bugzilla::Error::ThrowCodeError('invalid_feature', { feature => $feature_name });
    }

    return $FEATURE{$feature_name} = check_cpan_feature($feature)->{ok};
}


# Bugzilla expects this will also load all the modules.. so we have to do that.
# Later we should put a deprecation warning here, and favor calling has_feature().
sub feature {
    my ($class, $feature_name) = @_;
    return 0 unless _CAN_HAS_FEATURE;
    return 1 if $FEATURE_LOADED{$feature_name};
    return 0 unless $class->has_feature($feature_name);

    my $meta = $class->cpan_meta;
    my $feature = $meta->feature($feature_name);
    my @modules = $feature->prereqs->merged_requirements(['runtime'], ['requires'])->required_modules;
    Module::Runtime::require_module($_) foreach @modules;
    return $FEATURE_LOADED{$feature_name} = 1;
}

sub preload_features {
    my ($class) = @_;
    return 0 unless _CAN_HAS_FEATURE;
    my $meta = $class->cpan_meta;

    foreach my $feature ($meta->features) {
        next if $feature->identifier eq 'mod_perl';
        $class->feature($feature->identifier);
    }
}

1;

__END__


=head1 NAME

Bugzilla::CPAN - Methods relating to Bugzilla's CPAN metadata (including features)

=head1 SYNOPSIS

  use Bugzilla;
  Bugzilla->cpan_meta;
  Bugzilla->feature('psgi');
  Bugzilla->has_feature('psgi');

=head1 DESCRIPTION

You most likely never need to use this module directly, as the Bugzilla factory class inherits all of these class methods.
It exists so that cpan metadata can be read in before the rest of Bugzilla.pm is loaded in checksetup.pl

=head1 CLASS METHODS

=head2 C<feature>

Wrapper around C<has_feature()> that also loads all of required modules into the runtime.

=head2 C<has_feature>

Consults F<MYMETA.yml> for optional Bugzilla features and returns true if all the requirements
are installed.

=head2 C<cpan_meta>

Returns a L<CPAN::Meta> from the contents of MYMETA.json in the bugzilla directory.

=head2 C<preload_features()>

Attempts to load all features.
