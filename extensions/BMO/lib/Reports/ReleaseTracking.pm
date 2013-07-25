# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BMO::Reports::ReleaseTracking;
use strict;
use warnings;

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Extension::BMO::Util;
use Bugzilla::Field;
use Bugzilla::FlagType;
use Bugzilla::Util qw(correct_urlbase trick_taint);
use JSON qw(-convert_blessed_universally);
use List::MoreUtils qw(uniq);

sub report {
    my ($vars) = @_;
    my $dbh = Bugzilla->dbh;
    my $input = Bugzilla->input_params;
    my $user = Bugzilla->user;

    my @flag_names = qw(
        approval-mozilla-release
        approval-mozilla-beta
        approval-mozilla-aurora
        approval-mozilla-central
        approval-comm-release
        approval-comm-beta
        approval-comm-aurora
        approval-calendar-release
        approval-calendar-beta
        approval-calendar-aurora
        approval-mozilla-esr10
    );

    my @flags_json;
    my @fields_json;
    my @products_json;

    #
    # tracking flags
    #

    my $all_products = $user->get_selectable_products;
    my @usable_products;

    # build list of flags and their matching products

    my @invalid_flag_names;
    foreach my $flag_name (@flag_names) {
        # grab all matching flag_types
        my @flag_types = @{Bugzilla::FlagType::match({ name => $flag_name, is_active => 1 })};

        # remove invalid flags
        if (!@flag_types) {
            push @invalid_flag_names, $flag_name;
            next;
        }

        # we need a list of products, based on inclusions/exclusions
        my @products;
        my %flag_types;
        foreach my $flag_type (@flag_types) {
            $flag_types{$flag_type->name} = $flag_type->id;
            my $has_all = 0;
            my @exclusion_ids;
            my @inclusion_ids;
            foreach my $flag_type (@flag_types) {
                if (scalar keys %{$flag_type->inclusions}) {
                    my $inclusions = $flag_type->inclusions;
                    foreach my $key (keys %$inclusions) {
                        push @inclusion_ids, ($inclusions->{$key} =~ /^(\d+)/);
                    }
                } elsif (scalar keys %{$flag_type->exclusions}) {
                    my $exclusions = $flag_type->exclusions;
                    foreach my $key (keys %$exclusions) {
                        push @exclusion_ids, ($exclusions->{$key} =~ /^(\d+)/);
                    }
                } else {
                    $has_all = 1;
                    last;
                }
            }

            if ($has_all) {
                push @products, @$all_products;
            } elsif (scalar @exclusion_ids) {
                push @products, @$all_products;
                foreach my $exclude_id (uniq @exclusion_ids) {
                    @products = grep { $_->id != $exclude_id } @products;
                }
            } else {
                foreach my $include_id (uniq @inclusion_ids) {
                    push @products, grep { $_->id == $include_id } @$all_products;
                }
            }
        }
        @products = uniq @products;
        push @usable_products, @products;
        my @product_ids = map { $_->id } sort { lc($a->name) cmp lc($b->name) } @products;

        push @flags_json, {
            name => $flag_name,
            id => $flag_types{$flag_name} || 0,
            products => \@product_ids,
            fields => [],
        };
    }
    foreach my $flag_name (@invalid_flag_names) {
        @flag_names = grep { $_ ne $flag_name } @flag_names;
    }
    @usable_products = uniq @usable_products;

    # build a list of tracking flags for each product
    # also build the list of all fields

    my @unlink_products;
    foreach my $product (@usable_products) {
        my @fields =
            grep { is_active_status_field($_) }
            Bugzilla->active_custom_fields({ product => $product });
        my @field_ids = map { $_->id } @fields;
        if (!scalar @fields) {
            push @unlink_products, $product;
            next;
        }

        # product
        push @products_json, {
            name => $product->name,
            id => $product->id,
            fields => \@field_ids,
        };

        # add fields to flags
        foreach my $rh (@flags_json) {
            if (grep { $_ eq $product->id } @{$rh->{products}}) {
                push @{$rh->{fields}}, @field_ids;
            }
        }

        # add fields to fields_json
        foreach my $field (@fields) {
            my $existing = 0;
            foreach my $rh (@fields_json) {
                if ($rh->{id} == $field->id) {
                    $existing = 1;
                    last;
                }
            }
            if (!$existing) {
                push @fields_json, {
                    name => $field->name,
                    id => $field->id,
                };
            }
        }
    }
    foreach my $rh (@flags_json) {
        my @fields = uniq @{$rh->{fields}};
        $rh->{fields} = \@fields;
    }

    # remove products which aren't linked with status fields

    foreach my $rh (@flags_json) {
        my @product_ids;
        foreach my $id (@{$rh->{products}}) {
            unless (grep { $_->id == $id } @unlink_products) {
                push @product_ids, $id;
            }
            $rh->{products} = \@product_ids;
        }
    }

    #
    # rapid release dates
    #

    my @ranges;
    my $start_date = string_to_datetime('2011-08-16');
    my $end_date = $start_date->clone->add(weeks => 6)->add(days => -1);
    my $now_date = string_to_datetime('2012-11-19');

    while ($start_date <= $now_date) {
        unshift @ranges, {
            value => sprintf("%s-%s", $start_date->ymd(''), $end_date->ymd('')),
            label => sprintf("%s and %s", $start_date->ymd('-'), $end_date->ymd('-')),
        };

        $start_date = $end_date->clone;;
        $start_date->add(days => 1);
        $end_date->add(weeks => 6);
    }

    # 2012-11-20 - 2013-01-06 was a 7 week release cycle instead of 6
    $start_date = string_to_datetime('2012-11-20');
    $end_date = $start_date->clone->add(weeks => 7)->add(days => -1);
    unshift @ranges, {
        value => sprintf("%s-%s", $start_date->ymd(''), $end_date->ymd('')),
        label => sprintf("%s and %s", $start_date->ymd('-'), $end_date->ymd('-')),
    };

    # Back on track with 6 week releases
    $start_date = string_to_datetime('2013-01-08');
    $end_date = $start_date->clone->add(weeks => 6)->add(days => -1);
    $now_date = time_to_datetime((time));

    while ($start_date <= $now_date) {
        unshift @ranges, {
            value => sprintf("%s-%s", $start_date->ymd(''), $end_date->ymd('')),
            label => sprintf("%s and %s", $start_date->ymd('-'), $end_date->ymd('-')),
        };

        $start_date = $end_date->clone;;
        $start_date->add(days => 1);
        $end_date->add(weeks => 6);
    }

    push @ranges, {
        value => '*',
        label => 'Anytime',
    };

    #
    # run report
    #

    if ($input->{q} && !$input->{edit}) {
        my $q = _parse_query($input->{q});

        my @where;
        my @params;
        my $query = "
            SELECT DISTINCT b.bug_id
              FROM bugs b
                   INNER JOIN flags f ON f.bug_id = b.bug_id ";

        if ($q->{start_date}) {
            $query .= "INNER JOIN bugs_activity a ON a.bug_id = b.bug_id ";
        }

        if (grep($_ == FIELD_TYPE_EXTENSION, map { $_->{type} } @{ $q->{fields} })) {
            $query .= "LEFT JOIN tracking_flags_bugs AS tfb ON tfb.bug_id = b.bug_id " .
                      "LEFT JOIN tracking_flags AS tf ON tfb.tracking_flag_id = tf.id ";
        }

        $query .= "WHERE ";

        if ($q->{start_date}) {
            push @where, "(a.fieldid = ?)";
            push @params, $q->{field_id};

            push @where, "(a.bug_when >= ?)";
            push @params, $q->{start_date} . ' 00:00:00';
            push @where, "(a.bug_when < ?)";
            push @params, $q->{end_date} . ' 00:00:00';

            push @where, "(a.added LIKE ?)";
            push @params, '%' . $q->{flag_name} . $q->{flag_status} . '%';
        }

        push @where, "(f.type_id IN (SELECT id FROM flagtypes WHERE name = ?))";
        push @params, $q->{flag_name};

        push @where, "(f.status = ?)";
        push @params, $q->{flag_status};

        if ($q->{product_id}) {
            push @where, "(b.product_id = ?)";
            push @params, $q->{product_id};
        }

        if (scalar @{$q->{fields}}) {
            my @fields;
            foreach my $field (@{$q->{fields}}) {
                my $field_sql = "(" . ($field->{value} eq '+' ? '' : '!') . "(";
                if ($field->{type} == FIELD_TYPE_EXTENSION) {
                    $field_sql .= "tf.name = " . $dbh->quote($field->{name}) . " AND tfb.value";
                }
                else {
                    $field_sql .= "b." . $field->{name};
                }
                $field_sql .= " IN ('fixed','verified')))";
                push(@fields, $field_sql);
            }
            my $join = uc $q->{join};
            push @where, '(' . join(" $join ", @fields) . ')';
        }

        $query .= join("\nAND ", @where);

        if ($input->{debug}) {
            print "Content-Type: text/plain\n\n";
            $query =~ s/\?/\000/g;
            foreach my $param (@params) {
                $query =~ s/\000/$param/;
            }
            print "$query\n";
            exit;
        }

        my $bugs = $dbh->selectcol_arrayref($query, undef, @params);
        push @$bugs, 0 unless @$bugs;

        my $urlbase = correct_urlbase();
        my $cgi = Bugzilla->cgi;
        print $cgi->redirect(
            -url => "${urlbase}buglist.cgi?bug_id=" . join(',', @$bugs)
        );
        exit;
    }

    #
    # set template vars
    #

    my $json = JSON->new();
    if (0) {
        # debugging
        $json->shrink(0);
        $json->canonical(1);
        $vars->{flags_json} = $json->pretty->encode(\@flags_json);
        $vars->{products_json} = $json->pretty->encode(\@products_json);
        $vars->{fields_json} = $json->pretty->encode(\@fields_json);
    } else {
        $json->shrink(1);
        $vars->{flags_json} = $json->encode(\@flags_json);
        $vars->{products_json} = $json->encode(\@products_json);
        $vars->{fields_json} = $json->encode(\@fields_json);
    }

    $vars->{flag_names} = \@flag_names;
    $vars->{ranges} = \@ranges;
    $vars->{default_query} = $input->{q};
    foreach my $field (qw(product flags range)) {
        $vars->{$field} = $input->{$field};
    }
}

sub _parse_query {
    my $q = shift;
    my @query = split(/:/, $q);
    my $query;

    # field_id for flag changes
    $query->{field_id} = get_field_id('flagtypes.name');

    # flag_name
    my $flag_name = shift @query;
    @{Bugzilla::FlagType::match({ name => $flag_name, is_active => 1 })}
        or ThrowUserError('report_invalid_parameter', { name => 'flag_name' });
    trick_taint($flag_name);
    $query->{flag_name} = $flag_name;

    # flag_status
    my $flag_status = shift @query;
    $flag_status =~ /^([\?\-\+])$/
        or ThrowUserError('report_invalid_parameter', { name => 'flag_status' });
    $query->{flag_status} = $1;

    # date_range -> from_ymd to_ymd
    my $date_range = shift @query;
    if ($date_range ne '*') {
        $date_range =~ /^(\d\d\d\d)(\d\d)(\d\d)-(\d\d\d\d)(\d\d)(\d\d)$/
            or ThrowUserError('report_invalid_parameter', { name => 'date_range' });
        $query->{start_date} = "$1-$2-$3";
        $query->{end_date} = "$4-$5-$6";
    }

    # product_id
    my $product_id = shift @query;
    $product_id =~ /^(\d+)$/
        or ThrowUserError('report_invalid_parameter', { name => 'product_id' });
    $query->{product_id} = $1;

    # join
    my $join = shift @query;
    $join =~ /^(and|or)$/
        or ThrowUserError('report_invalid_parameter', { name => 'join' });
    $query->{join} = $1;

    # fields
    my @fields;
    foreach my $field (@query) {
        $field =~ /^(\d+)([\-\+])$/
            or ThrowUserError('report_invalid_parameter', { name => 'fields' });
        my ($id, $value) = ($1, $2);
        my $field_obj = Bugzilla::Field->new($id)
            or ThrowUserError('report_invalid_parameter', { name => 'field_id' });
        push @fields, { id => $id, value => $value,
                        name => $field_obj->name, type => $field_obj->type };
    }
    $query->{fields} = \@fields;

    return $query;
}

1;
