#!/usr/bin/env perl
use 5.10.1;
use strict;
use warnings;

my ($repo, $user, $pass)
  = check_env(qw(DOCKERHUB_REPO DOCKER_USER DOCKER_PASS));
run("docker", "login", "-u", $user, "-p", $pass);

my @docker_tags = ($ENV{CIRCLE_SHA1});

if ($ENV{CIRCLE_TAG}) {
  push @docker_tags, $ENV{CIRCLE_TAG};
}
elsif ($ENV{CIRCLE_BRANCH}) {
  if ($ENV{CIRCLE_BRANCH} eq 'master') {
    push @docker_tags, 'latest';
  }
  else {
    push @docker_tags, $ENV{CIRCLE_BRANCH};
  }
}

say "Pushing tags...";
say "  $_" for @docker_tags;
foreach my $tag (@docker_tags) {
  run("docker", "tag", "bmo", "$repo:$tag");
  run("docker", "push", "$repo:$tag");
}

sub run {
  my (@cmd) = @_;
  my $rv = system(@cmd);
  exit 1 if $rv != 0;
}

sub check_env {
  my (@missing, @found);
  foreach my $name (@_) {
    push @missing, $name unless $ENV{$name};
    push @found, $ENV{$name};
  }

  if (@missing) {
    warn "Missing environmental variables: ", join(", ", @missing), "\n";
    exit;
  }
  return @found;
}


