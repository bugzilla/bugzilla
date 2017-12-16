# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BMO::Reports::ReleaseTracking;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Extension::BMO::Util;
use Bugzilla::Field;
use Bugzilla::FlagType;
use Bugzilla::Util qw(trick_taint validate_date);
use JSON qw(-convert_blessed_universally);
use List::MoreUtils qw(uniq);

use constant DATE_RANGES => [
    {
        value => '20160126-20160307',
        label => '2016-01-26 and 2016-03-07'
    },
    {
        value => '20151215-20160125',
        label => '2015-12-15 and 2016-01-25'
    },
    {
        value => '20151103-20151214',
        label => '2015-11-03 and 2015-12-14'
    },
    {
        value => '20150922-20151102',
        label => '2015-09-22 and 2015-11-02'
    },
    {
        value => '20150811-20150921',
        label => '2015-08-11 and 2015-09-21'
    },
    {
        value => '20150630-20150810',
        label => '2015-06-30 and 2015-08-10'
    },
    {
        value => '20150512-20150629',
        label => '2015-05-12 and 2015-06-29'
    },
    {
        value => '20150331-20150511',
        label => '2015-03-31 and 2015-05-11'
    },
    {
        value => '20150224-20150330',
        label => '2015-02-24 and 2015-03-30'
    },
    {
        value => '20150113-20150223',
        label => '2015-01-13 and 2015-02-23'
    },
    {
        value => '20141111-20141222',
        label => '2014-11-11 and 2014-12-22'
    },
    {
        value => '20140930-20141110',
        label => '2014-09-30 and 2014-11-10'
    },
    {
        value => '20140819-20140929',
        label => '2014-08-19 and 2014-09-29'
    },
    {
        value => '20140708-20140818',
        label => '2014-07-08 and 2014-08-18'
    },
    {
        value => '20140527-20140707',
        label => '2014-05-27 and 2014-07-07'
    },
    {
        value => '20140415-20140526',
        label => '2014-04-15 and 2014-05-26'
    },
    {
        value => '20140304-20140414',
        label => '2014-03-04 and 2014-04-14'
    },
    {
        value => '20140121-20140303',
        label => '2014-01-21 and 2014-03-03'
    },
    {
        value => '20131210-20140120',
        label => '2013-12-10 and 2014-01-20'
    },
    {
        value => '20131029-20131209',
        label => '2013-10-29 and 2013-12-09'
    },
    {
        value => '20130917-20131028',
        label => '2013-09-17 and 2013-10-28'
    },
    {
        value => '20130806-20130916',
        label => '2013-08-06 and 2013-09-16'
    },
    {
        value => '20130625-20130805',
        label => '2013-06-25 and 2013-08-05'
    },
    {
        value => '20130514-20130624',
        label => '2013-05-14 and 2013-06-24'
    },
    {
        value => '20130402-20130513',
        label => '2013-04-02 and 2013-05-13'
    },
    {
        value => '20130219-20130401',
        label => '2013-02-19 and 2013-04-01'
    },
    {
        value => '20130108-20130218',
        label => '2013-01-08 and 2013-02-18'
    },
    {
        value => '20121120-20130107',
        label => '2012-11-20 and 2013-01-07'
    },
    {
        value => '20121009-20121119',
        label => '2012-10-09 and 2012-11-19'
    },
    {
        value => '20120828-20121008',
        label => '2012-08-28 and 2012-10-08'
    },
    {
        value => '20120717-20120827',
        label => '2012-07-17 and 2012-08-27'
    },
    {
        value => '20120605-20120716',
        label => '2012-06-05 and 2012-07-16'
    },
    {
        value => '20120424-20120604',
        label => '2012-04-24 and 2012-06-04'
    },
    {
        value => '20120313-20120423',
        label => '2012-03-13 and 2012-04-23'
    },
    {
        value => '20120131-20120312',
        label => '2012-01-31 and 2012-03-12'
    },
    {
        value => '20111220-20120130',
        label => '2011-12-20 and 2012-01-30'
    },
    {
        value => '20111108-20111219',
        label => '2011-11-08 and 2011-12-19'
    },
    {
        value => '20110927-20111107',
        label => '2011-09-27 and 2011-11-07'
    },
    {
        value => '20110816-20110926',
        label => '2011-08-16 and 2011-09-26'
    },
    {
        value => '*',
        label => 'Anytime'
    }
];

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
            sort { $a->sortkey <=> $b->sortkey }
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
                    desc => $field->description,
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
    # run report
    #

    if ($input->{q} && !$input->{edit}) {
        my $q = _parse_query($input->{q});

        my @where;
        my @params;
        my $query = "
            SELECT DISTINCT b.bug_id
              FROM bugs b
                   INNER JOIN flags f ON f.bug_id = b.bug_id\n";

        if ($q->{start_date}) {
            $query .= "INNER JOIN bugs_activity a ON a.bug_id = b.bug_id\n";
        }

        $query .= "WHERE ";

        if ($q->{start_date}) {
            push @where, "(a.fieldid = ?)";
            push @params, $q->{field_id};

            push @where, "(CONVERT_TZ(a.bug_when, 'UTC', 'America/Los_Angeles') >= ?)";
            push @params, $q->{start_date} . ' 00:00:00';
            push @where, "(CONVERT_TZ(a.bug_when, 'UTC', 'America/Los_Angeles') <= ?)";
            push @params, $q->{end_date} . ' 23:59:59';

            push @where, "(a.added LIKE ?)";
            push @params, '%' . $q->{flag_name} . $q->{flag_status} . '%';
        }

        my ($type_id) = $dbh->selectrow_array(
            "SELECT id FROM flagtypes WHERE name = ?",
            undef,
            $q->{flag_name}
        );
        push @where, "(f.type_id = ?)";
        push @params, $type_id;

        push @where, "(f.status = ?)";
        push @params, $q->{flag_status};

        if ($q->{product_id}) {
            push @where, "(b.product_id = ?)";
            push @params, $q->{product_id};
        }

        if (scalar @{$q->{fields}}) {
            my @fields;
            foreach my $field (@{$q->{fields}}) {
                my $field_sql = "(";
                if ($field->{type} == FIELD_TYPE_EXTENSION) {
                    $field_sql .= "
                        COALESCE(
                            (SELECT tracking_flags_bugs.value
                               FROM tracking_flags_bugs
                                    LEFT JOIN tracking_flags
                                         ON tracking_flags.id = tracking_flags_bugs.tracking_flag_id
                              WHERE tracking_flags_bugs.bug_id = b.bug_id
                                    AND tracking_flags.name = " . $dbh->quote($field->{name}) . ")
                        , '') ";
                }
                else {
                    $field_sql .= "b." . $field->{name};
                }
                $field_sql .= " " . ($field->{value} eq '+' ? '' : 'NOT ') . "IN ('fixed','verified'))";
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
                $query =~ s/\000/'$param'/;
            }
            print "$query\n";
            exit;
        }

        my $bugs = $dbh->selectcol_arrayref($query, undef, @params);
        push @$bugs, 0 unless @$bugs;

        my $urlbase = Bugzilla->localconfig->{urlbase};
        my $cgi = Bugzilla->cgi;
        print $cgi->redirect(
            -url => "${urlbase}buglist.cgi?bug_id=" . join(',', @$bugs)
        );
        exit;
    }

    #
    # set template vars
    #

    my $json = JSON->new()->shrink(1);
    $vars->{flags_json} = $json->encode(\@flags_json);
    $vars->{products_json} = $json->encode(\@products_json);
    $vars->{fields_json} = $json->encode(\@fields_json);
    $vars->{flag_names} = \@flag_names;
    $vars->{ranges} = DATE_RANGES;
    $vars->{default_query} = $input->{q};
    $vars->{is_custom} = $input->{is_custom};
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
        validate_date($query->{start_date})
          || ThrowUserError('illegal_date', { date   => $query->{start_date},
                                              format => 'YYYY-MM-DD' });
        validate_date($query->{end_date})
          || ThrowUserError('illegal_date', { date   => $query->{end_date},
                                              format => 'YYYY-MM-DD' });
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
