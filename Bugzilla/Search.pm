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

use Date::Format;
use Date::Parse;

use Storable qw(dclone);

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
        _default => \&_attachments,
    },
    blocked => {
        _non_changed => \&_blocked_nonchanged,
    },
    bug_group => {
        _non_changed => \&_bug_group_nonchanged,
    },
    changedin => {
        _default => \&_changedin_days_elapsed,
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
        _default => \&_changedin_days_elapsed,
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

# Backwards compatibility for times that we changed the names of fields.
use constant FIELD_MAP => {
    long_desc => 'longdesc',
};

# A SELECTed expression that we use as a placeholder if somebody selects
# <none> for the X, Y, or Z axis in report.cgi.
use constant EMPTY_COLUMN => '-1';

# Some fields are not sorted on themselves, but on other fields. 
# We need to have a list of these fields and what they map to.
# Each field points to an array that contains the fields mapped 
# to, in order.
use constant SPECIAL_ORDER => {
    'target_milestone' => [ 'ms_order.sortkey','ms_order.value' ],
};

# When we add certain fields to the ORDER BY, we need to then add a
# table join to the FROM statement. This hash maps input fields to 
# the join statements that need to be added.
use constant SPECIAL_ORDER_JOIN => {
    'target_milestone' => 'LEFT JOIN milestones AS ms_order ON ms_order.value = bugs.target_milestone AND ms_order.product_id = bugs.product_id',
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
    my $actual_time = '(SUM(ldtime.work_time)'
        . ' * COUNT(DISTINCT ldtime.bug_when)/COUNT(bugs.bug_id))';
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
            . $dbh->sql_string_concat('flagtypes.name', 'flags.status')),

        'keywords' => $dbh->sql_group_concat('DISTINCT keyworddefs.name'),
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
        if (!Bugzilla->user->id) {
             $sql = $dbh->sql_string_until($sql, $dbh->quote('@'));
        }
        $special_sql{$col} = $sql;
        $columns{"${col}_realname"}->{name} = "map_${col}.realname";
    }

    foreach my $col (@id_fields) {
        $special_sql{$col} = "map_${col}s.name";
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
                'DISTINCT map_bug_' . $field->name . '.value');
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

# Create a new Search
# Note that the param argument may be modified by Bugzilla::Search
sub new {
    my $invocant = shift;
    my $class = ref($invocant) || $invocant;
  
    my $self = { @_ };
    bless($self, $class);

    $self->init();
 
    return $self;
}

sub init {
    my $self = shift;
    my @fields = @{ $self->{'fields'} || [] };
    my $params = $self->{'params'};
    $params->convert_old_params();
    $self->{'user'} ||= Bugzilla->user;
    my $user = $self->{'user'};

    my @inputorder = @{ $self->{'order'} || [] };
    my @orderby;

    my @supptables;
    my @wherepart;
    my @having;
    my @groupby;
    my @specialchart;
    my @andlist;

    my %special_order      = %{SPECIAL_ORDER()};
    my %special_order_join = %{SPECIAL_ORDER_JOIN()};

    my @select_fields = 
        Bugzilla->get_fields({ type => FIELD_TYPE_SINGLE_SELECT });
    
    my @multi_select_fields = Bugzilla->get_fields({
        type     => [FIELD_TYPE_MULTI_SELECT, FIELD_TYPE_BUG_URLS],
        obsolete => 0 });
    foreach my $field (@select_fields) {
        next if $field->is_abnormal;
        my $name = $field->name;
        $special_order{$name} = [ "$name.sortkey", "$name.value" ],
        $special_order_join{$name} =
           "LEFT JOIN $name ON $name.value = bugs.$name";
    }

    my $dbh = Bugzilla->dbh;
   
    # All items that are in the ORDER BY must be in the SELECT.
    foreach my $orderitem (@inputorder) {
        my $column_name = split_order_term($orderitem);
        if (!grep($_ eq $column_name, @fields)) {
            push(@fields, $column_name);
        }
    }
 
    # First, deal with all the old hard-coded non-chart-based poop.
    if (grep(/^assigned_to/, @fields)) {
        push @supptables, "INNER JOIN profiles AS map_assigned_to " .
                          "ON bugs.assigned_to = map_assigned_to.userid";
    }

    if (grep(/^reporter/, @fields)) {
        push @supptables, "INNER JOIN profiles AS map_reporter " .
                          "ON bugs.reporter = map_reporter.userid";
    }

    if (grep(/^qa_contact/, @fields)) {
        push @supptables, "LEFT JOIN profiles AS map_qa_contact " .
                          "ON bugs.qa_contact = map_qa_contact.userid";
    }

    if (grep($_ eq 'product' || $_ eq 'classification', @fields)) 
    {
        push @supptables, "INNER JOIN products AS map_products " .
                          "ON bugs.product_id = map_products.id";
    }

    if (grep($_ eq 'classification', @fields)) {
        push @supptables,
                "INNER JOIN classifications AS map_classifications " .
                "ON map_products.classification_id = map_classifications.id";
    }

    if (grep($_ eq 'component', @fields)) {
        push @supptables, "INNER JOIN components AS map_components " .
                          "ON bugs.component_id = map_components.id";
    }
    
    if (grep($_ eq 'actual_time' || $_ eq 'percentage_complete', @fields)) {
        push(@supptables, "LEFT JOIN longdescs AS ldtime " .
                          "ON ldtime.bug_id = bugs.bug_id");
    }
    foreach my $field (@multi_select_fields) {
        my $field_name = $field->name;
        next if !grep($_ eq $field_name, @fields);
        push(@supptables, "LEFT JOIN bug_$field_name AS map_bug_$field_name"
                          . " ON map_bug_$field_name.bug_id = bugs.bug_id");
    }

    if (grep($_ eq 'flagtypes.name', @fields)) {
        push(@supptables, "LEFT JOIN flags ON flags.bug_id = bugs.bug_id AND attach_id IS NULL");
        push(@supptables, "LEFT JOIN flagtypes ON flagtypes.id = flags.type_id");
    }

    if (grep($_ eq 'keywords', @fields)) {
        push(@supptables, "LEFT JOIN keywords ON keywords.bug_id = bugs.bug_id");
        push(@supptables, "LEFT JOIN keyworddefs ON keyworddefs.id = keywords.keywordid");
    }
    
    # Calculating percentage_complete requires remaining_time. Mostly,
    # we just need remaining_time in the GROUP_BY, but it simplifies
    # things to just add it in the SELECT.
    if (grep($_ eq 'percentage_complete', @fields)
        and !grep($_ eq 'remaining_time', @fields))
    {
        push(@fields, 'remaining_time');
    }

    # If the user has selected all of either status or resolution, change to
    # selecting none. This is functionally equivalent, but quite a lot faster.
    # Also, if the status is __open__ or __closed__, translate those
    # into their equivalent lists of open and closed statuses.
    if ($params->param('bug_status')) {
        my @bug_statuses = $params->param('bug_status');
        # Also include inactive bug statuses, as you can query them.
        my @legal_statuses =
          map {$_->name} @{Bugzilla::Field->new({name => 'bug_status'})->legal_values};

        # Filter out any statuses that have been removed completely that are still 
        # being used by the client
        my @valid_statuses;
        foreach my $status (@bug_statuses) {
            push(@valid_statuses, $status) if grep($_ eq $status, @legal_statuses);
        }
        
        if (scalar(@valid_statuses) == scalar(@legal_statuses)
            || $bug_statuses[0] eq "__all__")
        {
            $params->delete('bug_status');
        }
        elsif ($bug_statuses[0] eq '__open__') {
            $params->param('bug_status', grep(is_open_state($_), 
                                              @legal_statuses));
        }
        elsif ($bug_statuses[0] eq "__closed__") {
            $params->param('bug_status', grep(!is_open_state($_), 
                                              @legal_statuses));
        }
        else {
            $params->param('bug_status', @valid_statuses);
        }
    }
    
    if ($params->param('resolution')) {
        my @resolutions = $params->param('resolution');
        # Also include inactive resolutions, as you can query them.
        my $legal_resolutions = Bugzilla::Field->new({name => 'resolution'})->legal_values;
        if (scalar(@resolutions) == scalar(@$legal_resolutions)) {
            $params->delete('resolution');
        }
    }
    
    # All fields that don't have a . in their name should be specifyable
    # in the URL directly.
    my @legal_fields = grep { $_->name !~ /\./ } Bugzilla->get_fields;
    if (!$user->is_timetracker) {
        foreach my $field (TIMETRACKING_FIELDS) {
            @legal_fields = grep { $_->name ne $field } @legal_fields;
        }
    }

    foreach my $field ($params->param()) {
        if (grep { $_->name eq $field } @legal_fields) {
            my $type = $params->param("${field}_type");
            if (!$type) {
                if ($field eq 'keywords') {
                    $type = 'anywords';
                }
                else {
                    $type = 'anyexact';
                }
            }
            $type = 'matches' if $field eq 'content';
            push(@specialchart, [$field, $type,
                                 join(',', $params->param($field))]);
        }
    }

    foreach my $id (1, 2, 3) {
        if (!defined ($params->param("email$id"))) {
            next;
        }
        my $email = trim($params->param("email$id"));
        if ($email eq "") {
            next;
        }
        my $type = $params->param("emailtype$id");
        $type = "anyexact" if ($type eq "exact");

        my @clist;
        foreach my $field ("assigned_to", "reporter", "cc", "qa_contact") {
            if ($params->param("email$field$id")) {
                push(@clist, $field, $type, $email);
            }
        }
        if ($params->param("emaillongdesc$id")) {
                push(@clist, "commenter", $type, $email);
        }
        if (@clist) {
            push(@specialchart, \@clist);
        }
        else {
            # No field is selected. Nothing to see here.
            next;
        }

        if ($type eq "anyexact") {
            foreach my $name (split(',', $email)) {
                $name = trim($name);
                login_to_id($name, THROW_ERROR) if $name;
            }
        }
    }

    my $chfieldfrom = trim(lc($params->param('chfieldfrom') || ''));
    my $chfieldto = trim(lc($params->param('chfieldto') || ''));
    $chfieldfrom = '' if ($chfieldfrom eq 'now');
    $chfieldto = '' if ($chfieldto eq 'now');
    my @chfield = $params->param('chfield');
    my $chvalue = trim($params->param('chfieldvalue')) || '';

    # 2003-05-20: The 'changedin' field is no longer in the UI, but we continue
    # to process it because it will appear in stored queries and bookmarks.
    my $changedin = trim($params->param('changedin')) || '';
    if ($changedin) {
        if ($changedin !~ /^[0-9]*$/) {
            ThrowUserError("illegal_changed_in_last_x_days",
                              { value => $changedin });
        }

        if (!$chfieldfrom
            && !$chfieldto
            && scalar(@chfield) == 1
            && $chfield[0] eq "[Bug creation]")
        {
            # Deal with the special case where the query is using changedin
            # to get bugs created in the last n days by converting the value
            # into its equivalent for the chfieldfrom parameter.
            $chfieldfrom = "-" . ($changedin - 1) . "d";
        }
        else {
            # Oh boy, the general case.  Who knows why the user included
            # the changedin parameter, but do our best to comply.
            push(@specialchart, ["changedin", "lessthan", $changedin + 1]);
        }
    }

    if ($chfieldfrom ne '' || $chfieldto ne '') {
        my $sql_chfrom = $chfieldfrom ? $dbh->quote(SqlifyDate($chfieldfrom)):'';
        my $sql_chto   = $chfieldto   ? $dbh->quote(SqlifyDate($chfieldto))  :'';
        my $sql_chvalue = $chvalue ne '' ? $dbh->quote($chvalue) : '';
        trick_taint($sql_chvalue);
        if(!@chfield) {
            if ($sql_chfrom) {
                my $term = "bugs.delta_ts >= $sql_chfrom";
                push(@wherepart, $term);
                $self->search_description({
                    field => 'delta_ts', type => 'greaterthaneq',
                    value => $chfieldfrom, term => $term,
                });
            }
            if ($sql_chto) {
                my $term = "bugs.delta_ts <= $sql_chto";
                push(@wherepart, $term);
                $self->search_description({
                    field => 'delta_ts', type => 'lessthaneq',
                    value => $chfieldto, term => $term,
                });
            }
        } else {
            my $bug_creation_clause;
            my @list;
            my @actlist;
            foreach my $f (@chfield) {
                if ($f eq "[Bug creation]") {
                    # Treat [Bug creation] differently because we need to look
                    # at bugs.creation_ts rather than the bugs_activity table.
                    my @l;
                    if ($sql_chfrom) {
                        my $term = "bugs.creation_ts >= $sql_chfrom";
                        push(@l, $term);
                        $self->search_description({
                            field => 'creation_ts', type => 'greaterthaneq',
                            value => $chfieldfrom, term => $term,
                        });
                    }
                    if ($sql_chto) {
                        my $term = "bugs.creation_ts <= $sql_chto";
                        push(@l, $term);
                        $self->search_description({
                            field => 'creation_ts', type => 'lessthaneq',
                            value => $chfieldto, term => $term,
                        });
                    }
                    $bug_creation_clause = "(" . join(' AND ', @l) . ")";
                } else {
                    push(@actlist, get_field_id($f));
                }
            }

            # @actlist won't have any elements if the only field being searched
            # is [Bug creation] (in which case we don't need bugs_activity).
            if(@actlist) {
                my $extra = " actcheck.bug_id = bugs.bug_id";
                push(@list, "(actcheck.bug_when IS NOT NULL)");

                my $from_term = " AND actcheck.bug_when >= $sql_chfrom";
                $extra .= $from_term if $sql_chfrom;
                my $to_term = " AND actcheck.bug_when <= $sql_chto";
                $extra .= $to_term if $sql_chto;
                my $value_term = " AND actcheck.added = $sql_chvalue";
                $extra .= $value_term if $sql_chvalue;

                push(@supptables, "LEFT JOIN bugs_activity AS actcheck " .
                                  "ON $extra AND " 
                                 . $dbh->sql_in('actcheck.fieldid', \@actlist));

                foreach my $field (@chfield) {
                    next if $field eq "[Bug creation]";
                    if ($sql_chvalue) {
                        $self->search_description({
                            field => $field, type => 'changedto',
                            value => $chvalue, term  => $value_term,
                        });
                    }
                    if ($sql_chfrom) {
                        $self->search_description({
                            field => $field, type => 'changedafter',
                            value => $chfieldfrom, term => $from_term,
                        });
                    }
                    if ($sql_chvalue) {
                        $self->search_description({
                            field => $field, type => 'changedbefore',
                            value => $chfieldto, term => $to_term,
                        });
                    }
                }
            }

            # Now that we're done using @list to determine if there are any
            # regular fields to search (and thus we need bugs_activity),
            # add the [Bug creation] criterion to the list so we can OR it
            # together with the others.
            push(@list, $bug_creation_clause) if $bug_creation_clause;

            push(@wherepart, "(" . join(" OR ", @list) . ")");
        }
    }

    my $sql_deadlinefrom;
    my $sql_deadlineto;
    if ($user->is_timetracker) {
      my $deadlinefrom;
      my $deadlineto;
            
      if ($params->param('deadlinefrom')){
        $params->param('deadlinefrom', '') if lc($params->param('deadlinefrom')) eq 'now';
        $deadlinefrom = SqlifyDate($params->param('deadlinefrom'));
        $sql_deadlinefrom = $dbh->quote($deadlinefrom);
        trick_taint($sql_deadlinefrom);
        my $term = "bugs.deadline >= $sql_deadlinefrom";
        push(@wherepart, $term);
        $self->search_description({
            field => 'deadline', type => 'greaterthaneq',
            value => $deadlinefrom, term => $term,
        });
      }
      
      if ($params->param('deadlineto')){
        $params->param('deadlineto', '') if lc($params->param('deadlineto')) eq 'now';
        $deadlineto = SqlifyDate($params->param('deadlineto'));
        $sql_deadlineto = $dbh->quote($deadlineto);
        trick_taint($sql_deadlineto);
        my $term = "bugs.deadline <= $sql_deadlineto";
        push(@wherepart, $term);
        $self->search_description({
            field => 'deadline', type => 'lessthaneq',
            value => $deadlineto, term => $term,
        });
      }
    }  

    foreach my $f ("short_desc", "longdesc", "bug_file_loc",
                   "status_whiteboard") {
        if (defined $params->param($f)) {
            my $s = trim($params->param($f));
            if ($s ne "") {
                my $type = $params->param($f . "_type");
                push(@specialchart, [$f, $type, $s]);
            }
        }
    }

    # first we delete any sign of "Chart #-1" from the HTML form hash
    # since we want to guarantee the user didn't hide something here
    my @badcharts = grep /^(field|type|value)-1-/, $params->param();
    foreach my $field (@badcharts) {
        $params->delete($field);
    }

    # now we take our special chart and stuff it into the form hash
    my $chart = -1;
    my $row = 0;
    foreach my $ref (@specialchart) {
        my $col = 0;
        while (@$ref) {
            $params->param("field$chart-$row-$col", shift(@$ref));
            $params->param("type$chart-$row-$col", shift(@$ref));
            $params->param("value$chart-$row-$col", shift(@$ref));
            $col++;

        }
        $row++;
    }


# A boolean chart is a way of representing the terms in a logical
# expression.  Bugzilla builds SQL queries depending on how you enter
# terms into the boolean chart. Boolean charts are represented in
# urls as tree-tuples of (chart id, row, column). The query form
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

# $chartid is the number of the current chart whose SQL we're constructing
# $row is the current row of the current chart

# names for table aliases are constructed using $chartid and $row
#   SELECT blah  FROM $table "$table_$chartid_$row" WHERE ....

# $f  = field of table in bug db (e.g. bug_id, reporter, etc)
# $ff = qualified field name (field name prefixed by table)
#       e.g. bugs_activity.bug_id
# $t  = type of query. e.g. "equal to", "changed after", case sensitive substr"
# $v  = value - value the user typed in to the form
# $q  = sanitized version of user input trick_taint(($dbh->quote($v)))
# @supptables = Tables and/or table aliases used in query
# %suppseen   = A hash used to store all the tables in supptables to weed
#               out duplicates.
# @supplist   = A list used to accumulate all the JOIN clauses for each
#               chart to merge the ON sections of each.
# $suppstring = String which is pasted into query containing all table names

    # get a list of field names to verify the user-submitted chart fields against
    my %chartfields = @{$dbh->selectcol_arrayref(
        q{SELECT name, id FROM fielddefs}, { Columns=>[1,2] })};

    if (!$user->is_timetracker) {
        foreach my $tt_field (TIMETRACKING_FIELDS) {
            delete $chartfields{$tt_field};
        }
    }

    my ($sequence, $chartid);
    $row = 0;
    for ($chart=-1 ;
         $chart < 0 || $params->param("field$chart-0-0") ;
         $chart++) 
    {
        $chartid = $chart >= 0 ? $chart : "";
        my @chartandlist;
        for ($row = 0 ;
             $params->param("field$chart-$row-0") ;
             $row++) 
        {
            my @orlist;
            for (my $col = 0 ;
                 $params->param("field$chart-$row-$col") ;
                 $col++) 
            {
                my $field = $params->param("field$chart-$row-$col") || "noop";
                my $operator = $params->param("type$chart-$row-$col") || "noop";
                my $value = $params->param("value$chart-$row-$col");
                $value = "" if !defined $value;
                $value = trim($value);
                next if ($field eq "noop" || $operator eq "noop" 
                         || $value eq "");

                # chart -1 is generated by other code above, not from the user-
                # submitted form, so we'll blindly accept any values in chart -1
                if (!$chartfields{$field} and $chart != -1) {
                    ThrowCodeError("invalid_field_name", { field => $field });
                }

                # This is either from the internal chart (in which case we
                # already know about it), or it was in %chartfields, so it is
                # a valid field name, which means that it's ok.
                trick_taint($field);
                my $quoted = $dbh->quote($value);
                trick_taint($quoted);

                my $full_field = $field =~ /\./ ? $field : "bugs.$field";
                my %search_args = (
                    chart_id   => $chartid,
                    sequence   => $sequence,
                    field      => $field,
                    full_field => $full_field,
                    operator   => $operator,
                    value      => $value,
                    quoted     => $quoted,
                    multi_fields => \@multi_select_fields,
                    joins        => \@supptables,
                    where        => \@wherepart,
                    having       => \@having,
                    group_by     => \@groupby,
                    fields       => \@fields,
                    chart_fields => \%chartfields,
                );
                # This should add a "term" selement to %search_args.
                $self->do_search_function(\%search_args);
                
                if ($search_args{term}) {
                    # All the things here that don't get pulled out of
                    # %search_args are their original values before
                    # do_search_function modified them.
                    $self->search_description({
                        field => $field, type => $operator,
                        value => $value, term => $search_args{term},
                    });
                    push(@orlist, $search_args{term});
                }
                else {
                    # This field and this type don't work together.
                    ThrowUserrror("search_field_operator_invalid",
                                   { field => $field, operator => $operator });
                }
            }
            if (@orlist) {
                @orlist = map("($_)", @orlist) if (scalar(@orlist) > 1);
                push(@chartandlist, "(" . join(" OR ", @orlist) . ")");
            }
        }
        if (@chartandlist) {
            if ($params->param("negate$chart")) {
                push(@andlist, "NOT(" . join(" AND ", @chartandlist) . ")");
            } else {
                push(@andlist, "(" . join(" AND ", @chartandlist) . ")");
            }
        }
    }

    # The ORDER BY clause goes last, but can require modifications
    # to other parts of the query, so we want to create it before we
    # write the FROM clause.
    foreach my $orderitem (@inputorder) {
        BuildOrderBy(\%special_order, $orderitem, \@orderby);
    }
    # Now JOIN the correct tables in the FROM clause.
    # This is done separately from the above because it's
    # cleaner to do it this way.
    foreach my $orderitem (@inputorder) {
        # Grab the part without ASC or DESC.
        my $column_name = split_order_term($orderitem);
        if ($special_order_join{$column_name}) {
            push(@supptables, $special_order_join{$column_name});
        }
    }

    my %suppseen = ("bugs" => 1);
    my $suppstring = "bugs";
    my @supplist = (" ");
    foreach my $str (@supptables) {

        if ($str =~ /^(LEFT|INNER|RIGHT)\s+JOIN/i) {
            $str =~ /^(.*?)\s+ON\s+(.*)$/i;
            my ($leftside, $rightside) = ($1, $2);
            if (defined $suppseen{$leftside}) {
                $supplist[$suppseen{$leftside}] .= " AND ($rightside)";
            } else {
                $suppseen{$leftside} = scalar @supplist;
                push @supplist, " $leftside ON ($rightside)";
            }
        } else {
            # Do not accept implicit joins using comma operator
            # as they are not DB agnostic
            ThrowCodeError("comma_operator_deprecated");
        }
    }
    $suppstring .= join('', @supplist);
    
    # Make sure we create a legal SQL query.
    @andlist = ("1 = 1") if !@andlist;

    my @sql_fields;
    foreach my $field (@fields) {
        my $alias = $field;
        # Aliases cannot contain dots in them. We convert them to underscores.
        $alias =~ s/\./_/g;
        my $sql_field = ($field eq EMPTY_COLUMN) ? EMPTY_COLUMN
                                                 : COLUMNS->{$field}->{name} . " AS $alias";
        push(@sql_fields, $sql_field);
    }
    my $query = "SELECT " . join(', ', @sql_fields) .
                " FROM $suppstring" .
                " LEFT JOIN bug_group_map " .
                " ON bug_group_map.bug_id = bugs.bug_id ";

    if ($user->id) {
        if (scalar @{ $user->groups }) {
            $query .= " AND bug_group_map.group_id NOT IN (" 
                   . $user->groups_as_string . ") ";
        }

        $query .= " LEFT JOIN cc ON cc.bug_id = bugs.bug_id AND cc.who = " . $user->id;
    }

    $query .= " WHERE " . join(' AND ', (@wherepart, @andlist)) .
              " AND bugs.creation_ts IS NOT NULL AND ((bug_group_map.group_id IS NULL)";

    if ($user->id) {
        my $userid = $user->id;
        $query .= "    OR (bugs.reporter_accessible = 1 AND bugs.reporter = $userid) " .
              "    OR (bugs.cclist_accessible = 1 AND cc.who IS NOT NULL) " .
              "    OR (bugs.assigned_to = $userid) ";
        if (Bugzilla->params->{'useqacontact'}) {
            $query .= "OR (bugs.qa_contact = $userid) ";
        }
    }

    # For some DBs, every field in the SELECT must be in the GROUP BY.
    foreach my $field (@fields) {
        # These fields never go into the GROUP BY (bug_id goes in
        # explicitly, below).
        next if (grep($_ eq $field, EMPTY_COLUMN, 
                      qw(bug_id actual_time percentage_complete flagtypes.name keywords)));
        my $col = COLUMNS->{$field}->{name};
        push(@groupby, $col) if !grep($_ eq $col, @groupby);
    }
    # And all items from ORDER BY must be in the GROUP BY. The above loop 
    # doesn't catch items that were put into the ORDER BY from SPECIAL_ORDER.
    foreach my $item (@inputorder) {
        my $column_name = split_order_term($item);
        if ($special_order{$column_name}) {
            push(@groupby, @{ $special_order{$column_name} });
        }
    }
    $query .= ") " . $dbh->sql_group_by("bugs.bug_id", join(', ', @groupby));


    if (@having) {
        $query .= " HAVING " . join(" AND ", @having);
    }

    if (@orderby) {
        $query .= " ORDER BY " . join(',', @orderby);
    }

    $self->{'sql'} = $query;
}

###############################################################################
# Helper functions for the init() method.
###############################################################################

# This takes information about the current boolean chart and translates
# it into SQL, using the constants at the top of this file.
sub do_search_function {
    my ($self, $args) = @_;
    my ($field, $operator, $value) = @$args{qw(field operator value)};
    
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
        if (grep { $_->name eq $actual_field } @{ $args->{multi_fields} }) {
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

sub getSQL {
    my $self = shift;
    return $self->{'sql'};
}

sub search_description {
    my ($self, $params) = @_;
    my $desc = $self->{'search_description'} ||= [];
    if ($params) {
        push(@$desc, $params);
    }
    return $self->{'search_description'};
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

# Validate that the query type is one we can deal with
sub IsValidQueryType
{
    my ($queryType) = @_;
    if (grep { $_ eq $queryType } qw(specific advanced)) {
        return 1;
    }
    return 0;
}

# BuildOrderBy - Private Subroutine
# This function converts the input order to an "output" order,
# suitable for concatenation to form an ORDER BY clause. Basically,
# it just handles fields that have non-standard sort orders from
# %specialorder.
# Arguments:
#  $orderitem - A string. The next value to append to the ORDER BY clause,
#      in the format of an item in the 'order' parameter to
#      Bugzilla::Search.
#  $stringlist - A reference to the list of strings that will be join()'ed
#      to make ORDER BY. This is what the subroutine modifies.
#  $reverseorder - (Optional) A boolean. TRUE if we should reverse the order
#      of the field that we are given (from ASC to DESC or vice-versa).
#
# Explanation of $reverseorder
# ----------------------------
# The role of $reverseorder is to handle things like sorting by
# "target_milestone DESC".
# Let's say that we had a field "A" that normally translates to a sort 
# order of "B ASC, C DESC". If we sort by "A DESC", what we really then
# mean is "B DESC, C ASC". So $reverseorder is only used if we call 
# BuildOrderBy recursively, to let it know that we're "reversing" the 
# order. That is, that we wanted "A DESC", not "A".
sub BuildOrderBy {
    my ($special_order, $orderitem, $stringlist, $reverseorder) = (@_);

    my ($orderfield, $orderdirection) = split_order_term($orderitem);

    if ($reverseorder) {
        # If orderdirection is empty or ASC...
        if (!$orderdirection || $orderdirection =~ m/asc/i) {
            $orderdirection = "DESC";
        } else {
            # This has the minor side-effect of making any reversed invalid
            # direction into ASC.
            $orderdirection = "ASC";
        }
    }

    # Handle fields that have non-standard sort orders, from $specialorder.
    if ($special_order->{$orderfield}) {
        foreach my $subitem (@{$special_order->{$orderfield}}) {
            # DESC on a field with non-standard sort order means
            # "reverse the normal order for each field that we map to."
            BuildOrderBy($special_order, $subitem, $stringlist,
                         $orderdirection =~ m/desc/i);
        }
        return;
    }
    # Aliases cannot contain dots in them. We convert them to underscores.
    $orderfield =~ s/\./_/g if exists COLUMNS->{$orderfield};

    push(@$stringlist, trim($orderfield . ' ' . $orderdirection));
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
    my $user = $self->{'user'};
    
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
    my $join_sql =
        "LEFT JOIN user_group_map AS $table"
        .     " ON $table.user_id = bugs.$field"
        .        " AND " . $dbh->sql_in("$table.group_id", $group_ids)
        .        " AND $table.isbless = 0";
    push(@$joins, $join_sql);
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
    my $joins = $args->{joins};
    
    push(@$joins, "LEFT JOIN profiles AS map_qa_contact " .
                         "ON bugs.qa_contact = map_qa_contact.userid");
    $args->{full_field} = "COALESCE(map_qa_contact.login_name,'')";
}

sub _cc_pronoun {
    my ($self, $args) = @_;
    my ($full_field, $value) = @$args{qw(full_field value)};
    my $user = $self->{'user'};

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
    my $user = $self->{'user'};
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
    
    my $group_table = "user_group_map_$chart_id";
    my $cc_table = "cc_$chart_id";
    push(@$joins, "LEFT JOIN cc AS $cc_table " .
                         "ON bugs.bug_id = $cc_table.bug_id");
    my $join_sql =
        "LEFT JOIN user_group_map AS $group_table"
        .     " ON $group_table.user_id = $cc_table.who"
        .        " AND " . $dbh->sql_in("$group_table.group_id", $all_groups)
        .        " AND $group_table.isbless = 0 ";
    push(@$joins, $join_sql);
    if ($operator =~ /^not/) {
        $args->{term} = "$group_table.group_id IS NULL";
    }
    else {
        $args->{term} = "$group_table.group_id IS NOT NULL";
    }
}

sub _cc_nonchanged {
    my ($self, $args) = @_;
    my ($chart_id, $sequence, $field, $full_field, $operator, $joins, $value) =
        @$args{qw(chart_id sequence field full_field operator joins value)};

    # This is for the email1, email2, email3 fields from query.cgi.
    if ($chart_id eq "") {
        $chart_id = "CC$$sequence";
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
    my $join_sql =
        "LEFT JOIN cc AS $table"
        .     " ON bugs.bug_id = $table.bug_id"
         .       " AND $table.who IN (SELECT userid FROM profiles WHERE $term)";
    push(@$joins, $join_sql);
    
    $args->{term} = "$table.who IS NOT NULL";
}

# XXX This duplicates having Commenter as a search field.
sub _long_desc_changedby {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $value) = @$args{qw(chart_id joins value)};
    
    my $table = "longdescs_$chart_id";
    push(@$joins, "LEFT JOIN longdescs AS $table " .
                         "ON $table.bug_id = bugs.bug_id");
    my $user_id = login_to_id($value, THROW_ERROR);
    $args->{term} = "$table.who = $user_id";
}

sub _long_desc_changedbefore_after {
    my ($self, $args) = @_;
    my ($chart_id, $operator, $value, $joins) =
        @$args{qw(chart_id operator value joins)};
    my $dbh = Bugzilla->dbh;
    
    my $sql_operator = ($operator =~ /before/) ? '<' : '>';
    my $table = "longdescs_$chart_id";
    my $sql_date = $dbh->quote(SqlifyDate($value));
    my $join_sql =
        "LEFT JOIN longdescs AS $table "
        .        " ON $table.bug_id = bugs.bug_id"
        .           " AND $table.bug_when $sql_operator $sql_date";
    push(@$joins, $join_sql);
    $args->{term} = "$table.bug_when IS NOT NULL";
}

sub _content_matches {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $group_by, $fields, $operator, $value) =
        @$args{qw(chart_id joins group_by fields operator value)};
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
    $comments_col = "comments_noprivate" unless $self->{'user'}->is_insider;
    push(@$joins, "LEFT JOIN bugs_fulltext AS $table " .
                         "ON bugs.bug_id = $table.bug_id");
    
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
    my $user = $self->{'user'};

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
    
    my $extra = $self->{'user'}->is_insider ? "" : "AND $table.isprivate = 0";
    # commenter_pronoun could have changed $full_field to something else,
    # so we only set this if commenter_pronoun hasn't set it.
    if ($full_field eq 'bugs.commenter') {
        $args->{full_field} = "profiles.login_name";
    }
    $self->_do_operator_function($args);
    my $term = $args->{term};
    my $join_sql =
        "LEFT JOIN longdescs AS $table"
        . " ON $table.bug_id = bugs.bug_id $extra"
        .    " AND $table.who IN (SELECT userid FROM profiles WHERE $term)";
    push(@$joins, $join_sql);
    $args->{term} = "$table.who IS NOT NULL";
}

sub _long_desc {
    my ($self, $args) = @_;
    my ($chart_id, $joins) = @$args{qw(chart_id joins)};
    
    my $table = "longdescs_$chart_id";
    my $extra = $self->{'user'}->is_insider ? "" : "AND $table.isprivate = 0";
    push(@$joins, "LEFT JOIN longdescs AS $table " .
                         "ON $table.bug_id = bugs.bug_id $extra");
    $args->{full_field} = "$table.thetext";
}

sub _longdescs_isprivate {
    my ($self, $args) = @_;
    my ($chart_id, $joins) = @$args{qw(chart_id joins)};
    
    my $table = "longdescs_$chart_id";
    my $extra = $self->{'user'}->is_insider ? "" : "AND $table.isprivate = 0";
    push(@$joins, "LEFT JOIN longdescs AS $table " .
                         "ON $table.bug_id = bugs.bug_id $extra");
    $args->{full_field} = "$table.isprivate";
}

sub _work_time_changedby {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $value) = @$args{qw(chart_id joins value)};
    
    my $table = "longdescs_$chart_id";
    push(@$joins, "LEFT JOIN longdescs AS $table " .
                         "ON $table.bug_id = bugs.bug_id");
    my $user_id = login_to_id($value, THROW_ERROR);
    $args->{term} = "$table.who = $user_id AND $table.work_time != 0";
}

sub _work_time_changedbefore_after {
    my ($self, $args) = @_;
    my ($chart_id, $operator, $value, $joins) =
        @$args{qw(chart_id operator value joins)};
    my $dbh = Bugzilla->dbh;
    
    my $table = "longdescs_$chart_id";
    my $sql_operator = ($operator =~ /before/) ? '<' : '>';
    my $sql_date = $dbh->quote(SqlifyDate($value));
    my $join_sql =
        "LEFT JOIN longdescs AS $table"
        .     " ON $table.bug_id = bugs.bug_id"
        .        " AND $table.work_time != 0"
        .        " AND $table.bug_when $sql_operator $sql_date";
    push(@$joins, $join_sql);
    
    $args->{term} = "$table.bug_when IS NOT NULL";
}

sub _work_time {
    my ($self, $args) = @_;
    my ($chart_id, $joins) = @$args{qw(chart_id joins)};
    
    my $table = "longdescs_$chart_id";
    push(@$joins, "LEFT JOIN longdescs AS $table " .
                         "ON $table.bug_id = bugs.bug_id");
    $args->{full_field} = "$table.work_time";
}

sub _percentage_complete {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $operator, $value, $having, $fields) =
        @$args{qw(chart_id joins operator value having fields)};

    my $table = "longdescs_$chart_id";

    # We can't just use "percentage_complete" as the field, because
    # (a) PostgreSQL doesn't accept it in the HAVING clause
    # and (b) it wouldn't work in multiple chart rows, because it uses
    # a fixed name for the table, "ldtime".
    my $expression = COLUMNS->{percentage_complete}->{name};
    $expression =~ s/\bldtime\b/$table/g;
    $args->{full_field} = "($expression)";
    push(@$joins, "LEFT JOIN longdescs AS $table " .
                         "ON $table.bug_id = bugs.bug_id");

    # We need remaining_time in @fields, otherwise we can't use
    # it in the expression for creating percentage_complete.
    if (!grep { $_ eq 'remaining_time' } @$fields) {
        push(@$fields, 'remaining_time');
    }

    $self->_do_operator_function($args);
    push(@$having, $args->{term});
   
    # We put something into $args->{term} so that do_search_function
    # stops processing.
    $args->{term} = "0=0";
}

sub _bug_group_nonchanged {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $field) = @$args{qw(chart_id joins field)};
    
    my $map_table = "bug_group_map_$chart_id";
    push(@$joins,
        "LEFT JOIN bug_group_map AS $map_table " .
               "ON bugs.bug_id = $map_table.bug_id");
    
    my $groups_table = "groups_$chart_id";
    my $full_field = "$groups_table.name";
    $args->{full_field} = $full_field;
    $self->_do_operator_function($args);
    my $term = $args->{term};
    push(@$joins,
        "LEFT JOIN groups AS $groups_table " .
               "ON $groups_table.id = $map_table.group_id AND $term");
    $args->{term} = "$full_field IS NOT NULL";
}

sub _attach_data_thedata {
    my ($self, $args) = @_;
    my ($chart_id, $joins) = @$args{qw(chart_id joins)};
    
    my $attach_table = "attachments_$chart_id";
    my $data_table = "attachdata_$chart_id";
    my $extra = $self->{'user'}->is_insider
                ? "" : "AND $attach_table.isprivate = 0";
    push(@$joins, "LEFT JOIN attachments AS $attach_table " .
                         "ON bugs.bug_id = $attach_table.bug_id $extra");
    push(@$joins, "LEFT JOIN attach_data AS $data_table " .
                       "ON $data_table.id = $attach_table.attach_id");
    $args->{full_field} = "$data_table.thedata";
}

sub _attachments_submitter {
    my ($self, $args) = @_;
    my ($chart_id, $joins) = @$args{qw(chart_id joins)};
    
    my $attach_table = "attachment_submitter_$chart_id";
    my $extra = $self->{'user'}->is_insider
                ? "" : "AND $attach_table.isprivate = 0";
    push(@$joins, "LEFT JOIN attachments AS $attach_table " .
                         "ON bugs.bug_id = $attach_table.bug_id $extra");
    
    my $map_table = "map_attachment_submitter_$chart_id";
    push(@$joins, "LEFT JOIN profiles AS $map_table " .
                         "ON $attach_table.submitter_id = $map_table.userid");
    $args->{full_field} = "$map_table.login_name";
}

sub _attachments {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $field, $operator, $value) =
        @$args{qw(chart_id joins field operator value)};
    my $dbh = Bugzilla->dbh;
    
    my $table = "attachments_$chart_id";
    my $extra = $self->{'user'}->is_insider ? "" : "AND $table.isprivate = 0";
    push(@$joins, "LEFT JOIN attachments AS $table " .
                         "ON bugs.bug_id = $table.bug_id $extra");
    
    $field =~ /^attachments\.(.+)$/;
    my $attach_field = $1;
    # XXX This is not actually the correct method of searching for
    # changes in attachment values--this just tells you who posted an
    # attachment.
    if ($operator eq "changedby") {
        $args->{value} = login_to_id($value, THROW_ERROR);
        $args->{quoted} = $args->{value};
        $attach_field = "submitter_id";
        $args->{operator} = "equals";
    }
    elsif ($operator eq 'changedbefore' or $operator eq 'changedafter') {
        $args->{value} = SqlifyDate($value);
        $args->{quoted} = $dbh->quote($args->{value});
        $attach_field = "creation_ts";
        $args->{operator} = $operator eq 'changedbefore' ? "lessthan"
                                                         : "greaterthan";
    }
    
    $args->{full_field} = "$table.$attach_field";
}

sub _join_flag_tables {
    my ($self, $args) = @_;
    my ($joins, $chart_id) = @$args{qw(joins chart_id)};
    
    my $attachments = "attachments_$chart_id";
    my $extra = $self->{'user'}->is_insider
                ? "" : "AND $attachments.isprivate = 0";
    push(@$joins, "LEFT JOIN attachments AS $attachments " .
                         "ON bugs.bug_id = $attachments.bug_id $extra");
    my $flags = "flags_$chart_id";
    # We join both the bugs and the attachments table in separately,
    # and then the join code will later combine the terms.
    push(@$joins, "LEFT JOIN flags AS $flags " . 
                         "ON bugs.bug_id = $flags.bug_id ");
    push(@$joins, "LEFT JOIN flags AS $flags " .
                         "ON $flags.attach_id = $attachments.attach_id " .
                             "OR $flags.attach_id IS NULL");
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
    push(@$joins, "LEFT JOIN flagtypes AS $flagtypes " . 
                         "ON $flags.type_id = $flagtypes.id");
    
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
       $args->{term} = "0=0";
    }
}

# XXX These two functions can probably be joined (requestees and setters).
sub _requestees_login_name {
    my ($self, $args) = @_;
    my ($chart_id, $joins) = @$args{qw(chart_id joins)};
    
    $self->_join_flag_tables($args);
    my $flags = "flags_$chart_id";
    my $map_table = "map_flag_requestees_$chart_id";
    push(@$joins, "LEFT JOIN profiles AS $map_table " .
                         "ON $flags.requestee_id = $map_table.userid");

    $args->{full_field} = "$map_table.login_name";
}

sub _setters_login_name {
    my ($self, $args) = @_;
    my ($chart_id, $joins) = @$args{qw(chart_id joins)};
    
    $self->_join_flag_tables($args);
    my $flags = "flags_$chart_id";
    my $map_table = "map_flag_setters_$chart_id";
    push(@$joins, "LEFT JOIN profiles AS $map_table " .
                         "ON $flags.setter_id = $map_table.userid");

    $args->{full_field} = "$map_table.login_name";
}

sub _changedin_days_elapsed {
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
    
    # Generate the restriction condition
    push(@$joins, "INNER JOIN products AS map_products " .
                          "ON bugs.product_id = map_products.id");
    $args->{full_field} = "classifications.name";
    $self->_do_operator_function($args);
    my $term = $args->{term};
    $args->{term} = build_subselect("map_products.classification_id",
        "classifications.id", "classifications", $term);
}

sub _keywords_exact {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $value, $operator) =
        @$args{qw(chart_id joins value operator)};
    my $dbh = Bugzilla->dbh;
    
    my @keyword_ids;
    foreach my $value (split(/[\s,]+/, $value)) {
        next if $value eq '';
        my $keyword = Bugzilla::Keyword->check($value);
        push(@keyword_ids, $keyword->id);
    }
    
    # XXX We probably should instead throw an error here if there were
    # just commas in the field.
    if (!@keyword_ids) {
        $args->{term} = "0=0";
        return;
    }
    
    # This is an optimization for anywords, since we already know
    # the keyword id from having checked it above.
    if ($operator eq 'anywords') {
        my $table = "keywords_$chart_id";
        $args->{term} = $dbh->sql_in("$table.keywordid", \@keyword_ids);
        push(@$joins, "LEFT JOIN keywords AS $table"
                      .     " ON $table.bug_id = bugs.bug_id");
        return;
    }
    
    $self->_keywords_nonchanged($args);
}

sub _keywords_nonchanged {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $value, $operator) =
        @$args{qw(chart_id joins value operator)};

    my $k_table = "keywords_$chart_id";
    my $kd_table = "keyworddefs_$chart_id";
    
    push(@$joins, "LEFT JOIN keywords AS $k_table " .
                         "ON $k_table.bug_id = bugs.bug_id");
    push(@$joins, "LEFT JOIN keyworddefs AS $kd_table " .
                         "ON $kd_table.id = $k_table.keywordid");
    
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
    push(@$joins, "LEFT JOIN dependencies AS $table " .
                         "ON $table.blocked = bugs.bug_id AND ($term)");
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
    push(@$joins, "LEFT JOIN dependencies AS $table " .
                         "ON $table.dependson = bugs.bug_id AND ($term)");
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
    my $comments_join =
        "LEFT JOIN longdescs AS $ld_table"
        .     " ON $ld_table.who = bugs.assigned_to"
        .        " AND $ld_table.bug_id = bugs.bug_id"
        .        " AND $ld_table.bug_when > $quoted";
    push(@$joins, $comments_join);

    my $act_table = "activity_$table";
    my $assigned_fieldid = get_field_id('assigned_to');

    # XXX Why are we joining using $assignedto_fieldid here? It shouldn't
    #     matter when or if the assignee changed.
    my $activity_join =
        "LEFT JOIN bugs_activity AS $act_table"
        .     " ON ( $act_table.who = bugs.assigned_to"
        .         "  OR $act_table.fieldid = $assigned_fieldid )"
        .        " AND $act_table.bug_id = bugs.bug_id"
        .        " AND $act_table.bug_when > $quoted";
    push(@$joins, $activity_join);
    
    if ($operator =~ /greater/) {
        $args->{term} =
            "$ld_table.who IS NULL AND $act_table.who IS NULL)";
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
    my ($chart_id, $joins, $field, $operator, $value)
        = @$args{qw(chart_id joins field operator value)};
    
    my $table = "bug_$field";
    $args->{full_field} = "$table.value";
    
    my @terms;
    foreach my $word (split(/[\s,]+/, $value)) {
        $args->{value} = $word;
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
    push(@$joins, "LEFT JOIN bug_$field AS $table " .
                         "ON $table.bug_id = bugs.bug_id ");
}

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
    my ($field, $value, $full_field) = @$args{qw(field value full_field)};
    my $dbh = Bugzilla->dbh;
    
    my @list;
    foreach my $word (split(/,/, $value)) {
        $word = trim($word);
        if ($word eq "---" && $field eq 'resolution') {
            $word = "";
        }
        my $quoted_word = $dbh->quote($word);
        trick_taint($quoted_word);
        push(@list, $quoted_word);
    }
    
    if (@list) {
        $args->{term} = $dbh->sql_in($full_field, \@list);
    }
    # XXX Perhaps if it's all commas, we should just throw an error.
    else {
        $args->{term} = "0=0";
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
    
    my $sql_operator = ($operator =~ /before/) ? '<' : '>';
    my $table = "act_$chart_id";
    my $field_id = get_field_id($field);
    my $sql_date = $dbh->quote(SqlifyDate($value));
    push(@$joins,
        "LEFT JOIN bugs_activity AS $table"
        .     " ON $table.bug_id = bugs.bug_id"
        .         " AND $table.fieldid = $field_id"
        .         " AND $table.bug_when $sql_operator $sql_date");
    $args->{term} = "$table.bug_when IS NOT NULL";
}

sub _changedfrom_changedto {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $field, $operator, $quoted) =
        @$args{qw(chart_id joins field operator quoted)};
    
    my $column = ($operator =~ /from/) ? 'removed' : 'added';
    my $table = "act_$chart_id";
    my $field_id = get_field_id($field);
    push(@$joins,
        "LEFT JOIN bugs_activity AS $table"
        .     " ON $table.bug_id = bugs.bug_id"
        .        " AND $table.fieldid = $field_id"
        .        " AND $table.$column = $quoted");
    $args->{term} = "$table.bug_when IS NOT NULL";
}

sub _changedby {
    my ($self, $args) = @_;
    my ($chart_id, $joins, $field, $operator, $value) =
        @$args{qw(chart_id joins field operator value)};
    
    my $table = "act_$chart_id";
    my $field_id = get_field_id($field);
    my $user_id  = login_to_id($value, THROW_ERROR);
    push(@$joins,
        "LEFT JOIN bugs_activity AS $table"
        .     " ON $table.bug_id = bugs.bug_id"
        .        " AND $table.fieldid = $field_id"
        .        " AND $table.who = $user_id");
    $args->{term} = "$table.bug_when IS NOT NULL";
}

1;
