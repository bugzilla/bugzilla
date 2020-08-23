package ExtUtils::Helpers::Unix;
$ExtUtils::Helpers::Unix::VERSION = '0.026';
use strict;
use warnings FATAL => 'all';

use Exporter 5.57 'import';
our @EXPORT = qw/make_executable detildefy/;

use Carp qw/croak/;
use Config;

my $layer = $] >= 5.008001 ? ":raw" : "";

sub make_executable {
	my $filename = shift;
	my $current_mode = (stat $filename)[2] + 0;
	if (-T $filename) {
		open my $fh, "<$layer", $filename;
		my @lines = <$fh>;
		if (@lines and $lines[0] =~ s{ \A \#! \s* (?:/\S+/)? perl \b (.*) \z }{$Config{startperl}$1}xms) {
			open my $out, ">$layer", "$filename.new" or croak "Couldn't open $filename.new: $!";
			print $out @lines;
			close $out;
			rename $filename, "$filename.bak" or croak "Couldn't rename $filename to $filename.bak";
			rename "$filename.new", $filename or croak "Couldn't rename $filename.new to $filename";
			unlink "$filename.bak";
		}
	}
	chmod $current_mode | oct(111), $filename;
	return;
}

sub detildefy {
	my $value = shift;
	# tilde with optional username
	for ($value) {
		s{ ^ ~ (?= /|$)}          [ $ENV{HOME} || (getpwuid $>)[7] ]ex or # tilde without user name
		s{ ^ ~ ([^/]+) (?= /|$) } { (getpwnam $1)[7] || "~$1" }ex;        # tilde with user name
	}
	return $value;
}

1;

# ABSTRACT: Unix specific helper bits

__END__

=pod

=encoding UTF-8

=head1 NAME

ExtUtils::Helpers::Unix - Unix specific helper bits

=head1 VERSION

version 0.026

=for Pod::Coverage make_executable
split_like_shell
detildefy

=head1 AUTHORS

=over 4

=item *

Ken Williams <kwilliams@cpan.org>

=item *

Leon Timmermans <leont@cpan.org>

=back

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2004 by Ken Williams, Leon Timmermans.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
