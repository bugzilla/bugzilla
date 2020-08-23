package App::cpm;
use strict;
use warnings;

our $VERSION = '0.993';
our ($GIT_DESCRIBE, $GIT_URL);

1;
__END__

=encoding utf-8

=head1 NAME

App::cpm - a fast CPAN module installer

=head1 SYNOPSIS

  > cpm install Module

=head1 DESCRIPTION

=for html
<a href="https://skaji.github.io/images/cpm-Plack.svg"><img src="https://skaji.github.io/images/cpm-Plack.svg" alt="demo" style="max-width:100%;"></a>

cpm is a fast CPAN module installer, which uses L<Menlo> in parallel.

Moreover cpm keeps the each builds of distributions in your home directory,
and reuses them later.
That is, if prebuilts are available, cpm never builds distributions again, just copies the prebuilts into an appropriate directory.
This is (of course!) inspired by L<Carmel>.

For tutorial, check out L<App::cpm::Tutorial>.

=head1 MOTIVATION

Why do we need a new CPAN client?

I used L<cpanm> a lot, and it's totally awesome.

But if your Perl project has hundreds of CPAN module dependencies,
then it takes quite a lot of time to install them.

So my motivation is simple: I want to install CPAN modules as fast as possible.

=head2 HOW FAST?

Just an example:

  > time cpanm -nq -Lextlib Plack
  real 0m47.705s

  > time cpm install Plack
  real 0m16.629s

This shows cpm is 3x faster than cpanm.

=head1 CAVEATS

L<eserte|https://github.com/skaji/cpm/issues/71> reported that
the parallel feature of cpm yielded a new type of failure for CPAN module installation.
That is,
if B<ModuleA> implicitly requires B<ModuleB> in configure/build phase,
and B<ModuleB> is about to be installed,
then it may happen that the installation of B<ModuleA> fails.

I can say that it hardly happens especially if you use a new Perl.
Moreover, for a workaround, cpm automatically retries the installation if it fails.

I hope that
if almost all CPAN modules are distributed with L<static install enabled|http://blogs.perl.org/users/shoichi_kaji1/2017/03/make-your-cpan-module-static-installable.html>,
then cpm will parallelize the installation for these CPAN modules safely and we can eliminate this new type of failure completely.

=head1 ROADMAP

If you all find cpm useful,
then cpm should be merged into cpanm 2.0. How exciting!

To merge cpm into cpanm, there are several TODOs:

=over 4

=item * (DONE) Win32? - support platforms that do not have fork(2) system call

=item * (DONE) Logging? - the parallel feature makes log really messy

=back

Your feedback is highly appreciated.

=head1 COPYRIGHT AND LICENSE

Copyright 2015 Shoichi Kaji E<lt>skaji@cpan.orgE<gt>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Perl Advent Calendar 2015|http://www.perladvent.org/2015/2015-12-02.html>

L<App::cpanminus>

L<Menlo>

L<Carton>

L<Carmel>

=cut
