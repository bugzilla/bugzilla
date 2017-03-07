#!/usr/bin/perl
use strict;
use warnings;
use Bugzilla;
use JSON '-convert_blessed_universally';

print JSON->new->pretty->encode(
    Bugzilla::Elastic::Search->new(
        quicksearch => "@ARGV",
        fields => ['bug_id', 'short_desc'],
        order => ['bug_id'],
    )->es_query
);
