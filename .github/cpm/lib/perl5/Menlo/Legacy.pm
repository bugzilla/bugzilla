package Menlo::Legacy;

use strict;
our $VERSION = '1.9022';

1;
__END__

=encoding utf-8

=head1 NAME

Menlo::Legacy - Legacy internal and client support for Menlo

=head1 DESCRIPTION

Menlo::Legacy is a package to install L<Menlo::CLI::Compat> which is a
compatibility library that implements the classic version of cpanminus
internals and behavios. This is so that existing users of cpanm and
API clients such as L<Carton>, L<Carmel> and L<App::cpm>) can rely on
the stable features and specific behaviors of cpanm.

This way Menlo can evolve and be refactored without the fear of
breaking any downstream clients, including C<cpanm> itself.

=head1 AUTHOR

Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt>

=head1 COPYRIGHT

Copyright 2018- Tatsuhiko Miyagawa

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Menlo::CLI::Compat>

=cut
