# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# The Initial Developer of the Original Code is Netscape Communications
# Corporation. Portions created by Netscape are
# Copyright (C) 1998 Netscape Communications Corporation. All
# Rights Reserved.
#
# Contributor(s): Gervase Markham <gerv@gerv.net>
#                 Terry Weissman <terry@mozilla.org>
#                 Dan Mosedale <dmose@mozilla.org>
#                 Stephan Niemz <st.n@gmx.net>
#                 Andreas Franke <afranke@mathweb.org>
#                 Myk Melez <myk@mozilla.org>
#                 Michael Schindler <michael@compressconsult.com>
#                 Max Kanat-Alexander <mkanat@bugzilla.org>
#                 Joel Peshkin <bugreport@peshkin.net>
#                 Lance Larsh <lance.larsh@oracle.com>
#                 Jesse Clark <jjclark1982@gmail.com>
#                 Rémi Zara <remi_zara@mac.com>
#                 Reed Loden <reed@reedloden.com>

use strict;

package Bugzilla::Search;
use base qw(Exporter);
@Bugzilla::Search::EXPORT = qw(
    EMPTY_COLUMN

    IsValidQueryType
    split_order_term
    translate_old_column
);

use Bugzilla::Error;
use Bugzilla::Util;
use Bugzilla::Constants;
use Bugzilla::Group;
use Bugzilla::User;
use Bugzilla::Field;
use Bugzilla::Status;
use Bugzilla::Keyword;

use Data::Dumper;
use Date::Format;
use Date::Parse;
use List::MoreUtils qw(all part uniq);
use Storable qw(dclone);

# Description Of Boolean Charts
# -----------------------------
#
# A boolean chart is a way of representing the terms in a logical
# expression.  Bugzilla builds SQL queries depending on how you enter
# terms into the boolean chart. Boolean charts are represented in
# urls as three-tuples of (chart id, row, column). The query form
# (query.cgi) may contain an arbitrary number of boolean charts where
# each chart represents a clause in a SQL query.
#
# The query form starts out with one boolean chart containing one
# row and one column.  Extra rows can be created by pressing the
# AND button at the bottom of the chart.  Extra columns are created
# by pressing the OR button at the right end of the chart. Extra
# charts are created by pressing "Add another boolean chart".
#
# Each chart consists of an arbitrary number of rows and columns.
# The terms within a row are ORed together. The expressions represented
# by each row are ANDed together. The expressions represented by each
# chart are ANDed together.
#
#        ----------------------
#        | col2 | col2 | col3 |
# --------------|------|------|
# | row1 |  a1  |  a2  |      |
# |------|------|------|------|  => ((a1 OR a2) AND (b1 OR b2 OR b3) AND (c1))
# | row2 |  b1  |  b2  |  b3  |
# |------|------|------|------|
# | row3 |  c1  |      |      |
# -----------------------------
#
#        --------
#        | col2 |
# --------------|
# | row1 |  d1  | => (d1)
# ---------------
#
# Together, these two charts represent a SQL expression like this
# SELECT blah FROM blah WHERE ( (a1 OR a2)AND(b1 OR b2 OR b3)AND(c1)) AND (d1)
#
# The terms within a single row of a boolean chart are all constraints
# on a single piece of data.  If you're looking for a bug that has two
# different people cc'd on it, then you need to use two boolean charts.
# This will find bugs with one CC matching 'foo@blah.org' and and another
# CC matching 'bar@blah.org'.
#
# --------------------------------------------------------------
# CC    | equal to
# foo@blah.org
# --------------------------------------------------------------
# CC    | equal to
# bar@blah.org
#
# If you try to do this query by pressing the AND button in the
# original boolean chart then what you'll get is an expression that
# looks for a single CC where the login name is both "foo@blah.org",
# and "bar@blah.org". This is impossible.
#
# --------------------------------------------------------------
# CC    | equal to
# foo@blah.org
# AND
# CC    | equal to
# bar@blah.org
# --------------------------------------------------------------


#############
# Constants #
#############

# If you specify a search type in the boolean charts, this describes
# which operator maps to which internal function here.
use constant OPERATORS => {
    equals         => \&_simple_operator,
    notequals      => \&_simple_operator,
    casesubstring  => \&_casesubstring,
    substring      => \&_substring,
    substr         => \&_substring,
    notsubstring   => \&_notsubstring,
    regexp         => \&_regexp,
    notregexp      => \&_notregexp,
    lessthan       => \&_simple_operator,
    lessthaneq     => \&_simple_operator,
    matches        => sub { ThrowUserError("search_content_without_matches"); },
    notmatches     => sub { ThrowUserError("search_content_without_matches"); },
    greaterthan    => \&_simple_operator,
    greaterthaneq  => \&_simple_operator,
    anyexact       => \&_anyexact,
    anywordssubstr => \&_anywordsubstr,
    allwordssubstr => \&_allwordssubstr,
    nowordssubstr  => \&_nowordssubstr,
    anywords       => \&_anywords,
    allwords       => \&_allwords,
    nowords        => \&_nowords,
    changedbefore  => \&_changedbefore_changedafter,
    changedafter   => \&_changedbefore_changedafter,
    changedfrom    => \&_changedfrom_changedto,
    changedto      => \&_changedfrom_changedto,
    changedby      => \&_changedby,
};

# Some operators are really just standard SQL operators, and are
# all implemented by the _simple_operator function, which uses this
# constant.
use constant SIMPLE_OPERATORS => {
    equals        => '=',
    notequals     => '!=',
    greaterthan   => '>',
    greaterthaneq => '>=',
    lessthan      => '<',
    lessthaneq    => "<=",
};

# Most operators just reverse by removing or adding "not" from/to them.
# However, some operators reverse in a different way, so those are listed
# here.
use constant OPERATOR_REVERSE => {
    nowords        => 'anywords',
    nowordssubstr  => 'anywordssubstr',
    anywords       => 'nowords',
    anywordssubstr => 'nowordssubstr',
    lessthan       => 'greaterthaneq',
    lessthaneq     => 'greaterthan',
    greaterthan    => 'lessthaneq',
    greaterthaneq  => 'lessthan',
    # The following don't currently have reversals:
    # casesubstring, anyexact, allwords, allwordssubstr
};

use constant OPERATOR_FIELD_OVERRIDE => {
    
    # User fields
    'attachments.submitter' => {
        _default => \&_attachments_submitter,
    },
    assigned_to => {
        _non_changed => \&_contact_nonchanged,
    },
    cc => {
        _non_changed => \&_cc_nonchanged,
    },
    commenter => {
        _default => \&_commenter,
    },
    reporter => {
        _non_changed => \&_contact_nonchanged,
    },
    'requestees.login_name' => {
        _default => \&_requestees_login_name,
    },
    'setters.login_name' => {
        _default => \&_setters_login_name,    
    },    
    qa_contact => {
        _non_changed => \&_qa_contact_nonchanged,
    },
    
    # General Bug Fields
    alias => {
        _non_changed => \&_alias_nonchanged,
    },
    'attach_data.thedata' => {
        _non_changed => \&_attach_data_thedata,
    },
    # We check all attachment fields against this.
    'attachments' => {
        _non_changed => \&_attachments,
    },
    blocked => {
        _non_changed => \&_blocked_nonchanged,
    },
    bug_group => {
        _non_changed => \&_bug_group_nonchanged,
    },
    classification => {
        _non_changed => \&_classification_nonchanged,
    },
    component => {
        _non_changed => \&_component_nonchanged,
    },
    content => {
        matches    => \&_content_matches,
        notmatches => \&_content_matches,
        _default   => sub { ThrowUserError("search_content_without_matches"); },
    },
    days_elapsed => {
        _default => \&_days_elapsed,
    },
    dependson => {
        _non_changed => \&_dependson_nonchanged,
    },
    keywords => {
        equals       => \&_keywords_exact,
        anyexact     => \&_keywords_exact,
        anyword      => \&_keywords_exact,
        allwords     => \&_keywords_exact,

        notequals     => \&_multiselect_negative,
        notregexp     => \&_multiselect_negative,
        notsubstring  => \&_multiselect_negative,
        nowords       => \&_multiselect_negative,
        nowordssubstr => \&_multiselect_negative,

        _non_changed  => \&_keywords_nonchanged,
    },
    'flagtypes.name' => {
        _default => \&_flagtypes_name,
    },    
    longdesc => {
        changedby     => \&_long_desc_changedby,
        changedbefore => \&_long_desc_changedbefore_after,
        changedafter  => \&_long_desc_changedbefore_after,
        _default      => \&_long_desc,
    },
    'longdescs.isprivate' => {
        _default => \&_longdescs_isprivate,
    },
    owner_idle_time => {
        greaterthan   => \&_owner_idle_time_greater_less,
        greaterthaneq => \&_owner_idle_time_greater_less,
        lessthan      => \&_owner_idle_time_greater_less,
        lessthaneq    => \&_owner_idle_time_greater_less,
        _default      => \&_invalid_combination,
    },
    
    product => {
        _non_changed => \&_product_nonchanged,
    },
    
    # Custom multi-select fields
    _multi_select => {
        notequals      => \&_multiselect_negative,
        notregexp      => \&_multiselect_negative,
        notsubstring   => \&_multiselect_negative,
        nowords        => \&_multiselect_negative,
        nowordssubstr  => \&_multiselect_negative,
        
        allwords       => \&_multiselect_multiple,
        allwordssubstr => \&_multiselect_multiple,
        anyexact       => \&_multiselect_multiple,
        
        _non_changed    => \&_multiselect_nonchanged,
    },
    
    # Timetracking Fields
    percentage_complete => {
        _non_changed => \&_percentage_complete,
    },
    work_time => {
        changedby     => \&_work_time_changedby,
        changedbefore => \&_work_time_changedbefore_after,
        changedafter  => \&_work_time_changedbefore_after,
        _default      => \&_work_time,
    },
    
};

# These are fields where special action is taken depending on the
# *value* passed in to the chart, sometimes.
use constant SPECIAL_PARSING => {
    # Pronoun Fields (Ones that can accept %user%, etc.)
    assigned_to => \&_contact_pronoun,
    cc          => \&_cc_pronoun,
    commenter   => \&_commenter_pronoun,
    qa_contact  => \&_contact_pronoun,
    reporter    => \&_contact_pronoun,
    
    # Date Fields that accept the 1d, 1w, 1m, 1y, etc. format.
    creation_ts => \&_timestamp_translate,
    deadline    => \&_timestamp_translate,
    delta_ts    => \&_timestamp_translate,
};

# Backwards compatibility for times that we changed the names of fields
# or URL parameters.
use constant FIELD_MAP => {
    bugidtype => 'bug_id_type',
    changedin => 'days_elapsed',
    long_desc => 'longdesc',
};

# A SELECTed expression that we use as a placeholder if somebody selects
# <none> for the X, Y, or Z axis in report.cgi.
use constant EMPTY_COLUMN => '-1';

# A special value that is pushed into charts during _params_to_charts to
# represent that the particular chart we're dealing with should be negated.
use constant NEGATE => 'NOT';

# Some fields are not sorted on themselves, but on other fields. 
# We need to have a list of these fields and what they map to.
use constant SPECIAL_ORDER => {
    'target_milestone' => {
        order => ['map_target_milestone.sortkey','map_target_milestone.value'],
        join  => {
            table => 'milestones',
            from  => 'target_milestone',
            to    => 'value',
            extra => ['bugs.product_id = map_target_milestone.product_id'],
            join  => 'INNER',
        }
    },
};

# Certain columns require other columns to come before them
# in _select_columns, and should be put there if they're not there.
use constant COLUMN_DEPENDS => {
    classification      => ['product'],
    percentage_complete => ['actual_time', 'remaining_time'],
};

# This describes tables that must be joined when you want to display
# certain columns in the buglist. For the most part, Search.pm uses
# DB::Schema to figure out what needs to be joined, but for some
# fields it needs a little help.
use constant COLUMN_JOINS => {
    assigned_to => {
        from  => 'assigned_to',
        to    => 'userid',
        table => 'profiles',
        join  => 'INNER',
    },
    reporter => {
        from  => 'reporter',
        to    => 'userid',
        table => 'profiles',
        join  => 'INNER',
    },
    qa_contact => {
        from  => 'qa_contact',
        to    => 'userid',
        table => 'profiles',
    },
    component => {
        from  => 'component_id',
        to    => 'id',
        table => 'components',
        join  => 'INNER',
    },
    product => {
        from  => 'product_id',
        to    => 'id',
        table => 'products',
        join  => 'INNER',
    },
    classification => {
        table => 'classifications',
        from  => 'map_product.classification_id',
        to    => 'id',
        join  => 'INNER',
    },
    actual_time => {
        table  => 'longdescs',
        join   => 'INNER',
    },
    'flagtypes.name' => {
        as    => 'map_flags',
        table => 'flags',
        extra => ['attach_id IS NULL'],
        then_to => {
            as    => 'map_flagtypes',
            table => 'flagtypes',
            from  => 'map_flags.type_id',
            to    => 'id',
        },
    },
    keywords => {
        table => 'keywords',
        then_to => {
            as    => 'map_keyworddefs',
            table => 'keyworddefs',
            from  => 'map_keywords.keywordid',
            to    => 'id',
        },
    },
};

# This constant defines the columns that can be selected in a query 
# and/or displayed in a bug list.  Column records include the following
# fields:
#
# 1. id: a unique identifier by which the column is referred in code;
#
# 2. name: The name of the column in the database (may also be an expression
#          that returns the value of the column);
#
# 3. title: The title of the column as displayed to users.
# 
# Note: There are a few hacks in the code that deviate from these definitions.
#       In particular, the redundant short_desc column is removed when the
#       client requests "all" columns.
#
# This is really a constant--that is, once it's been called once, the value
# will always be the same unless somebody adds a new custom field. But
# we have to do a lot of work inside the subroutine to get the data,
# and we don't want it to happen at compile time, so we have it as a
# subroutine.
sub COLUMNS {
    my $dbh = Bugzilla->dbh;
    my $cache = Bugzilla->request_cache;
    return $cache->{search_columns} if defined $cache->{search_columns};

    # These are columns that don't exist in fielddefs, but are valid buglist
    # columns. (Also see near the bottom of this function for the definition
    # of short_short_desc.)
    my %columns = (
        relevance            => { title => 'Relevance'  },
        assigned_to_realname => { title => 'Assignee'   },
        reporter_realname    => { title => 'Reporter'   },
        qa_contact_realname  => { title => 'QA Contact' },
    );

    # Next we define columns that have special SQL instead of just something
    # like "bugs.bug_id".
    my $actual_time = '(SUM(map_actual_time.work_time)'
        . ' * COUNT(DISTINCT map_actual_time.bug_when)/COUNT(bugs.bug_id))';
    my %special_sql = (
        deadline    => $dbh->sql_date_format('bugs.deadline', '%Y-%m-%d'),
        actual_time => $actual_time,

        percentage_complete =>
            "(CASE WHEN $actual_time + bugs.remaining_time = 0.0"
              . " THEN 0.0"
              . " ELSE 100"
                   . " * ($actual_time / ($actual_time + bugs.remaining_time))"
              . " END)",

        'flagtypes.name' => $dbh->sql_group_concat('DISTINCT ' 
            . $dbh->sql_string_concat('map_flagtypes.name', 'map_flags.status')),

        'keywords' => $dbh->sql_group_concat('DISTINCT map_keyworddefs.name'),
    );

    # Backward-compatibility for old field names. Goes new_name => old_name.
    # These are here and not in translate_old_column because the rest of the
    # code actually still uses the old names, while the fielddefs table uses
    # the new names (which is not the case for the fields handled by 
    # translate_old_column).
    my %old_names = (
        creation_ts => 'opendate',
        delta_ts    => 'changeddate',
        work_time   => 'actual_time',
    );

    # Fields that are email addresses
    my @email_fields = qw(assigned_to reporter qa_contact);
    # Other fields that are stored in the bugs table as an id, but
    # should be displayed using their name.
    my @id_fields = qw(product component classification);

    foreach my $col (@email_fields) {
        my $sql = "map_${col}.login_name";
        # XXX This needs to be generated inside an accessor instead,
        #     probably, because it should use $self->_user to determine
        #     this, not Bugzilla->user.
        if (!Bugzilla->user->id) {
             $sql = $dbh->sql_string_until($sql, $dbh->quote('@'));
        }
        $special_sql{$col} = $sql;
        $columns{"${col}_realname"}->{name} = "map_${col}.realname";
    }

    foreach my $col (@id_fields) {
        $special_sql{$col} = "map_${col}.name";
    }

    # Do the actual column-getting from fielddefs, now.
    foreach my $field (Bugzilla->get_fields({ obsolete => 0, buglist => 1 })) {
        my $id = $field->name;
        $id = $old_names{$id} if exists $old_names{$id};
        my $sql;
        if (exists $special_sql{$id}) {
            $sql = $special_sql{$id};
        }
        elsif ($field->type == FIELD_TYPE_MULTI_SELECT) {
            $sql = $dbh->sql_group_concat(
                'DISTINCT map_' . $field->name . '.value');
        }
        else {
            $sql = 'bugs.' . $field->name;
        }
        $columns{$id} = { name => $sql, title => $field->description };
    }

    # The short_short_desc column is identical to short_desc
    $columns{'short_short_desc'} = $columns{'short_desc'};

    Bugzilla::Hook::process('buglist_columns', { columns => \%columns });

    $cache->{search_columns} = \%columns;
    return $cache->{search_columns};
}

sub REPORT_COLUMNS {
    my $columns = dclone(COLUMNS);
    # There's no reason to support reporting on unique fields.
    # Also, some other fields don't make very good reporting axises,
    # or simply don't work with the current reporting system.
    my @no_report_columns = 
        qw(bug_id alias short_short_desc opendate changeddate
           flagtypes.name keywords relevance);

    # Multi-select fields are not currently supported.
    my @multi_selects = Bugzilla->get_fields(
        { obsolete => 0, type => FIELD_TYPE_MULTI_SELECT });
    push(@no_report_columns, map { $_->name } @multi_selects);

    # If you're not a time-tracker, you can't use time-tracking
    # columns.
    if (!Bugzilla->user->is_timetracker) {
        push(@no_report_columns, TIMETRACKING_FIELDS);
    }

    foreach my $name (@no_report_columns) {
        delete $columns->{$name};
    }
    return $columns;
}

# These are fields that never go into the GROUP BY on any DB. bug_id
# is here because it *always* goes into the GROUP BY as the first item,
# so it should be skipped when determining extra GROUP BY columns.
use constant GROUP_BY_SKIP => EMPTY_COLUMN, qw(
    actual_time
    bug_id
    flagtypes.name
    keywords
    percentage_complete
);

###############
# Constructor #
###############

# Note that the params argument may be modified by Bugzilla::Search
sub new {
    my $invocant = shift;
    my $class = ref($invocant) || $invocant;
  
    my $self = { @_ };
    bless($self, $class);
    $self->{'user'} ||= Bugzilla->user;
    
    # There are certain behaviors of the CGI "Vars" hash that we don't want.
    # In particular, if you put a single-value arrayref into it, later you
    # get back out a string, which breaks anyexact charts (because they
    # need arrays even for individual items, or we will re-trigger bug 67036).
    #
    # We can't just untie the hash--that would give us a hash with no values.
    # We have to manually copy the hash into a new one, and we have to always
    # do it, because there's no way to know if we were passed a tied hash
    # or not.
    my $params_in = $self->_params;
    my %params = map { $_ => $params_in->{$_} } keys %$params_in;
    $self->{params} = \%params;

    return $self;
}


####################
# Public Accessors #
####################

sub sql {
    my ($self) = @_;
    return $self->{sql} if $self->{sql};
    my $dbh = Bugzilla->dbh;
    
    my ($joins, $having_terms, $where_terms) = $self->_charts_to_conditions();

    my $select = join(', ', $self->_sql_select);
    my $from = $self->_sql_from($joins);
    my $where = $self->_sql_where($where_terms);
    my $group_by = $dbh->sql_group_by($self->_sql_group_by);
    my $having = @$having_terms
                 ? "\nHAVING " . join(' AND ', @$having_terms) : '';
    my $order_by = $self->_sql_order_by
                   ? "\nORDER BY " . join(', ', $self->_sql_order_by) : '';
    
    my $query = <<END;
SELECT $select
  FROM $from
 WHERE $where
$group_by$having$order_by
END
    $self->{sql} = $query;
    return $self->{sql};
}

sub search_description {
    my ($self, $params) = @_;
    my $desc = $self->{'search_description'} ||= [];
    if ($params) {
        push(@$desc, $params);
    }
    # Make sure that the description has actually been generated if
    # people are asking for the whole thing.
    else {
        $self->sql;
    }
    return $self->{'search_description'};
}

######################
# Internal Accessors #
######################

# Fields that are legal for boolean charts of any kind.
sub _chart_fields {
    my ($self) = @_;

    if (!$self->{chart_fields}) {
        my $chart_fields = Bugzilla->fields({ by_name => 1 });

        if (!$self->_user->is_timetracker) {
            foreach my $tt_field (TIMETRACKING_FIELDS) {
                delete $chart_fields->{$tt_field};
            }
        }
        $self->{chart_fields} = $chart_fields;
    }
    return $self->{chart_fields};
}

# There are various places in Search.pm that we need to know the list of
# valid multi-select fields--or really, fields that are stored like
# multi-selects, which includes BUG_URLS fields.
sub _multi_select_fields {
    my ($self) = @_;
    $self->{multi_select_fields} ||= Bugzilla->fields({
        by_name => 1,
        type    => [FIELD_TYPE_MULTI_SELECT, FIELD_TYPE_BUG_URLS]});
    return $self->{multi_select_fields};
}

# $self->{params} contains values that could be undef, could be a string,
# or could be an arrayref. Sometimes we want that value as an array,
# always.
sub _param_array {
    my ($self, $name) = @_;
    my $value = $self->_params->{$name};
    if (!defined $value) {
        return ();
    }
    if (ref($value) eq 'ARRAY') {
        return @$value;
    }
    return ($value);
}

sub _params { $_[0]->{params} }

sub _user { return $_[0]->{user} }

##############################
# Internal Accessors: SELECT #
##############################

# These are the fields the user has chosen to display on the buglist,
# exactly as they were passed to new().
sub _input_columns { @{ $_[0]->{'fields'} || [] } }

# These are columns that are also going to be in the SELECT for one reason
# or another, but weren't actually requested by the caller.
sub _extra_columns {
    my ($self) = @_;
    # Everything that's going to be in the ORDER BY must also be
    # in the SELECT.
    $self->{extra_columns} ||= [ $self->_input_order_columns ];
    return @{ $self->{extra_columns} };
}

# For search functions to modify extra_columns. It doesn't matter if
# people push the same column onto this array multiple times, because
# _select_columns will call "uniq" on its final result.
sub _add_extra_column {
    my ($self, $column) = @_;
    push(@{ $self->{extra_columns} }, $column);
}

# These are the columns that we're going to be actually SELECTing.
sub _select_columns {
    my ($self) = @_;
    return @{ $self->{select_columns} } if $self->{select_columns};

    my @select_columns;
    foreach my $column ($self->_input_columns, $self->_extra_columns) {
        if (my $add_first = COLUMN_DEPENDS->{$column}) {
            push(@select_columns, @$add_first);
        }
        push(@select_columns, $column);
    }
    
    $self->{select_columns} = [uniq @select_columns];
    return @{ $self->{select_columns} };
}

# This takes _select_columns and translates it into the actual SQL that
# will go into the SELECT clause.
sub _sql_select {
    my ($self) = @_;
    my @sql_fields;
    foreach my $column ($self->_select_columns) {
        my $alias = $column;
        # Aliases cannot contain dots in them. We convert them to underscores.
        $alias =~ s/\./_/g;
        my $sql = ($column eq EMPTY_COLUMN)
                  ? EMPTY_COLUMN : COLUMNS->{$column}->{name} . " AS $alias";
        push(@sql_fields, $sql);
    }
    return @sql_fields;
}

################################
# Internal Accessors: ORDER BY #
################################

# The "order" that was requested by the consumer, exactly as it was
# requested.
sub _input_order { @{ $_[0]->{'order'} || [] } }
# The input order with just the column names, and no ASC or DESC.
sub _input_order_columns {
    my ($self) = @_;
    return map { (split_order_term($_))[0] } $self->_input_order;
}

# A hashref that describes all the special stuff that has to be done
# for various fields if they go into the ORDER BY clause.
sub _special_order {
    my ($self) = @_;
    return $self->{special_order} if $self->{special_order};
    
    my %special_order = %{ SPECIAL_ORDER() };
    my $select_fields = Bugzilla->fields({ type => FIELD_TYPE_SINGLE_SELECT });
    foreach my $field (@$select_fields) {
        next if $field->is_abnormal;
        my $name = $field->name;
        $special_order{$name} = {
            order => ["map_$name.sortkey", "map_$name.value"],
            join  => {
                table => $name,
                from  => "bugs.$name",
                to    => "value",
                join  => 'INNER',
            }
        };
    }
    $self->{special_order} = \%special_order;
    return $self->{special_order};
}

sub _sql_order_by {
    my ($self) = @_;
    if (!$self->{sql_order_by}) {
        my @order_by = map { $self->_translate_order_by_column($_) }
                           $self->_input_order;
        $self->{sql_order_by} = \@order_by;
    }
    return @{ $self->{sql_order_by} };
}

sub _translate_order_by_column {
    my ($self, $order_by_item) = @_;

    my ($field, $direction) = split_order_term($order_by_item);
    
    $direction = '' if lc($direction) eq 'asc';
    my $special_order = $self->_special_order->{$field}->{order};
    # Standard fields have underscores in their SELECT alias instead
    # of a period (because aliases can't have periods).
    $field =~ s/\./_/g;
    my @items = $special_order ? @$special_order : $field;
    if (lc($direction) eq 'desc') {
        @items = map { "$_ DESC" } @items;
    }
    return @items;
}

############################
# Internal Accessors: FROM #
############################

sub _column_join {
    my ($self, $field) = @_;
    my $join_info = COLUMN_JOINS->{$field};
    if ($join_info) {
        # Don't allow callers to modify the constant.
        $join_info = dclone($join_info);
    }
    else {
        if ($self->_multi_select_fields->{$field}) {
            $join_info = { table => "bug_$field" };
        }
    }
    if ($join_info and !$join_info->{as}) {
        $join_info = dclone($join_info);
        $join_info->{as} = "map_$field";
    }
    return $join_info ? $join_info : ();
}

# Sometimes we join the same table more than once. In this case, we
# want to AND all the various critiera that were used in both joins.
sub _combine_joins {
    my ($self, $joins) = @_;
    my @result;
    while(my $join = shift @$joins) {
        my $name = $join->{as};
        my ($others_like_me, $the_rest) = part { $_->{as} eq $name ? 0 : 1 }
                                               @$joins;
        if ($others_like_me) {
            my $from = $join->{from};
            my $to   = $join->{to};
            # Sanity check to make sure that we have the same from and to
            # for all the same-named joins.
            if ($from) {
                all { $_->{from} eq $from } @$others_like_me
                  or die "Not all same-named joins have identical 'from': "
                         . Dumper($join, $others_like_me);
            }
            if ($to) {
                all { $_->{to} eq $to } @$others_like_me
                  or die "Not all same-named joins have identical 'to': "
                         . Dumper($join, $others_like_me);
            }
            
            # We don't need to call uniq here--translate_join will do that
            # for us.
            my @conditions = map { @{ $_->{extra} || [] } }
                                 ($join, @$others_like_me);
            $join->{extra} = \@conditions;
            $joins = $the_rest;
        }
        push(@result, $join);
    }
    
    return @result;
}

# Takes all the "then_to" items and just puts them as the next item in
# the array. Right now this only does one level of "then_to", but we
# could re-write this to handle then_to recursively if we need more levels.
sub _extract_then_to {
    my ($self, $joins) = @_;
    my @result;
    foreach my $join (@$joins) {
        push(@result, $join);
        if (my $then_to = $join->{then_to}) {
            push(@result, $then_to);
        }
    }
    return @result;
}

# JOIN statements for the SELECT and ORDER BY columns. This should not be
# called until the moment it is needed, because _select_columns might be
# modified by the charts.
sub _select_order_joins {
    my ($self) = @_;
    my @joins;
    foreach my $field ($self->_select_columns) {
        my @column_join = $self->_column_join($field);
        push(@joins, @column_join);
    }
    foreach my $field ($self->_input_order_columns) {
        my $join_info = $self->_special_order->{$field}->{join};
        if ($join_info) {
            # Don't let callers modify SPECIAL_ORDER.
            $join_info = dclone($join_info);
            if (!$join_info->{as}) {
                $join_info->{as} = "map_$field";
            }
            push(@joins, $join_info);
        }
    }
    return @joins;
}

# These are the joins that are *always* in the FROM clause.
sub _standard_joins {
    my ($self) = @_;
    my $user = $self->_user;
    my @joins;

    my $security_join = {
        table => 'bug_group_map',
        as    => 'security_map',
    };
    push(@joins, $security_join);

    if ($user->id) {
        $security_join->{extra} =
            ["NOT (" . $user->groups_in_sql('security_map.group_id') . ")"];
            
        my $security_cc_join = {
            table => 'cc',
            as    => 'security_cc',
            extra => ['security_cc.who = ' . $user->id],
        };
        push(@joins, $security_cc_join);
    }
    
    return @joins;
}

sub _sql_from {
    my ($self, $joins_input) = @_;
    my @joins = ($self->_standard_joins, $self->_select_order_joins,
                 @$joins_input);
    @joins = $self->_extract_then_to(\@joins);
    @joins = $self->_combine_joins(\@joins);
    my @join_sql = map { $self->_translate_join($_) } @joins;
    return "bugs\n" . join("\n", @join_sql);
}

# This takes a join data structure and turns it into actual JOIN SQL.
sub _translate_join {
    my ($self, $join_info) = @_;
    
    die "join with no table: " . Dumper($join_info) if !$join_info->{table};
    die "join with no 'as': " . Dumper($join_info) if !$join_info->{as};
        
    my $from_table = "bugs";
    my $from  = $join_info->{from} || "bug_id";
    if ($from =~ /^(\w+)\.(\w+)$/) {
        ($from_table, $from) = ($1, $2);
    }
    my $table = $join_info->{table};
    my $name  = $join_info->{as};
    my $to    = $join_info->{to}    || "bug_id";
    my $join  = $join_info->{join}  || 'LEFT';
    my @extra = @{ $join_info->{extra} || [] };
    $name =~ s/\./_/g;
    
    # If a term contains ORs, we need to put parens around the condition.
    # This is a pretty weak test, but it's actually OK to put parens
    # around too many things.
    @extra = map { $_ =~ /\bOR\b/i ? "($_)" : $_ } @extra;
    my $extra_condition = join(' AND ', uniq @extra);
    if ($extra_condition) {
        $extra_condition = " AND $extra_condition";
    }

    my @join_sql = "$join JOIN $table AS $name"
                        . " ON $from_table.$from = $name.$to$extra_condition";
    return @join_sql;
}

#############################
# Internal Accessors: WHERE #
#############################

# Note: There's also quite a bit of stuff that affects the WHERE clause
# in the "Internal Accessors: Boolean Charts" section.

# The terms that are always in the WHERE clause. These implement bug
# group security.
sub _standard_where {
    my ($self) = @_;
    # If replication lags badly between the shadow db and the main DB,
    # it's possible for bugs to show up in searches before their group
    # controls are properly set. To prevent this, when initially creating
    # bugs we set their creation_ts to NULL, and don't give them a creation_ts
    # until their group controls are set. So if a bug has a NULL creation_ts,
    # it shouldn't show up in searches at all.
    my @where = ('bugs.creation_ts IS NOT NULL');
    
    my $security_term = 'security_map.group_id IS NULL';

    my $user = $self->_user;
    if ($user->id) {
        my $userid = $user->id;
        $security_term .= <<END;
 OR (bugs.reporter_accessible = 1 AND bugs.reporter = $userid)
 OR (bugs.cclist_accessible = 1 AND security_cc.who IS NOT NULL)
 OR bugs.assigned_to = $userid
END
        if (Bugzilla->params->{'useqacontact'}) {
            $security_term.= " OR bugs.qa_contact = $userid";
        }
        $security_term = "($security_term)";
    }

    push(@where, $security_term);

    return @where;
}

sub _sql_where {
    my ($self, $where_terms) = @_;
    return join(' AND ', $self->_standard_where, @$where_terms);
}

################################
# Internal Accessors: GROUP BY #
################################

# And these are the fields that we have to do GROUP BY for in DBs
# that are more strict about putting everything into GROUP BY.
sub _sql_group_by {
    my ($self) = @_;

    # Strict DBs require every element from the SELECT to be in the GROUP BY,
    # unless that element is being used in an aggregate function.
    my @extra_group_by;
    foreach my $column ($self->_select_columns) {
        next if $self->_skip_group_by->{$column};
        my $sql = COLUMNS->{$column}->{name};
        push(@extra_group_by, $sql);
    }

    # And all items from ORDER BY must be in the GROUP BY. The above loop 
    # doesn't catch items that were put into the ORDER BY from SPECIAL_ORDER.
    foreach my $column ($self->_input_order_columns) {
        my $special_order = $self->_special_order->{$column}->{order};
        next if !$special_order;
        push(@extra_group_by, @$special_order);
    }
    
    @extra_group_by = uniq @extra_group_by;
    
    # bug_id is the only field we actually group by.
    return ('bugs.bug_id', join(',', @extra_group_by));
}

# A helper for _sql_group_by.
sub _skip_group_by {
    my ($self) = @_;
    return $self->{skip_group_by} if $self->{skip_group_by};
    my @skip_list = GROUP_BY_SKIP;
    push(@skip_list, keys %{ $self->_multi_select_fields });
    my %skip_hash = map { $_ => 1 } @skip_list;
    $self->{skip_group_by} = \%skip_hash;
    return $self->{skip_group_by};
}

##############################################
# Internal Accessors: Special Params Parsing #
##############################################

# Backwards compatibility for old field names.
sub _convert_old_params {
    my ($self) = @_;
    my $params = $self->_params;
    
    # bugidtype has different values in modern Search.pm.
    if (defined $params->{'bugidtype'}) {
        my $value = $params->{'bugidtype'};
        $params->{'bugidtype'} = $value eq 'exclude' ? 'nowords' : 'anyexact';
    }
    
    foreach my $old_name (keys %{ FIELD_MAP() }) {
        if (defined $params->{$old_name}) {
            my $new_name = FIELD_MAP->{$old_name};
            $params->{$new_name} = delete $params->{$old_name};
        }
    }
}

sub _convert_special_params_to_chart_params {
    my ($self) = @_;
    my $params = $self->_params;
    
    my @special_charts = $self->_special_charts();
    
    # First we delete any sign of "Chart #-1" from the input parameters,
    # because we want to guarantee the user didn't hide something there.
    my @badcharts = grep { /^(field|type|value)-1-/ } keys %$params;
    foreach my $field (@badcharts) {
        delete $params->{$field};
    }

    # now we take our special chart and stuff it into the form hash
    my $chart = -1;
    my $and = 0;
    foreach my $or_array (@special_charts) {
        my $or = 0;
        my $identifier = "$chart-$and-$or";
        while (@$or_array) {
            $params->{"field$identifier"} = shift @$or_array;
            $params->{"type$identifier"}  = shift @$or_array;
            $params->{"value$identifier"} = shift @$or_array;
            $or++;
        }
        $and++;
    }
}

# This parses all the standard search parameters except for the boolean
# charts.
sub _special_charts {
    my ($self) = @_;
    $self->_convert_old_params();
    $self->_special_parse_bug_status();
    $self->_special_parse_resolution();
    my @charts = $self->_parse_basic_fields();
    push(@charts, $self->_special_parse_email());
    push(@charts, $self->_special_parse_chfield());
    push(@charts, $self->_special_parse_deadline());
    return @charts;
}

sub _parse_basic_fields {
    my ($self) = @_;
    my $params = $self->_params;
    my $chart_fields = $self->_chart_fields;
    
    my @charts;
    foreach my $field_name (keys %$chart_fields) {
        # CGI params shouldn't have periods in them, so we only accept
        # period-separated fields with underscores where the periods go.
        my $param_name = $field_name;
        $param_name =~ s/\./_/g;
        my @values = $self->_param_array($param_name);
        next if !@values;
        my $operator = $params->{"${param_name}_type"} || 'anyexact';
        $operator = 'matches' if $operator eq 'content';
        push(@charts, [$field_name, $operator, \@values]);
    }
    return @charts;
}

sub _special_parse_bug_status {
    my ($self) = @_;
    my $params = $self->_params;
    return if !defined $params->{'bug_status'};

    my @bug_status = $self->_param_array('bug_status');
    # Also include inactive bug statuses, as you can query them.
    my $legal_statuses = $self->_chart_fields->{'bug_status'}->legal_values;

    # If the status contains __open__ or __closed__, translate those
    # into their equivalent lists of open and closed statuses.
    if (grep { $_ eq '__open__' } @bug_status) {
        my @open = grep { $_->is_open } @$legal_statuses;
        @open = map { $_->name } @open;
        push(@bug_status, @open);
    }
    if (grep { $_ eq '__closed__' } @bug_status) {
        my @closed = grep { not $_->is_open } @$legal_statuses;
        @closed = map { $_->name } @closed;
        push(@bug_status, @closed);
    }

    @bug_status = uniq @bug_status;
    my $all = grep { $_ eq "__all__" } @bug_status;
    # This will also handle removing __open__ and __closed__ for us
    # (__all__ too, which is why we check for it above, first).
    @bug_status = _valid_values(\@bug_status, $legal_statuses);

    # If the user has selected every status, change to selecting none.
    # This is functionally equivalent, but quite a lot faster.    
    if ($all or scalar(@bug_status) == scalar(@$legal_statuses)) {
        delete $params->{'bug_status'};
    }
    else {
        $params->{'bug_status'} = \@bug_status;
    }
}

sub _special_parse_chfield {
    my ($self) = @_;
    my $params = $self->_params;
    
    my $date_from = trim(lc($params->{'chfieldfrom'} || ''));
    my $date_to = trim(lc($params->{'chfieldto'} || ''));
    $date_from = '' if $date_from eq 'now';
    $date_to = '' if $date_to eq 'now';
    my @fields = $self->_param_array('chfield');
    my $value_to = $params->{'chfieldvalue'};
    $value_to = '' if !defined $value_to;

    my @charts;
    # It is always safe and useful to push delta_ts into the charts
    # if there are any dates specified. It doesn't conflict with
    # searching [Bug creation], because a bug's delta_ts is set to
    # its creation_ts when it is created. So this just gives the
    # database an additional index to possibly choose.
    if ($date_from ne '') {
        push(@charts, ['delta_ts', 'greaterthaneq', $date_from]);
    }
    if ($date_to ne '') {
        push(@charts, ['delta_ts', 'lessthaneq', $date_to]);
    }
    
    if (grep { $_ eq '[Bug creation]' } @fields) {
        if ($date_from ne '') {
            push(@charts, ['creation_ts', 'greaterthaneq', $date_from]);
        }
        if ($date_to ne '') {
            push(@charts, ['creation_ts', 'lessthaneq', $date_to]);
        }
    }

    # Basically, we construct the chart like:
    #
    # (added_for_field1 = value OR added_for_field2 = value)
    # AND (date_field1_changed >= date_from OR date_field2_changed >= date_from)
    # AND (date_field1_changed <= date_to OR date_field2_changed <= date_to)
    #
    # Theoretically, all we *really* would need to do is look for the field id
    # in the bugs_activity table, because we've already limited the search
    # by delta_ts above, but there's no chart to do that, so we check the
    # change date of the fields.
    
    if ($value_to ne '') {
        my @value_chart;
        foreach my $field (@fields) {
            next if $field eq '[Bug creation]';
            push(@value_chart, $field, 'changedto', $value_to);
        }
        push(@charts, \@value_chart) if @value_chart;
    }

    if ($date_from ne '') {
        my @date_from_chart;
        foreach my $field (@fields) {
            next if $field eq '[Bug creation]';
            push(@date_from_chart, $field, 'changedafter', $date_from);
        }
        push(@charts, \@date_from_chart) if @date_from_chart;
    }
    if ($date_to ne '') {
        my @date_to_chart;
        foreach my $field (@fields) {
            push(@date_to_chart, $field, 'changedbefore', $date_to);
        }
        push(@charts, \@date_to_chart) if @date_to_chart;
    }

    return @charts;
}

sub _special_parse_deadline {
    my ($self) = @_;
    return if !$self->_user->is_timetracker;
    my $params = $self->_params;
    
    my @charts;
    if (my $from = $params->{'deadlinefrom'}) {
        push(@charts, ['deadline', 'greaterthaneq', $from]);
    }
    if (my $to = $params->{'deadlineto'}) {
        push(@charts, ['deadline', 'lessthaneq', $to]);
    }
    
    return @charts;
}

sub _special_parse_email {
    my ($self) = @_;
    my $params = $self->_params;
    
    my @email_params = grep { $_ =~ /^email\d+$/ } keys %$params;
    
    my @charts;
    foreach my $param (@email_params) {
        $param =~ /(\d+)$/;
        my $id = $1;
        my $email = trim($params->{"email$id"});
        next if !$email;
        my $type = $params->{"emailtype$id"} || 'anyexact';
        $type = "anyexact" if $type eq "exact";

        my @or_charts;
        foreach my $field qw(assigned_to reporter cc qa_contact) {
            if ($params->{"email$field$id"}) {
                push(@or_charts, $field, $type, $email);
            }
        }
        if ($params->{"emaillongdesc$id"}) {
            push(@or_charts, "commenter", $type, $email);
        }

        push(@charts, \@or_charts);
    }
    
    return @charts;
}

sub _special_parse_resolution {
    my ($self) = @_;
    my $params = $self->_params;
    return if !defined $params->{'resolution'};

    my @resolution = $self->_param_array('resolution');
    my $legal_resolutions = $self->_chart_fields->{resolution}->legal_values;
    @resolution = _valid_values(\@resolution, $legal_resolutions, '---');
    if (scalar(@resolution) == scalar(@$legal_resolutions)) {
        delete $params->{'resolution'};
    }
}

sub _valid_values {
    my ($input, $valid, $extra_value) = @_;
    my @result;
    foreach my $item (@$input) {
        if (defined $extra_value and $item eq $extra_value) {
            push(@result, $item);
        }
        elsif (grep { $_->name eq $item } @$valid) {
            push(@result, $item);
        }
    }
    return @result;
}

######################################
# Internal Accessors: Boolean Charts #
######################################

sub _charts_to_conditions {
    my ($self) = @_;
    my @charts = $self->_params_to_charts();
    
    my (@joins, @having, @where_terms);
    
    foreach my $chart (@charts) {
        my @and_terms;
        my $negate;
        foreach my $and_item (@$chart) {
            if (!ref $and_item and $and_item eq NEGATE) {
                $negate = 1;
                next;
            }
            my @or_terms;
            foreach my $or_item (@$and_item) {
                if ($or_item->{term} ne '') {
                    push(@or_terms, $or_item->{term});
                }
                push(@joins, @{ $or_item->{joins} });
                push(@having, @{ $or_item->{having} });
            }

            if (@or_terms) {
                # If a term contains ANDs, we need to put parens around the
                # condition. This is a pretty weak test, but it's actually OK
                # to put parens around too many things.
                @or_terms = map { $_ =~ /\bAND\b/i ? "($_)" : $_ } @or_terms;
                my $or_sql = join(' OR ', @or_terms);
                push(@and_terms, $or_sql);
            }
        }
        # And here we need to paren terms that contain ORs.
        @and_terms = map { $_ =~ /\bOR\b/i ? "($_)" : $_ } @and_terms;
        my $and_sql = join(' AND ', @and_terms);
        if ($negate and $and_sql ne '') {
            $and_sql = "NOT ($and_sql)";
        }
        push(@where_terms, $and_sql) if $and_sql ne '';
    }

    return (\@joins, \@having, \@where_terms);
}

sub _params_to_charts {
    my ($self) = @_;
    my $params = $self->_params;
    $self->_convert_special_params_to_chart_params();
    my @param_list = keys %$params;
    
    my @all_field_params = grep { /^field-?\d+/ } @param_list;
    my @chart_ids = map { /^field(-?\d+)/; $1 } @all_field_params;
    @chart_ids = sort { $a <=> $b } uniq @chart_ids;
    
    my $sequence = 0;
    my @charts;
    foreach my $chart_id (@chart_ids) {
        my @all_and = grep { /^field$chart_id-\d+/ } @param_list;
        my @and_ids = map { /^field$chart_id-(\d+)/; $1 } @all_and;
        @and_ids = sort { $a <=> $b } uniq @and_ids;
        
        my @and_charts;
        foreach my $and_id (@and_ids) {
            my @all_or = grep { /^field$chart_id-$and_id-\d+/ } @param_list;
            my @or_ids = map { /^field$chart_id-$and_id-(\d+)/; $1 } @all_or;
            @or_ids = sort { $a <=> $b } uniq @or_ids;
            
            my @or_charts;
            foreach my $or_id (@or_ids) {
                my $info = $self->_handle_chart($chart_id, $and_id, $or_id);
                # $info will be undefined if _handle_chart returned early,
                # meaning that the field, value, or operator were empty.
                push(@or_charts, $info) if defined $info;
            }
            if ($params->{"negate$chart_id"}) {
                push(@and_charts, NEGATE);
            }
            push(@and_charts, \@or_charts);
        }
        push(@charts, \@and_charts);
    }
    
    return @charts;
}

sub _handle_chart {
    my ($self, $chart_id, $and_id, $or_id) = @_;
    my $dbh = Bugzilla->dbh;
    my $params = $self->_params;
    
    my $sql_chart_id = $chart_id;
    if ($chart_id < 0) {
        $sql_chart_id = "default_" . abs($chart_id);
    }
    
    my $identifier = "$chart_id-$and_id-$or_id";
    
    my $field = $params->{"field$identifier"};
    my $operator = $params->{"type$identifier"};
    my $value = $params->{"value$identifier"};

    return if (!defined $field or !defined $operator or !defined $value);

    my $string_value;
    if (ref $value eq 'ARRAY') {
        # Trim input and ignore blank values.
        @$value = map { trim($_) } @$value;
        @$value = grep { defined $_ and $_ ne '' } @$value;
        return if !@$value;
        $string_value = join(',', @$value);
    }
    else {
        return if $value eq '';
        $string_value = $value;
    }
    
    $self->_chart_fields->{$field}
        or ThrowCodeError("invalid_field_name", { field => $field });
    trick_taint($field);
    
    # This is the field as you'd reference it in a SQL statement.
    my $full_field = $field =~ /\./ ? $field : "bugs.$field";

    # "value" and "quoted" are for search functions that always operate
    # on a scalar string and never care if they were passed multiple
    # parameters. If the user does pass multiple parameters, they will
    # become a space-separated string for those search functions.
    #
    # all_values and all_quoted are for search functions that do operate
    # on multiple values, like anyexact.

    my %search_args = (
        chart_id   => $sql_chart_id,
        sequence   => $or_id,
        field      => $field,
        full_field => $full_field,
        operator   => $operator,
        value      => $string_value,
        quoted     => $dbh->quote($string_value),
        all_values => $value,
        joins      => [],
        having     => [],
    );
    # This should add a "term" selement to %search_args.
    $self->do_search_function(\%search_args);
    
    # All the things here that don't get pulled out of
    # %search_args are their original values before
    # do_search_function modified them.   
    $self->search_description({
        field => $field, type => $operator,
        value => $string_value, term => $search_args{term},
    });
    
    return \%search_args;
}
   
##################################
# do_search_function And Helpers #
##################################

# This takes information about the current boolean chart and translates
# it into SQL, using the constants at the top of this file.
sub do_search_function {
    my ($self, $args) = @_;
    my ($field, $operator) = @$args{qw(field operator)};
    
    my $actual_field = FIELD_MAP->{$field} || $field;
    $args->{field} = $actual_field;
    
    if (my $parse_func = SPECIAL_PARSING->{$actual_field}) {
        $self->$parse_func($args);
        # Some parsing functions set $term, though most do not.
        # For the ones that set $term, we don't need to do any further
        # parsing.
        return if $args->{term};
    }
    
    my $override = OPERATOR_FIELD_OVERRIDE->{$actual_field};
    if (!$override) {
        # Multi-select fields get special handling.
        if ($self->_multi_select_fields->{$actual_field}) {
            $override = OPERATOR_FIELD_OVERRIDE->{_multi_select};
        }
        # And so do attachment fields, if they don't have a specific
        # individual override.
        elsif ($actual_field =~ /^attachments\./) {
            $override = OPERATOR_FIELD_OVERRIDE->{attachments};
        }
    }
    
    if ($override) {
        my $search_func = $self->_pick_override_function($override, $operator);
        $self->$search_func($args) if $search_func;
    }

    # Some search functions set $term, and some don't. For the ones that
    # don't (or for fields that don't have overrides) we now call the
    # direct operator function from OPERATORS.
    if (!defined $args->{term}) {
        $self->_do_operator_function($args);
    }
    
    if (!defined $args->{term}) {
        # This field and this type don't work together. Generally,
        # this should never be reached, because it should be handled
        # explicitly by OPERATOR_FIELD_OVERRIDE.
        ThrowUserError("search_field_operator_invalid",
                       { field => $field, operator => $operator });
    }
}

# A helper for various search functions that need to run operator
# functions directly.
sub _do_operator_function {
    my ($self, $func_args) = @_;
    my $operator = $func_args->{operator};
    my $operator_func = OPERATORS->{$operator};
    $self->$operator_func($func_args);
}

sub _reverse_operator {
    my ($self, $operator) = @_;
    my $reverse = OPERATOR_REVERSE->{$operator};
    return $reverse if $reverse;
    if ($operator =~ s/^not//) {
        return $operator;
    }
    return "not$operator";
}

sub _pick_override_function {
    my ($self, $override, $operator) = @_;
    my $search_func = $override->{$operator};

    if (!$search_func) {
        # If we don't find an override for one specific operator,
        # then there are some special override types:
        # _non_changed: For any operator that doesn't have the word
        #               "changed" in it
        # _default: Overrides all operators that aren't explicitly specified.
        if ($override->{_non_changed} and $operator !~ /changed/) {
            $search_func = $override->{_non_changed};
        }
        elsif ($override->{_default}) {
            $search_func = $override->{_default};
        }
    }

    return $search_func;
}

###########################
# Search Function Helpers #
###########################

sub SqlifyDate {
    my ($str) = @_;
    $str = "" if !defined $str;
    if ($str eq "") {
        my ($sec, $min, $hour, $mday, $month, $year, $wday) = localtime(time());
        return sprintf("%4d-%02d-%02d 00:00:00", $year+1900, $month+1, $mday);
    }


    if ($str =~ /^(-|\+)?(\d+)([hHdDwWmMyY])$/) {   # relative date
        my ($sign, $amount, $unit, $date) = ($1, $2, lc $3, time);
        my ($sec, $min, $hour, $mday, $month, $year, $wday)  = localtime($date);
        if ($sign && $sign eq '+') { $amount = -$amount; }
        if ($unit eq 'w') {                  # convert weeks to days
            $amount = 7*$amount + $wday;
            $unit = 'd';
        }
        if ($unit eq 'd') {
            $date -= $sec + 60*$min + 3600*$hour + 24*3600*$amount;
            return time2str("%Y-%m-%d %H:%M:%S", $date);
        }
        elsif ($unit eq 'y') {
            return sprintf("%4d-01-01 00:00:00", $year+1900-$amount);
        }
        elsif ($unit eq 'm') {
            $month -= $amount;
            while ($month<0) { $year--; $month += 12; }
            return sprintf("%4d-%02d-01 00:00:00", $year+1900, $month+1);
        }
        elsif ($unit eq 'h') {
            # Special case 0h for 'beginning of this hour'
            if ($amount == 0) {
                $date -= $sec + 60*$min;
            } else {
                $date -= 3600*$amount;
            }
            return time2str("%Y-%m-%d %H:%M:%S", $date);
        }
        return undef;                      # should not happen due to regexp at top
    }
    my $date = str2time($str);
    if (!defined($date)) {
        ThrowUserError("illegal_date", { date => $str });
    }
    return time2str("%Y-%m-%d %H:%M:%S", $date);
}

sub build_subselect {
    my ($outer, $inner, $table, $cond) = @_;
    my $q = "SELECT $inner FROM $table WHERE $cond";
    #return "$outer IN ($q)";
    my $dbh = Bugzilla->dbh;
    my $list = $dbh->selectcol_arrayref($q);
    return "1=2" unless @$list; # Could use boolean type on dbs which support it
    return $dbh->sql_in($outer, $list);}

sub GetByWordList {
    my ($field, $strs) = (@_);
    my @list;
    my $dbh = Bugzilla->dbh;
    return [] unless defined $strs;

    foreach my $w (split(/[\s,]+/, $strs)) {
        my $word = $w;
        if ($word ne "") {
            $word =~ tr/A-Z/a-z/;
            $word = $dbh->quote('(^|[^a-z0-9])' . quotemeta($word) . '($|[^a-z0-9])');
            trick_taint($word);
            push(@list, $dbh->sql_regexp($field, $word));
        }
    }

    return \@list;
}

# Support for "any/all/nowordssubstr" comparison type ("words as substrings")
sub GetByWordListSubstr {
    my ($field, $strs) = (@_);
    my @list;
    my $dbh = Bugzilla->dbh;
    my $sql_word;

    foreach my $word (split(/[\s,]+/, $strs)) {
        if ($word ne "") {
            $sql_word = $dbh->quote($word);
            trick_taint($sql_word);
            push(@list, $dbh->sql_iposition($sql_word, $field) . " > 0");
        }
    }

    return \@list;
}

sub pronoun {
    my ($noun, $user) = (@_);
    if ($noun eq "%user%") {
        if ($user->id) {
            return $user->id;
        } else {
            ThrowUserError('login_required_for_pronoun');
        }
    }
    if ($noun eq "%reporter%") {
        return "bugs.reporter";
    }
    if ($noun eq "%assignee%") {
        return "bugs.assigned_to";
    }
    if ($noun eq "%qacontact%") {
        return "bugs.qa_contact";
    }
    return 0;
}

sub _all_values {
    my ($self, $args, $split_on) = @_;
    $split_on ||= qr/[\s,]+/;
    my $dbh = Bugzilla->dbh;
    my $all_values = $args->{all_values};
    
    my @array;
    if (ref $all_values eq 'ARRAY') {
        @array = @$all_values;
    }
    else {
        @array = split($split_on, $all_values);
        @array = map { trim($_) } @array;
        @array = grep { defined $_ and $_ ne '' } @array;
    }
    
    if ($args->{field} eq 'resolution') {
        @array = map { $_ eq '---' ? '' : $_ } @array;
    }
    
    return @array;
}

######################
# Public Subroutines #
######################

# Validate that the query type is one we can deal with
sub IsValidQueryType
{
    my ($queryType) = @_;
    if (grep { $_ eq $queryType } qw(specific advanced)) {
        return 1;
    }
    return 0;
}

# Splits out "asc|desc" from a sort order item.
sub split_order_term {
    my $fragment = shift;
    $fragment =~ /^(.+?)(?:\s+(ASC|DESC))?$/i;
    my ($column_name, $direction) = (lc($1), uc($2 || ''));
    return wantarray ? ($column_name, $direction) : $column_name;
}

# Used to translate old SQL fragments from buglist.cgi's "order" argument
# into our modern field IDs.
sub translate_old_column {
    my ($column) = @_;
    # All old SQL fragments have a period in them somewhere.
    return $column if $column !~ /\./;

    if ($column =~ /\bAS\s+(\w+)$/i) {
        return $1;
    }
    # product, component, classification, assigned_to, qa_contact, reporter
    elsif ($column =~ /map_(\w+?)s?\.(login_)?name/i) {
        return $1;
    }
    
    # If it doesn't match the regexps above, check to see if the old 
    # SQL fragment matches the SQL of an existing column
    foreach my $key (%{ COLUMNS() }) {
        next unless exists COLUMNS->{$key}->{name};
        return $key if COLUMNS->{$key}->{name} eq $column;
    }

    return $column;
}

#####################################################################
# Search Functions
#####################################################################

sub _invalid_combination {
    my ($self, $args) = @_;
    my ($field, $operator) = @$args{qw(field operator)};
    ThrowUserError('search_field_operator_invalid',
                   { field => $field, operator => $operator });
}

sub _contact_pronoun {
    my ($self, $args) = @_;
    my ($value, $quoted) = @$args{qw(value quoted)};
    my $user = $self->_user;
    
    if ($value =~ /^\%group/) {
        $self->_contact_exact_group($args);
    }
    elsif ($value =~ /^(%\w+%)$/) {
        $args->{value} = pronoun($1, $user);
        $args->{quoted} = $args->{value};
    }
}

sub _contact_exact_group {
    my ($self, $args) = @_;
    my ($value, $operator, $field, $chart_id, $joins) =
        @$args{qw(value operator field chart_id joins)};
    my $dbh = Bugzilla->dbh;
    
    $value =~ /\%group\.([^%]+)%/;
    my $group = Bugzilla::Group->check($1);
    $group->check_members_are_visible();
    my $group_ids = Bugzilla::Group->flatten_group_membership($group->id);
    my $table = "user_group_map_$chart_id";
    my $join = {
        table => 'user_group_map',
        as    => $table,
        from  => $field,
        to    => 'user_id',
        extra => [$dbh->sql_in("$table.group_id", $group_ids),
                  "$table.isbless = 0"],
    };
    push(@$joins, $join);
    if ($operator =~ /^not/) {
        $args->{term} = "$table.group_id IS NULL";
    }
    else {
        $args->{term} = "$table.group_id IS NOT NULL";
    }
}

sub _contact_nonchanged {
    my ($self, $args) = @_;
    my $field = $args->{field};
    
    $args->{full_field} = "profiles.login_name";
    $self->_do_operator_function($args);
    my $term = $args->{term};
    $args->{term} = "bugs.$field IN (SELECT userid FROM profiles WHERE $term)";
}

sub _qa_contact_nonchanged {
    my ($self, $args) = @_;

    # This will join in map_qa_contact for us.    
    $self->_add_extra_column('qa_contact');
    $args->{full_field} = "COALESCE(map_qa_contact.login_name,'')";
}

sub _cc_pronoun {
    my ($self, $args) = @_;
    my ($full_field, $value) = @$args{qw(full_field value)};
    my $user = $self->_user;

    if ($value =~ /\%group/) {
        return $self->_cc_exact_group($args);
    }
    elsif ($value =~ /^(%\w+%)$/) {
        $args->{value} = pronoun($1, $user);
        $args->{quoted} = $args->{value};
        $args->{full_field} = "profiles.userid";
    }
}

sub _cc_exact_group {
    my ($self, $args) = @_;
    my ($chart_id, $sequence, $joins, $operator, $value) =
        @$args{qw(chart_id sequence joins operator value)};
    my $user = $self->_user;
    my $dbh = Bugzilla->dbh;
    
    $value =~ m/%group\.([^%]+)%/;
    my $group = Bugzilla::Group->check($1);
    $group->check_members_are_visible();
    my $all_groups = Bugzilla::Group->flatten_group_membership($group->id);

    # This is for the email1, email2, email3 fields from query.cgi.
    if ($chart_id eq "") {
        $chart_id = "CC$$sequence";
        $args->{sequence}++;
    }
    
    my $cc_table = "cc_$chart_id";
    push(@$joins, { table => 'cc', as => $cc_table });
    my $group_table = "user_group_map_$chart_id";
    my $group_join = {
        table => 'user_group_map',
        as    => $group_table,
        from  => "$cc_table.who",
        to    => 'user_id',
        extra => [$dbh->sql_in("$group_table.group_id", $all_groups),
                  "$group_table.isbless = 0"],
    };
    push(@$joins, $group_join);

    if ($operator =~ /^not/) {
        $args->{term} = "$group_table.group_id IS NULL";
    }
    else {
        $args->{term} = "$group_table.group_id IS NOT NULL";
    }
}

sub _cc_nonchanged {
    my ($self, $args) = @_;
    my ($chart_id, $sequence, $field, $full_field, $operator, $joins) =
        @$args{qw(chart_id sequence field full_field operator joins)};

    # This is for the email1, email2, email3 fields from query.cgi.
    if ($chart_id eq "") {
        $chart_id = "CC$sequence";
        $args->{sequence}++;
    }
    
    # $full_field might have been changed by one of the cc_pronoun
    # functions, in which case we leave it alone.
    if ($full_field eq 'bugs.cc') {
        $args->{full_field} = "profiles.login_name";
    }
    
    $self->_do_operator_function($args);
    
    my $term = $args->{term};
    my $table = "cc_$chart_id";
    my $join = {
        table => 'cc',
        as    => $table,
        extra => ["$table.who IN (SELECT userid FROM profiles WHERE $term)"],
    };
    push(@$joins, $join);
    
    $args->{term} = "$table.who IS NOT NULL";
}

# XXX This duplicates having Commenter as a search field.
sub _long_desc_changedby {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $value) = @$args{qw(chart_id joins value)};
    
    my $table = "longdescs_$chart_id";
    push(@$joins, { table => 'longdescs', as => $table });
    my $user_id = login_to_id($value, THROW_ERROR);
    $args->{term} = "$table.who = $user_id";
}

sub _long_desc_changedbefore_after {
    my ($self, $args) = @_;
    my ($chart_id, $operator, $value, $joins) =
        @$args{qw(chart_id operator value joins)};
    my $dbh = Bugzilla->dbh;
    
    my $sql_operator = ($operator =~ /before/) ? '<=' : '>=';
    my $table = "longdescs_$chart_id";
    my $sql_date = $dbh->quote(SqlifyDate($value));
    my $join = {
        table => 'longdescs',
        as    => $table,
        extra => ["$table.bug_when $sql_operator $sql_date"],
    };
    push(@$joins, $join);
    $args->{term} = "$table.bug_when IS NOT NULL";
}

sub _content_matches {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $fields, $operator, $value) =
        @$args{qw(chart_id joins fields operator value)};
    my $dbh = Bugzilla->dbh;
    
    # "content" is an alias for columns containing text for which we
    # can search a full-text index and retrieve results by relevance, 
    # currently just bug comments (and summaries to some degree).
    # There's only one way to search a full-text index, so we only
    # accept the "matches" operator, which is specific to full-text
    # index searches.

    # Add the fulltext table to the query so we can search on it.
    my $table = "bugs_fulltext_$chart_id";
    my $comments_col = "comments";
    $comments_col = "comments_noprivate" unless $self->_user->is_insider;
    push(@$joins, { table => 'bugs_fulltext', as => $table });
    
    # Create search terms to add to the SELECT and WHERE clauses.
    my ($term1, $rterm1) =
        $dbh->sql_fulltext_search("$table.$comments_col", $value, 1);
    my ($term2, $rterm2) =
        $dbh->sql_fulltext_search("$table.short_desc", $value, 2);
    $rterm1 = $term1 if !$rterm1;
    $rterm2 = $term2 if !$rterm2;

    # The term to use in the WHERE clause.
    my $term = "$term1 > 0 OR $term2 > 0";
    if ($operator =~ /not/i) {
        $term = "NOT($term)";
    }
    $args->{term} = $term;
    
    # In order to sort by relevance (in case the user requests it),
    # we SELECT the relevance value so we can add it to the ORDER BY
    # clause. Every time a new fulltext chart isadded, this adds more 
    # terms to the relevance sql.
    #
    # We build the relevance SQL by modifying the COLUMNS list directly,
    # which is kind of a hack but works.
    my $current = COLUMNS->{'relevance'}->{name};
    $current = $current ? "$current + " : '';
    # For NOT searches, we just add 0 to the relevance.
    my $select_term = $operator =~ /not/ ? 0 : "($current$rterm1 + $rterm2)";
    COLUMNS->{'relevance'}->{name} = $select_term;
}

sub _timestamp_translate {
    my ($self, $args) = @_;
    my $value = $args->{value};
    my $dbh = Bugzilla->dbh;

    return if $value !~ /^[\+\-]?\d+[hdwmy]$/i;
    
    $args->{value}  = SqlifyDate($value);
    $args->{quoted} = $dbh->quote($args->{value});
}

# XXX This should probably be merged with cc_pronoun.
sub _commenter_pronoun {
    my ($self, $args) = @_;
    my $value = $args->{value};
    my $user = $self->_user;

    if ($value =~ /^(%\w+%)$/) {
        $args->{value} = pronoun($1, $user);
        $args->{quoted} = $args->{value};
        $args->{full_field} = "profiles.userid";
    }
}

sub _commenter {
    my ($self, $args) = @_;
    my ($chart_id, $sequence, $joins, $field, $full_field, $operator) =
        @$args{qw(chart_id sequence joins field full_field operator)};

    if ($chart_id eq "") {
        $chart_id = "LD$sequence";
        $args->{sequence}++;
    }
    my $table = "longdescs_$chart_id";
    
    my $extra = $self->_user->is_insider ? "" : "AND $table.isprivate = 0";
    # commenter_pronoun could have changed $full_field to something else,
    # so we only set this if commenter_pronoun hasn't set it.
    if ($full_field eq 'bugs.commenter') {
        $args->{full_field} = "profiles.login_name";
    }
    $self->_do_operator_function($args);
    my $term = $args->{term};
    my $join = {
        table => 'longdescs',
        as    => $table,
        extra => ["$table.who IN (SELECT userid FROM profiles WHERE $term)"],
    };
    push(@$joins, $join);
    $args->{term} = "$table.who IS NOT NULL";
}

sub _long_desc {
    my ($self, $args) = @_;
    my ($chart_id, $joins) = @$args{qw(chart_id joins)};
    
    my $table = "longdescs_$chart_id";
    my $extra = $self->_user->is_insider ? [] : ["$table.isprivate = 0"];
    my $join = {
        table => 'longdescs',
        as    => $table,
        extra => $extra,
    };
    push(@$joins, $join);
    $args->{full_field} = "$table.thetext";
}

sub _longdescs_isprivate {
    my ($self, $args) = @_;
    my ($chart_id, $joins) = @$args{qw(chart_id joins)};
    
    my $table = "longdescs_$chart_id";
    my $extra = $self->_user->is_insider ? [] : ["$table.isprivate = 0"];
    my $join = {
        table => 'longdescs',
        as    => $table,
        extra => $extra,
    };
    push(@$joins, $join);
    $args->{full_field} = "$table.isprivate";
}

sub _work_time_changedby {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $value) = @$args{qw(chart_id joins value)};
    
    my $table = "longdescs_$chart_id";
    push(@$joins, { table => 'longdescs', as => $table });
    my $user_id = login_to_id($value, THROW_ERROR);
    $args->{term} = "$table.who = $user_id AND $table.work_time != 0";
}

sub _work_time_changedbefore_after {
    my ($self, $args) = @_;
    my ($chart_id, $operator, $value, $joins) =
        @$args{qw(chart_id operator value joins)};
    my $dbh = Bugzilla->dbh;
    
    my $table = "longdescs_$chart_id";
    my $sql_operator = ($operator =~ /before/) ? '<=' : '>=';
    my $sql_date = $dbh->quote(SqlifyDate($value));
    my $join = {
        table => 'longdescs',
        as    => $table,
        extra => ["$table.work_time != 0",
                  "$table.bug_when $sql_operator $sql_date"],
    };
    push(@$joins, $join);
    
    $args->{term} = "$table.bug_when IS NOT NULL";
}

sub _work_time {
    my ($self, $args) = @_;
    my ($chart_id, $joins) = @$args{qw(chart_id joins)};
    
    my $table = "longdescs_$chart_id";
    push(@$joins, { table => 'longdescs', as => $table });
    $args->{full_field} = "$table.work_time";
}

sub _percentage_complete {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $operator, $having, $fields) =
        @$args{qw(chart_id joins operator having fields)};

    my $table = "longdescs_$chart_id";

    # We can't just use "percentage_complete" as the field, because
    # (a) PostgreSQL doesn't accept it in the HAVING clause
    # and (b) it wouldn't work in multiple chart rows, because it uses
    # a fixed name for the table, "ldtime".
    my $expression = COLUMNS->{percentage_complete}->{name};
    $expression =~ s/\bldtime\b/$table/g;
    $args->{full_field} = "($expression)";
    push(@$joins, { table => 'longdescs', as => $table });

    # We need remaining_time in _select_columns, otherwise we can't use
    # it in the expression for creating percentage_complete.
    $self->_add_extra_column('remaining_time');

    $self->_do_operator_function($args);
    push(@$having, $args->{term});
   
    # We put something into $args->{term} so that do_search_function
    # stops processing.
    $args->{term} = '';
}

sub _bug_group_nonchanged {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $field) = @$args{qw(chart_id joins field)};
    
    my $map_table = "bug_group_map_$chart_id";
    
    push(@$joins, { table => 'bug_group_map', as => $map_table });
    
    my $groups_table = "groups_$chart_id";
    my $full_field = "$groups_table.name";
    $args->{full_field} = $full_field;
    $self->_do_operator_function($args);
    my $term = $args->{term};
    my $groups_join = {
        table => 'groups',
        as    => $groups_table,
        from  => "$map_table.group_id",
        to    => 'id',
        extra => [$term],
    };
    push(@$joins, $groups_join);
    $args->{term} = "$full_field IS NOT NULL";
}

sub _attach_data_thedata {
    my ($self, $args) = @_;
    my ($chart_id, $joins) = @$args{qw(chart_id joins)};
    
    my $attach_table = "attachments_$chart_id";
    my $data_table = "attachdata_$chart_id";
    my $extra = $self->_user->is_insider
                ? [] : ["$attach_table.isprivate = 0"];
    my $attachments_join = {
        table => 'attachments',
        as    => $attach_table,
        extra => $extra,
    };
    my $data_join = {
        table => 'attach_data',
        as    => $data_table,
        from  => "$attach_table.attach_id",
        to    => "id",
    };
    push(@$joins, $attachments_join, $data_join);
    $args->{full_field} = "$data_table.thedata";
}

sub _attachments_submitter {
    my ($self, $args) = @_;
    my ($chart_id, $joins) = @$args{qw(chart_id joins)};
    
    my $attach_table = "attachments_$chart_id";
    my $profiles_table = "map_attachment_submitter_$chart_id";    
    my $extra = $self->_user->is_insider
                ? [] : ["$attach_table.isprivate = 0"];
    my $attachments_join = {
        table => 'attachments',
        as    => $attach_table,
        extra => $extra,
    };
    my $profiles_join = {
        table => 'profiles',
        as    => $profiles_table,
        from  => "$attach_table.submitter_id",
        to    => 'userid',
    };
    push(@$joins, $attachments_join, $profiles_join);
    
    $args->{full_field} = "$profiles_table.login_name";
}

sub _attachments {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $field) =
        @$args{qw(chart_id joins field)};
    my $dbh = Bugzilla->dbh;
    
    my $table = "attachments_$chart_id";
    my $extra = $self->_user->is_insider ? [] : ["$table.isprivate = 0"];
    my $join = {
        table => 'attachments',
        as    => $table,
        extra => $extra,
    };
    push(@$joins, $join);
    $field =~ /^attachments\.(.+)$/;
    my $attach_field = $1;
    
    $args->{full_field} = "$table.$attach_field";
}

sub _join_flag_tables {
    my ($self, $args) = @_;
    my ($joins, $chart_id) = @$args{qw(joins chart_id)};
    
    my $attach_table = "attachments_$chart_id";
    my $flags_table = "flags_$chart_id";
    my $extra = $self->_user->is_insider
                ? [] : ["$attach_table.isprivate = 0"];
    my $attachments_join = {
        table => 'attachments',
        as    => $attach_table,
        extra => $extra,
    };
    # We join both the bugs and the attachments table in separately,
    # and then the join code will later combine the terms.
    my $flags_join = {
        table => 'flags',
        as    => $flags_table,
        extra => ["($flags_table.attach_id = $attach_table.attach_id "
                  . " OR $flags_table.attach_id IS NULL)"],
    };
    
    push(@$joins, $attachments_join, $flags_join);
}

sub _flagtypes_name {
    my ($self, $args) = @_;
    my ($chart_id, $operator, $joins, $field, $having) = 
        @$args{qw(chart_id operator joins field having)};
    my $dbh = Bugzilla->dbh;
    
    # Matches bugs by flag name/status.
    # Note that--for the purposes of querying--a flag comprises
    # its name plus its status (i.e. a flag named "review" 
    # with a status of "+" can be found by searching for "review+").
    
    # Don't do anything if this condition is about changes to flags,
    # as the generic change condition processors can handle those.
    return if $operator =~ /^changed/;
    
    # Add the flags and flagtypes tables to the query.  We do 
    # a left join here so bugs without any flags still match 
    # negative conditions (f.e. "flag isn't review+").
    $self->_join_flag_tables($args);
    my $flags = "flags_$chart_id";
    my $flagtypes = "flagtypes_$chart_id";
    my $flagtypes_join = {
        table => 'flagtypes',
        as    => $flagtypes,
        from  => "$flags.type_id",
        to    => 'id',
    };
    push(@$joins, $flagtypes_join);
    
    # Generate the condition by running the operator-specific
    # function. Afterwards the condition resides in the $args->{term}
    # variable.
    my $full_field = $dbh->sql_string_concat("$flagtypes.name",
                                             "$flags.status");
    $args->{full_field} = $full_field;
    $self->_do_operator_function($args);
    my $term = $args->{term};
    
    # If this is a negative condition (f.e. flag isn't "review+"),
    # we only want bugs where all flags match the condition, not 
    # those where any flag matches, which needs special magic.
    # Instead of adding the condition to the WHERE clause, we select
    # the number of flags matching the condition and the total number
    # of flags on each bug, then compare them in a HAVING clause.
    # If the numbers are the same, all flags match the condition,
    # so this bug should be included.
    if ($operator =~ /^not/) {
       push(@$having,
            "SUM(CASE WHEN $full_field IS NOT NULL THEN 1 ELSE 0 END) = " .
            "SUM(CASE WHEN $term THEN 1 ELSE 0 END)");
       $args->{term} = '';
    }
}

# XXX These two functions can probably be joined (requestees and setters).
sub _requestees_login_name {
    my ($self, $args) = @_;
    my ($chart_id, $joins) = @$args{qw(chart_id joins)};
    
    $self->_join_flag_tables($args);
    my $flags = "flags_$chart_id";
    my $map_table = "map_flag_requestees_$chart_id";
    my $profiles_join = {
        table => 'profiles',
        as    => $map_table,
        from  => "$flags.requestee_id",
        to    => 'userid',
    };
    push(@$joins, $profiles_join);

    $args->{full_field} = "$map_table.login_name";
}

sub _setters_login_name {
    my ($self, $args) = @_;
    my ($chart_id, $joins) = @$args{qw(chart_id joins)};
    
    $self->_join_flag_tables($args);
    my $flags = "flags_$chart_id";
    my $map_table = "map_flag_setters_$chart_id";
    my $profiles_join = {
        table => 'profiles',
        as    => $map_table,
        from  => "$flags.setter_id",
        to    => 'userid',
    };
    push(@$joins, $profiles_join);
    $args->{full_field} = "$map_table.login_name";
}

sub _days_elapsed {
    my ($self, $args) = @_;
    my $dbh = Bugzilla->dbh;
    
    $args->{full_field} = "(" . $dbh->sql_to_days('NOW()') . " - " .
                                $dbh->sql_to_days('bugs.delta_ts') . ")";
}

sub _component_nonchanged {
    my ($self, $args) = @_;
    
    $args->{full_field} = "components.name";
    $self->_do_operator_function($args);
    my $term = $args->{term};
    $args->{term} = build_subselect("bugs.component_id",
        "components.id", "components", $args->{term});
}

sub _product_nonchanged {
    my ($self, $args) = @_;
    
    # Generate the restriction condition
    $args->{full_field} = "products.name";
    $self->_do_operator_function($args);
    my $term = $args->{term};
    $args->{term} = build_subselect("bugs.product_id",
        "products.id", "products", $term);
}

sub _classification_nonchanged {
    my ($self, $args) = @_;
    my $joins = $args->{joins};
    
    # This joins the right tables for us.
    $self->_add_extra_column('product');
    
    # Generate the restriction condition    
    $args->{full_field} = "classifications.name";
    $self->_do_operator_function($args);
    my $term = $args->{term};
    $args->{term} = build_subselect("map_product.classification_id",
        "classifications.id", "classifications", $term);
}

sub _keywords_exact {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $value, $operator) =
        @$args{qw(chart_id joins value operator)};
    my $dbh = Bugzilla->dbh;
    
    my @keyword_ids;
    foreach my $word (split(/[\s,]+/, $value)) {
        next if $word eq '';
        my $keyword = Bugzilla::Keyword->check($word);
        push(@keyword_ids, $keyword->id);
    }
    
    # XXX We probably should instead throw an error here if there were
    # just commas in the field.
    if (!@keyword_ids) {
        $args->{term} = '';
        return;
    }
    
    # This is an optimization for anywords and anyexact, since we already know
    # the keyword id from having checked it above.
    if ($operator eq 'anywords' or $operator eq 'anyexact') {
        my $table = "keywords_$chart_id";
        $args->{term} = $dbh->sql_in("$table.keywordid", \@keyword_ids);
        push(@$joins, { table => 'keywords', as => $table });
        return;
    }
    
    $self->_keywords_nonchanged($args);
}

sub _keywords_nonchanged {
    my ($self, $args) = @_;
    my ($chart_id, $joins) =
        @$args{qw(chart_id joins)};

    my $k_table = "keywords_$chart_id";
    my $kd_table = "keyworddefs_$chart_id";
    
    push(@$joins, { table => 'keywords', as => $k_table });
    my $defs_join = {
        table => 'keyworddefs',
        as    => $kd_table,
        from  => "$k_table.keywordid",
        to    => 'id',
    };
    push(@$joins, $defs_join);
    
    $args->{full_field} = "$kd_table.name";
}

# XXX This should be combined with blocked_nonchanged.
sub _dependson_nonchanged {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $field, $operator) =
        @$args{qw(chart_id joins field operator)};
    
    my $table = "dependson_$chart_id";
    my $full_field = "$table.$field";
    $args->{full_field} = $full_field;
    $self->_do_operator_function($args);
    my $term = $args->{term};
    my $dep_join = {
        table => 'dependencies',
        as    => $table,
        to    => 'blocked',
        extra => [$term],
    };
    push(@$joins, $dep_join);
    $args->{term} = "$full_field IS NOT NULL";
}

sub _blocked_nonchanged {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $field, $operator) =
        @$args{qw(chart_id joins field operator)};

    my $table = "blocked_$chart_id";
    my $full_field = "$table.$field";
    $args->{full_field} = $full_field;
    $self->_do_operator_function($args);
    my $term = $args->{term};
    my $dep_join = {
        table => 'dependencies',
        as    => $table,
        to    => 'dependson',
        extra => [$term],
    };
    push(@$joins, $dep_join);
    $args->{term} = "$full_field IS NOT NULL";
}

sub _alias_nonchanged {
    my ($self, $args) = @_;
    $args->{full_field} = "COALESCE(bugs.alias, '')";
    $self->_do_operator_function($args);
}

sub _owner_idle_time_greater_less {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $value, $operator) =
        @$args{qw(chart_id joins value operator)};
    my $dbh = Bugzilla->dbh;
    
    my $table = "idle_$chart_id";
    my $quoted = $dbh->quote(SqlifyDate($value));
    
    my $ld_table = "comment_$table";
    my $act_table = "activity_$table";    
    my $comments_join = {
        table => 'longdescs',
        as    => $ld_table,
        from  => 'assigned_to',
        to    => 'who',
        extra => ["$ld_table.bug_when > $quoted"],
    };
    my $activity_join = {
        table => 'bugs_activity',
        as    => $act_table,
        from  => 'assigned_to',
        to    => 'who',
        extra => ["$act_table.bug_when > $quoted"]
    };
    
    push(@$joins, $comments_join, $activity_join);
    
    if ($operator =~ /greater/) {
        $args->{term} =
            "$ld_table.who IS NULL AND $act_table.who IS NULL";
    } else {
         $args->{term} =
            "$ld_table.who IS NOT NULL OR $act_table.who IS NOT NULL";
    }
}

sub _multiselect_negative {
    my ($self, $args) = @_;
    my ($field, $operator) = @$args{qw(field operator)};

    my $table;
    if ($field eq 'keywords') {
        $table = "keywords LEFT JOIN keyworddefs"
                 . " ON keywords.keywordid = keyworddefs.id";
        $args->{full_field} = "keyworddefs.name";
    }
    else { 
        $table = "bug_$field";
        $args->{full_field} = "$table.value";
    }
    $args->{operator} = $self->_reverse_operator($operator);
    $self->_do_operator_function($args);
    my $term = $args->{term};
    $args->{term} =
        "bugs.bug_id NOT IN (SELECT bug_id FROM $table WHERE $term)";
}

sub _multiselect_multiple {
    my ($self, $args) = @_;
    my ($chart_id, $field, $operator, $value)
        = @$args{qw(chart_id field operator value)};
    my $dbh = Bugzilla->dbh;
    
    my $table = "bug_$field";
    $args->{full_field} = "$table.value";
    
    my @terms;
    foreach my $word (split(/[\s,]+/, $value)) {
        $args->{value} = $word;
        $args->{quoted} = $dbh->quote($value);
        $self->_do_operator_function($args);
        my $term = $args->{term};
        push(@terms, "bugs.bug_id IN (SELECT bug_id FROM $table WHERE $term)");
    }
    
    if ($operator eq 'anyexact') {
        $args->{term} = join(" OR ", @terms);
    }
    else {
        $args->{term} = join(" AND ", @terms);
    }
}

sub _multiselect_nonchanged {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $field, $operator) =
        @$args{qw(chart_id joins field operator)};

    my $table = "${field}_$chart_id";
    $args->{full_field} = "$table.value";
    push(@$joins, { table => "bug_$field", as => $table });
}

###############################
# Standard Operator Functions #
###############################

sub _simple_operator {
    my ($self, $args) = @_;
    my ($full_field, $quoted, $operator) =
        @$args{qw(full_field quoted operator)};
    my $sql_operator = SIMPLE_OPERATORS->{$operator};
    $args->{term} = "$full_field $sql_operator $quoted";
}

sub _casesubstring {
    my ($self, $args) = @_;
    my ($full_field, $quoted) = @$args{qw(full_field quoted)};
    my $dbh = Bugzilla->dbh;
    
    $args->{term} = $dbh->sql_position($quoted, $full_field) . " > 0";
}

sub _substring {
    my ($self, $args) = @_;
    my ($full_field, $quoted) = @$args{qw(full_field quoted)};
    my $dbh = Bugzilla->dbh;
    
    # XXX This should probably be changed to just use LIKE
    $args->{term} = $dbh->sql_iposition($quoted, $full_field) . " > 0";
}

sub _notsubstring {
    my ($self, $args) = @_;
    my ($full_field, $quoted) = @$args{qw(full_field quoted)};
    my $dbh = Bugzilla->dbh;
    
    # XXX This should probably be changed to just use NOT LIKE
    $args->{term} = $dbh->sql_iposition($quoted, $full_field) . " = 0";
}

sub _regexp {
    my ($self, $args) = @_;
    my ($full_field, $quoted) = @$args{qw(full_field quoted)};
    my $dbh = Bugzilla->dbh;
    
    $args->{term} = $dbh->sql_regexp($full_field, $quoted);
}

sub _notregexp {
    my ($self, $args) = @_;
    my ($full_field, $quoted) = @$args{qw(full_field quoted)};
    my $dbh = Bugzilla->dbh;
    
    $args->{term} = $dbh->sql_not_regexp($full_field, $quoted);
}

sub _anyexact {
    my ($self, $args) = @_;
    my ($field, $full_field) = @$args{qw(field full_field)};
    my $dbh = Bugzilla->dbh;
    
    my @list = $self->_all_values($args, ',');
    @list = map { $dbh->quote($_) } @list;
    
    if (@list) {
        $args->{term} = $dbh->sql_in($full_field, \@list);
    }
    else {
        $args->{term} = '';
    }
}

sub _anywordsubstr {
    my ($self, $args) = @_;
    my ($full_field, $value) = @$args{qw(full_field value)};
    
    my $list = GetByWordListSubstr($full_field, $value);
    $args->{term} = join(" OR ", @$list);
}

sub _allwordssubstr {
    my ($self, $args) = @_;
    my ($full_field, $value) = @$args{qw(full_field value)};
    
    my $list = GetByWordListSubstr($full_field, $value);
    $args->{term} = join(" AND ", @$list);
}

sub _nowordssubstr {
    my ($self, $args) = @_;
    $self->_anywordsubstr($args);
    my $term = $args->{term};
    $args->{term} = "NOT($term)";
}

sub _anywords {
    my ($self, $args) = @_;
    my ($full_field, $value) = @$args{qw(full_field value)};
    
    my $list = GetByWordList($full_field, $value);
    $args->{term} = join(" OR ", @$list);
}

sub _allwords {
    my ($self, $args) = @_;
    my ($full_field, $value) = @$args{qw(full_field value)};
    
    my $list = GetByWordList($full_field, $value);
    $args->{term} = join(" AND ", @$list);
}

sub _nowords {
    my ($self, $args) = @_;
    $self->_anywords($args);
    my $term = $args->{term};
    $args->{term} = "NOT($term)";
}

sub _changedbefore_changedafter {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $field, $operator, $value) =
        @$args{qw(chart_id joins field operator value)};
    my $dbh = Bugzilla->dbh;
    
    my $sql_operator = ($operator =~ /before/) ? '<=' : '>=';
    my $field_object = $self->_chart_fields->{$field}
        || ThrowCodeError("invalid_field_name", { field => $field });
    my $field_id = $field_object->id;
    # Charts on changed* fields need to be field-specific. Otherwise,
    # OR chart rows make no sense if they contain multiple fields.
    my $table = "act_${field_id}_$chart_id";

    my $sql_date = $dbh->quote(SqlifyDate($value));
    my $join = {
        table => 'bugs_activity',
        as    => $table,
        extra => ["$table.fieldid = $field_id",
                  "$table.bug_when $sql_operator $sql_date"],
    };
    push(@$joins, $join);
    $args->{term} = "$table.bug_when IS NOT NULL";
}

sub _changedfrom_changedto {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $field, $operator, $quoted) =
        @$args{qw(chart_id joins field operator quoted)};
    
    my $column = ($operator =~ /from/) ? 'removed' : 'added';
    my $field_object = $self->_chart_fields->{$field}
        || ThrowCodeError("invalid_field_name", { field => $field });
    my $field_id = $field_object->id;
    my $table = "act_${field_id}_$chart_id";
    my $join = {
        table => 'bugs_activity',
        as    => $table,
        extra => ["$table.fieldid = $field_id",
                  "$table.$column = $quoted"],
    };
    push(@$joins, $join);

    $args->{term} = "$table.bug_when IS NOT NULL";
}

sub _changedby {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $field, $operator, $value) =
        @$args{qw(chart_id joins field operator value)};
    
    my $field_object = $self->_chart_fields->{$field}
        || ThrowCodeError("invalid_field_name", { field => $field });
    my $field_id = $field_object->id;
    my $table = "act_${field_id}_$chart_id";
    my $user_id  = login_to_id($value, THROW_ERROR);
    my $join = {
        table => 'bugs_activity',
        as    => $table,
        extra => ["$table.fieldid = $field_id",
                  "$table.who = $user_id"],
    };
    push(@$joins, $join);
    $args->{term} = "$table.bug_when IS NOT NULL";
}

1;
