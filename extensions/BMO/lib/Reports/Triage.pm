# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BMO::Reports::Triage;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Component;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Product;
use Bugzilla::User;
use Bugzilla::Util qw(detaint_natural trim url_quote);
use Date::Parse;

use JSON::XS;
use List::MoreUtils qw(any);

# set an upper limit on the *unfiltered* number of bugs to process
use constant MAX_NUMBER_BUGS => 4000;

use constant DEFAULT_OWNER_PRODUCTS => (
    'Core',
    'Firefox',
    'Firefox for Android',
    'Firefox for iOS',
    'Toolkit',
);

sub unconfirmed {
    my ($vars, $filter) = @_;
    my $dbh = Bugzilla->dbh;
    my $input = Bugzilla->input_params;
    my $user = Bugzilla->user;

    if (exists $input->{'action'} && $input->{'action'} eq 'run' && $input->{'product'}) {

        # load product and components from input

        my $product = Bugzilla::Product->new({ name => $input->{'product'} })
            || ThrowUserError('invalid_object', { object => 'Product', value => $input->{'product'} });

        my @component_ids;
        if ($input->{'component'} ne '') {
            my $ra_components = ref($input->{'component'})
                ? $input->{'component'} : [ $input->{'component'} ];
            foreach my $component_name (@$ra_components) {
                my $component = Bugzilla::Component->new({ name => $component_name, product => $product })
                    || ThrowUserError('invalid_object', { object => 'Component', value => $component_name });
                push @component_ids, $component->id;
            }
        }

        # determine which comment filters to run

        my $filter_commenter = $input->{'filter_commenter'};
        my $filter_commenter_on = $input->{'commenter'};
        my $filter_last = $input->{'filter_last'};
        my $filter_last_period = $input->{'last'};

        if (!$filter_commenter || $filter_last) {
            $filter_commenter = '1';
            $filter_commenter_on = 'reporter';
        }

        my $filter_commenter_id;
        if ($filter_commenter && $filter_commenter_on eq 'is') {
            Bugzilla::User::match_field({ 'commenter_is' => {'type' => 'single'} });
            my $user = Bugzilla::User->new({ name => $input->{'commenter_is'} })
                || ThrowUserError('invalid_object', { object => 'User', value => $input->{'commenter_is'} });
            $filter_commenter_id = $user ? $user->id : 0;
        }

        my $filter_last_time;
        if ($filter_last) {
            if ($filter_last_period eq 'is') {
                $filter_last_period = -1;
                $filter_last_time = str2time($input->{'last_is'} . " 00:00:00") || 0;
            } else {
                detaint_natural($filter_last_period);
                    $filter_last_period = 14 if $filter_last_period < 14;
            }
        }

        # form sql queries

        my $now = (time);
        my $bugs_sql = "
              SELECT bug_id, short_desc, reporter, creation_ts
                FROM bugs
               WHERE product_id = ?
                     AND bug_status = 'UNCONFIRMED'";
        if (@component_ids) {
            $bugs_sql .= " AND component_id IN (" . join(',', @component_ids) . ")";
        }
        $bugs_sql .= "
            ORDER BY creation_ts
        ";

        my $comment_count_sql = "
            SELECT COUNT(*)
              FROM longdescs
             WHERE bug_id = ?
        ";

        my $comment_sql = "
              SELECT who, bug_when, type, thetext, extra_data
                FROM longdescs
               WHERE bug_id = ?
        ";
        if (!Bugzilla->user->is_insider) {
            $comment_sql .= " AND isprivate = 0 ";
        }
        $comment_sql .= "
            ORDER BY bug_when DESC
               LIMIT 1
        ";

        my $attach_sql = "
            SELECT description, isprivate
              FROM attachments
             WHERE attach_id = ?
        ";

        # work on an initial list of bugs

        my $list = $dbh->selectall_arrayref($bugs_sql, undef, $product->id);
        my @bugs;

        # this can be slow to process, resulting in 'service unavailable' errors from zeus
        # so if too many bugs are returned, throw an error

        if (scalar(@$list) > MAX_NUMBER_BUGS) {
            ThrowUserError('report_too_many_bugs');
        }

        foreach my $entry (@$list) {
            my ($bug_id, $summary, $reporter_id, $creation_ts) = @$entry;

            next unless $user->can_see_bug($bug_id);

            # get last comment information

            my ($comment_count) = $dbh->selectrow_array($comment_count_sql, undef, $bug_id);
            my ($commenter_id, $comment_ts, $type, $comment, $extra)
                = $dbh->selectrow_array($comment_sql, undef, $bug_id);
            my $commenter = 0;

            # apply selected filters

            if ($filter_commenter) {
                next if $comment_count <= 1;

                if ($filter_commenter_on eq 'reporter') {
                    next if $commenter_id != $reporter_id;

                } elsif ($filter_commenter_on eq 'noconfirm') {
                    $commenter = Bugzilla::User->new({ id => $commenter_id, cache => 1 });
                    next if $commenter_id != $reporter_id
                        || $commenter->in_group('canconfirm');

                } elsif ($filter_commenter_on eq 'is') {
                    next if $commenter_id != $filter_commenter_id;
                }
            } else {
                $input->{'commenter'} = '';
                $input->{'commenter_is'} = '';
            }

            if ($filter_last) {
                my $comment_time = str2time($comment_ts)
                    or next;
                if ($filter_last_period == -1) {
                    next if $comment_time >= $filter_last_time;
                } else {
                    next if $now - $comment_time <= 60 * 60 * 24 * $filter_last_period;
                }
            } else {
                $input->{'last'} = '';
                $input->{'last_is'} = '';
            }

            # get data for attachment comments

            if ($comment eq '' && $type == CMT_ATTACHMENT_CREATED) {
                my ($description, $is_private) = $dbh->selectrow_array($attach_sql, undef, $extra);
                next if $is_private && !Bugzilla->user->is_insider;
                $comment = "(Attachment) " . $description;
            }

            # truncate long comments

            if (length($comment) > 80) {
                $comment = substr($comment, 0, 80) . '...';
            }

            # build bug hash for template

            my $bug = {};
            $bug->{id}            = $bug_id;
            $bug->{summary}       = $summary;
            $bug->{reporter}      = Bugzilla::User->new({ id => $reporter_id, cache => 1 });
            $bug->{creation_ts}   = $creation_ts;
            $bug->{commenter}     = $commenter || Bugzilla::User->new({ id => $commenter_id, cache => 1 });
            $bug->{comment_ts}    = $comment_ts;
            $bug->{comment}       = $comment;
            $bug->{comment_count} = $comment_count;
            push @bugs, $bug;
        }

        @bugs = sort { $b->{comment_ts} cmp $a->{comment_ts} } @bugs;

        $vars->{bugs} = \@bugs;
    } else {
        $input->{action} = '';
    }

    if (!$input->{filter_commenter} && !$input->{filter_last}) {
        $input->{filter_commenter} = 1;
    }

    $vars->{'input'} = $input;
}

sub owners {
    my ($vars, $filter) = @_;
    my $dbh   = Bugzilla->dbh;
    my $input = Bugzilla->input_params;
    my $user  = Bugzilla->user;

    Bugzilla::User::match_field({ 'owner' => {'type' => 'multi'}  });

    my @products;
    if (!$input->{product} && $input->{owner}) {
        @products = @{ $user->get_selectable_products };
    }
    else {
        my @product_names = $input->{product} ? ($input->{product}) : DEFAULT_OWNER_PRODUCTS;
        foreach my $name (@product_names) {
            push(@products, Bugzilla::Product->check({ name => $name }));
        }
    }

    my @component_ids;
    if (@products == 1 && $input->{'component'}) {
        my $ra_components = ref($input->{'component'})
                            ? $input->{'component'}
                            : [ $input->{'component'} ];
        foreach my $component_name (@$ra_components) {
            my $component = Bugzilla::Component->check({ name => $component_name, product => $products[0] });
            push @component_ids, $component->id;
        }
    }

    my @owner_names = split(/[,;]+/, $input->{owner}) if $input->{owner};
    my @owner_ids;
    foreach my $name (@owner_names) {
        $name = trim($name);
        next unless $name;
        push(@owner_ids, login_to_id($name, THROW_ERROR));
    }

    my $sql = "SELECT products.name, components.name, components.id, components.triage_owner_id
               FROM components JOIN products ON components.product_id = products.id
               WHERE products.id IN (" . join(',', map { $_->id } @products) . ")";
    if (@component_ids) {
        $sql .= " AND components.id IN (" . join(',', @component_ids) . ")";
    }
    if (@owner_ids) {
        $sql .= " AND components.triage_owner_id IN (" . join(',', @owner_ids) . ")";
    }
    $sql .= " ORDER BY products.name, components.name";

    my $rows = $dbh->selectall_arrayref($sql);

    my $bug_count_sth = $dbh->prepare("
        SELECT COUNT(bugs.bug_id)
        FROM   bugs INNER JOIN components AS map_component ON bugs.component_id = map_component.id
               INNER JOIN bug_status AS map_bug_status ON bugs.bug_status = map_bug_status.value
               INNER JOIN priority AS map_priority ON bugs.priority = map_priority.value
        WHERE  bugs.resolution IN ('')
                AND bugs.priority IN ('--')
                AND bugs.creation_ts >= '2016-06-01'
                AND (NOT( EXISTS (
                    SELECT 1
                    FROM   bugs bugs_1
                           LEFT JOIN attachments AS attachments_1 ON bugs_1.bug_id = attachments_1.bug_id
                           LEFT JOIN flags AS flags_1 ON bugs_1.bug_id = flags_1.bug_id AND (flags_1.attach_id = attachments_1.attach_id OR flags_1.attach_id IS NULL)
                           LEFT JOIN flagtypes AS flagtypes_1 ON flags_1.type_id = flagtypes_1.id
                    WHERE  bugs_1.bug_id = bugs.bug_id AND CONCAT(flagtypes_1.name, flags_1.status) = 'needinfo?')))
                AND bugs.component_id = ?");

    my @results;
    foreach my $row (@$rows) {
        my ($product_name, $component_name, $component_id, $triage_owner_id) = @$row;
        my $triage_owner = $triage_owner_id
                           ? Bugzilla::User->new({ id => $triage_owner_id, cache => 1 })
                           : "";
        my $data = {
            product     => $product_name,
            component   => $component_name,
            owner       => $triage_owner,
        };
        $data->{buglist_url} = 'priority=--&resolution=---&f1=creation_ts&o1=greaterthaneq&v1=2016-06-01'.
                               '&f2=flagtypes.name&o2=notequals&v2=needinfo%3F';
        if ($triage_owner) {
            $data->{buglist_url} .= '&f3=triage_owner&o3=equals&v3=' . url_quote($triage_owner->login);
        }
        $bug_count_sth->execute($component_id);
        ($data->{bug_count}) = $bug_count_sth->fetchrow_array();
        push @results, $data;
    }
    $vars->{results} = \@results;

    my $json_data = { products => [] };
    foreach my $product (@{ $user->get_selectable_products }) {
        my $prod_data = {
            name        => $product->name,
            components  => [],
        };
        foreach my $component (@{ $product->components }) {
            my $selected = 0;
            if ($input->{product}
                && $input->{product} eq $product->name
                && $input->{component})
            {
                $selected = 1 if (ref $input->{component} && any { $_ eq $component->name } @{ $input->{component} });
                $selected = 1 if (!ref $input->{componet} && $input->{component} eq $component->name);
            }
            my $comp_data = {
                name     => $component->name,
                selected => $selected
            };
            push(@{ $prod_data->{components} }, $comp_data);
        }
        push(@{ $json_data->{products} }, $prod_data);
    }

    $vars->{product}   = $input->{product};
    $vars->{owner}     = $input->{owner};
    $vars->{json_data} = encode_json($json_data);
}

1;
