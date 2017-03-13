# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Elastic::Indexer;

use 5.10.1;
use Moo;
use List::MoreUtils qw(natatime);
use Storable qw(dclone);
use namespace::clean;

with 'Bugzilla::Elastic::Role::HasClient';
with 'Bugzilla::Elastic::Role::HasIndexName';

has 'mtime' => (
    is      => 'lazy',
    clearer => 'clear_mtime',
);

has 'shadow_dbh' => ( is => 'lazy' );

has 'debug_sql' => (
    is => 'ro',
    default => 0,
);

has 'progress_bar' => (
    is        => 'ro',
    predicate => 'has_progress_bar',
);

sub create_index {
    my ($self) = @_;
    my $indices = $self->client->indices;

    $indices->create(
        index => $self->index_name,
        body => {
            settings => {
                number_of_shards => 1,
                analysis => {
                    analyzer => {
                        folding => {
                            type      => 'standard',
                            tokenizer => 'standard',
                            filter    => [ 'lowercase', 'asciifolding' ]
                        },
                        bz_text_analyzer => {
                            type             => 'standard',
                            filter           => ['lowercase', 'stop'],
                            max_token_length => '20'
                        },
                        bz_substring_analyzer => {
                            type      => 'custom',
                            filter    => ['lowercase'],
                            tokenizer => 'bz_ngram_tokenizer',
                        },
                        bz_equals_analyzer => {
                            type   => 'custom',
                            filter => ['lowercase'],
                            tokenizer => 'keyword',
                        },
                        whiteboard_words => {
                            type => 'custom',
                            tokenizer => 'whiteboard_words_pattern',
                            filter => ['stop']
                        },
                        whiteboard_shingle_words => {
                            type => 'custom',
                            tokenizer => 'whiteboard_words_pattern',
                            filter => ['stop', 'shingle']
                        },
                        whiteboard_tokens => {
                            type => 'custom',
                            tokenizer => 'whiteboard_tokens_pattern',
                            filter => ['stop']
                        },
                        whiteboard_shingle_tokens => {
                            type => 'custom',
                            tokenizer => 'whiteboard_tokens_pattern',
                            filter => ['stop', 'shingle']
                        }
                    },
                    tokenizer => {
                        bz_ngram_tokenizer => {
                            type => 'nGram',
                            min_ngram => 2,
                            max_ngram => 25,
                        },
                        whiteboard_tokens_pattern => {
                            type => 'pattern',
                            pattern => '\\s*([,;]*\\[|\\][\\s\\[]*|[;,])\\s*'
                        },
                        whiteboard_words_pattern => {
                            type => 'pattern',
                            pattern => '[\\[\\];,\\s]+'
                        },
                    },
                },
            },
        }
    ) unless $indices->exists(index => $self->index_name);
}

sub _bulk_helper {
    my ($self, $class) = @_;

    return $self->client->bulk_helper(
        index => $self->index_name,
        type  => $class->ES_TYPE,
    );
}

sub find_largest_mtime {
    my ($self, $class) = @_;

    my $result = $self->client->search(
        index => $self->index_name,
        type  => $class->ES_TYPE,
        body  => {
            aggs => { es_mtime => { extended_stats => { field => 'es_mtime' } } },
            size => 0
        }
    );

    return $result->{aggregations}{es_mtime}{max};
}

sub find_largest_id {
    my ($self, $class) = @_;

    my $result = $self->client->search(
        index => $self->index_name,
        type  => $class->ES_TYPE,
        body  => {
            aggs => { $class->ID_FIELD => { extended_stats => { field => $class->ID_FIELD } } },
            size => 0
        }
    );

    return $result->{aggregations}{$class->ID_FIELD}{max};
}

sub put_mapping {
    my ($self, $class) = @_;

    my %body = ( properties => scalar $class->ES_PROPERTIES );
    if ($class->does('Bugzilla::Elastic::Role::ChildObject')) {
        $body{_parent} = { type => $class->ES_PARENT_TYPE };
    }

    $self->client->indices->put_mapping(
        index => $self->index_name,
        type => $class->ES_TYPE,
        body => \%body,
    );
}

sub _debug_sql {
    my ($self, $sql, $params) = @_;
    if ($self->debug_sql) {
        my ($out, @args) = ($sql, $params ? (@$params) : ());
        $out =~ s/^\n//gs;
        $out =~ s/^\s{8}//gm;
        $out =~ s/\?/Bugzilla->dbh->quote(shift @args)/ge;
        warn $out, "\n";
    }

    return ($sql, $params)
}

sub bulk_load {
    my ( $self, $class ) = @_;

    $self->put_mapping($class);
    my $bulk = $self->_bulk_helper($class);
    my $ids  = $self->_select_all_ids($class);
    $self->clear_mtime;
    $self->_bulk_load_ids($bulk, $class, $ids) if @$ids;
    undef $ids; # free up some memory

    my $updated_ids = $self->_select_updated_ids($class);
    if ($updated_ids) {
        $self->_bulk_load_ids($bulk, $class, $updated_ids) if @$updated_ids;
    }
}

sub _select_all_ids {
    my ($self, $class) = @_;

    my $dbh     = Bugzilla->dbh;
    my $last_id = $self->find_largest_id($class);
    my ($sql, $params) = $self->_debug_sql($class->ES_SELECT_ALL_SQL($last_id));
    return $dbh->selectcol_arrayref($sql, undef, @$params);
}

sub _select_updated_ids {
    my ($self, $class) = @_;

    my $dbh   = Bugzilla->dbh;
    my $mtime = $self->find_largest_mtime($class);
    if ($mtime && $mtime != $self->mtime) {
        my ($updated_sql, $updated_params) = $self->_debug_sql($class->ES_SELECT_UPDATED_SQL($mtime));
        return $dbh->selectcol_arrayref($updated_sql, undef, @$updated_params);
    } else {
        return undef;
    }
}

sub bulk_load_ids {
    my ($self, $class, $ids) = @_;

    $self->put_mapping($class);
    $self->clear_mtime;
    $self->_bulk_load_ids($self->_bulk_helper($class), $class, $ids);
}

sub _bulk_load_ids {
    my ($self, $bulk, $class, $all_ids) = @_;

    my $iter  = natatime $class->ES_OBJECTS_AT_ONCE, @$all_ids;
    my $mtime = $self->mtime;
    my $progress_bar;
    my $next_update;

    if ($self->has_progress_bar) {
        my $name = (split(/::/, $class))[-1];
        $progress_bar = $self->progress_bar->new({
            name  => $name,
            count => scalar @$all_ids,
            ETA   => 'linear'
        });
        $progress_bar->message(sprintf "loading %d $class objects, %d at a time", scalar @$all_ids, $class->ES_OBJECTS_AT_ONCE);
        $next_update = $progress_bar->update(0);
        $progress_bar->max_update_rate(1);
    }

    my $total = 0;
    use Time::HiRes;
    my $start = time;
    while (my @ids = $iter->()) {
        if ($progress_bar) {
            $total += @ids;
            if ($total >= $next_update) {
                $next_update = $progress_bar->update($total);
                my $duration = time - $start || 1;
            }
        }

        my $objects = $class->new_from_list(\@ids);
        foreach my $object (@$objects) {
            my %doc = (
                id     => $object->id,
                source => scalar $object->es_document($mtime),
            );

            if ($class->does('Bugzilla::Elastic::Role::ChildObject')) {
                $doc{parent} = $object->es_parent_id;
            }

            $bulk->index(\%doc);
        }
        Bugzilla->_cleanup();
    }

    $bulk->flush;
}

sub _build_shadow_dbh { Bugzilla->switch_to_shadow_db }

sub _build_mtime {
    my ($self) = @_;
    my ($mtime) = $self->shadow_dbh->selectrow_array("SELECT UNIX_TIMESTAMP(NOW())");
    return $mtime;
}

1;
