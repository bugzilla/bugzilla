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
# Contributor(s): C. Begle
#                 Jesse Ruderman
#                 Andreas Franke <afranke@mathweb.org>
#                 Stephen Lee <slee@uk.bnsmc.com>
#                 Marc Schumann <wurblzap@gmail.com>

package Bugzilla::Search::Quicksearch;

# Make it harder for us to do dangerous things in Perl.
use strict;

use Bugzilla::Error;
use Bugzilla::Constants;
use Bugzilla::Keyword;
use Bugzilla::Status;
use Bugzilla::Field;
use Bugzilla::Util;

use List::Util qw(min max);
use List::MoreUtils qw(firstidx);

use base qw(Exporter);
@Bugzilla::Search::Quicksearch::EXPORT = qw(quicksearch);

# Custom mappings for some fields.
use constant MAPPINGS => {
    # Status, Resolution, Platform, OS, Priority, Severity
    "status"   => "bug_status",
    "platform" => "rep_platform",
    "os"       => "op_sys",
    "severity" => "bug_severity",

    # People: AssignedTo, Reporter, QA Contact, CC, etc.
    "assignee" => "assigned_to",
    "owner"    => "assigned_to",

    # Product, Version, Component, Target Milestone
    "milestone" => "target_milestone",

    # Summary, Description, URL, Status whiteboard, Keywords
    "summary"     => "short_desc",
    "description" => "longdesc",
    "comment"     => "longdesc",
    "url"         => "bug_file_loc",
    "whiteboard"  => "status_whiteboard",
    "sw"          => "status_whiteboard",
    "kw"          => "keywords",
    "group"       => "bug_group",

    # Flags
    "flag"        => "flagtypes.name",
    "requestee"   => "requestees.login_name",
    "setter"      => "setters.login_name",

    # Attachments
    "attachment"     => "attachments.description",
    "attachmentdesc" => "attachments.description",
    "attachdesc"     => "attachments.description",
    "attachmentdata" => "attach_data.thedata",
    "attachdata"     => "attach_data.thedata",
    "attachmentmimetype" => "attachments.mimetype",
    "attachmimetype" => "attachments.mimetype"
};

sub FIELD_MAP {
    my $cache = Bugzilla->request_cache;
    return $cache->{quicksearch_fields} if $cache->{quicksearch_fields};

    # Get all the fields whose names don't contain periods. (Fields that
    # contain periods are always handled in MAPPINGS.) 
    my @db_fields = grep { $_->name !~ /\./ } 
                         @{ Bugzilla->fields({ obsolete => 0 }) };
    my %full_map = (%{ MAPPINGS() }, map { $_->name => $_->name } @db_fields);

    # Eliminate the fields that start with bug_ or rep_, because those are
    # handled by the MAPPINGS instead, and we don't want too many names
    # for them. (Also, otherwise "rep" doesn't match "reporter".)
    #
    # Remove "status_whiteboard" because we have "whiteboard" for it in
    # the mappings, and otherwise "stat" can't match "status".
    #
    # Also, don't allow searching the _accessible stuff via quicksearch
    # (both because it's unnecessary and because otherwise 
    # "reporter_accessible" and "reporter" both match "rep".
    delete @full_map{qw(rep_platform bug_status bug_file_loc bug_group
                        bug_severity bug_status
                        status_whiteboard
                        cclist_accessible reporter_accessible)};

    $cache->{quicksearch_fields} = \%full_map;

    return $cache->{quicksearch_fields};
}

# Certain fields, when specified like "field:value" get an operator other
# than "substring"
use constant FIELD_OPERATOR => {
    content         => 'matches',
    owner_idle_time => 'greaterthan',
};

# We might want to put this into localconfig or somewhere
use constant PRODUCT_EXCEPTIONS => (
    'row',   # [Browser]
             #   ^^^
    'new',   # [MailNews]
             #      ^^^
);
use constant COMPONENT_EXCEPTIONS => (
    'hang'   # [Bugzilla: Component/Keyword Changes]
             #                               ^^^^
);

# Quicksearch-wide globals for boolean charts.
our ($chart, $and, $or);

sub quicksearch {
    my ($searchstring) = (@_);
    my $cgi = Bugzilla->cgi;

    $chart = 0;
    $and   = 0;
    $or    = 0;

    # Remove leading and trailing commas and whitespace.
    $searchstring =~ s/(^[\s,]+|[\s,]+$)//g;
    ThrowUserError('buglist_parameters_required') unless ($searchstring);

    if ($searchstring =~ m/^[0-9,\s]*$/) {
        _bug_numbers_only($searchstring);
    }
    else {
        _handle_alias($searchstring);

        # Globally translate " AND ", " OR ", " NOT " to space, pipe, dash.
        $searchstring =~ s/\s+AND\s+/ /g;
        $searchstring =~ s/\s+OR\s+/|/g;
        $searchstring =~ s/\s+NOT\s+/ -/g;

        my @words = splitString($searchstring);
        _handle_status_and_resolution(\@words);

        my (@unknownFields, %ambiguous_fields);

        # Loop over all main-level QuickSearch words.
        foreach my $qsword (@words) {
            my $negate = substr($qsword, 0, 1) eq '-';
            if ($negate) {
                $qsword = substr($qsword, 1);
            }

            # No special first char
            if (!_handle_special_first_chars($qsword, $negate)) {
                # Split by '|' to get all operands for a boolean OR.
                foreach my $or_operand (split(/\|/, $qsword)) {
                    if (!_handle_field_names($or_operand, $negate,
                                             \@unknownFields, 
                                             \%ambiguous_fields))
                    {
                        # Having ruled out the special cases, we may now split
                        # by comma, which is another legal boolean OR indicator.
                        foreach my $word (split(/,/, $or_operand)) {
                            if (!_special_field_syntax($word, $negate)) {
                                _default_quicksearch_word($word, $negate);
                            }
                            _handle_urls($word, $negate);
                        }
                    }
                }
            }
            $chart++;
            $and = 0;
            $or = 0;
        } # foreach (@words)

        # Inform user about any unknown fields
        if (scalar(@unknownFields) || scalar(keys %ambiguous_fields)) {
            ThrowUserError("quicksearch_unknown_field",
                           { unknown   => \@unknownFields,
                             ambiguous => \%ambiguous_fields });
        }

        # Make sure we have some query terms left
        scalar($cgi->param())>0 || ThrowUserError("buglist_parameters_required");
    }

    # List of quicksearch-specific CGI parameters to get rid of.
    my @params_to_strip = ('quicksearch', 'load', 'run');
    my $modified_query_string = $cgi->canonicalise_query(@params_to_strip);

    if ($cgi->param('load')) {
        my $urlbase = correct_urlbase();
        # Param 'load' asks us to display the query in the advanced search form.
        print $cgi->redirect(-uri => "${urlbase}query.cgi?format=advanced&amp;"
                             . $modified_query_string);
    }

    # Otherwise, pass the modified query string to the caller.
    # We modified $cgi->params, so the caller can choose to look at that, too,
    # and disregard the return value.
    $cgi->delete(@params_to_strip);
    return $modified_query_string;
}

##########################
# Parts of quicksearch() #
##########################

sub _bug_numbers_only {
    my $searchstring = shift;
    my $cgi = Bugzilla->cgi;
    # Allow separation by comma or whitespace.
    $searchstring =~ s/[,\s]+/,/g;

    if ($searchstring !~ /,/) {
        # Single bug number; shortcut to show_bug.cgi.
        print $cgi->redirect(
            -uri => correct_urlbase() . "show_bug.cgi?id=$searchstring");
        exit;
    }
    else {
        # List of bug numbers.
        $cgi->param('bug_id', $searchstring);
        $cgi->param('order', 'bugs.bug_id');
        $cgi->param('bug_id_type', 'anyexact');
    }
}

sub _handle_alias {
    my $searchstring = shift;
    if ($searchstring =~ /^([^,\s]+)$/) {
        my $alias = $1;
        # We use this direct SQL because we want quicksearch to be VERY fast.
        my $is_alias = Bugzilla->dbh->selectrow_array(
            q{SELECT 1 FROM bugs WHERE alias = ?}, undef, $alias);
        if ($is_alias) {
            print Bugzilla->cgi->redirect(
                -uri => correct_urlbase() . "show_bug.cgi?id=$alias");
            exit;
        }
    }
}

sub _handle_status_and_resolution {
    my ($words) = @_;
    my $legal_statuses = get_legal_field_values('bug_status');
    my $legal_resolutions = get_legal_field_values('resolution');

    my @openStates = BUG_STATE_OPEN;
    my @closedStates;
    my (%states, %resolutions);

    foreach (@$legal_statuses) {
        push(@closedStates, $_) unless is_open_state($_);
    }
    foreach (@openStates) { $states{$_} = 1 }
    if ($words->[0] eq 'ALL') {
        foreach (@$legal_statuses) { $states{$_} = 1 }
        shift @$words;
    }
    elsif ($words->[0] eq 'OPEN') {
        shift @$words;
    }
    elsif ($words->[0] =~ /^[A-Z_]+(,[_A-Z]+)*$/) {
        # e.g. CON,IN_PR,FIX
        undef %states;
        if (matchPrefixes(\%states,
                          \%resolutions,
                          [split(/,/, $words->[0])],
                          $legal_statuses,
                          $legal_resolutions)) {
            shift @$words;
        }
        else {
            # Carry on if no match found
            foreach (@openStates) { $states{$_} = 1 }
        }
    }
    else {
        # Default: search for unresolved bugs only.
        # Put custom code here if you would like to change this behaviour.
    }

    # If we have wanted resolutions, allow closed states
    if (keys(%resolutions)) {
        foreach (@closedStates) { $states{$_} = 1 }
    }

    Bugzilla->cgi->param('bug_status', keys(%states));
    Bugzilla->cgi->param('resolution', keys(%resolutions));
}


sub _handle_special_first_chars {
    my ($qsword, $negate) = @_;

    my $firstChar = substr($qsword, 0, 1);
    my $baseWord = substr($qsword, 1);
    my @subWords = split(/[\|,]/, $baseWord);

    if ($firstChar eq '#') {
        addChart('short_desc', 'substring', $baseWord, $negate);
        addChart('content', 'matches', _matches_phrase($baseWord), $negate);
        return 1;
    }
    if ($firstChar eq ':') {
        foreach (@subWords) {
            addChart('product', 'substring', $_, $negate);
            addChart('component', 'substring', $_, $negate);
        }
        return 1;
    }
    if ($firstChar eq '@') {
        addChart('assigned_to', 'substring', $_, $negate) foreach (@subWords);
        return 1;
    }
    if ($firstChar eq '[') {
        addChart('short_desc', 'substring', $baseWord, $negate);
        addChart('status_whiteboard', 'substring', $baseWord, $negate);
        return 1;
    }
    if ($firstChar eq '!') {
        addChart('keywords', 'anywords', $baseWord, $negate);
        return 1;
    }
    return 0;
}

sub _handle_field_names {
    my ($or_operand, $negate, $unknownFields, $ambiguous_fields) = @_;
    
    # Flag and requestee shortcut
    if ($or_operand =~ /^(?:flag:)?([^\?]+\?)([^\?]*)$/) {
        addChart('flagtypes.name', 'substring', $1, $negate);
        $chart++; $and = $or = 0; # Next chart for boolean AND
        addChart('requestees.login_name', 'substring', $2, $negate);
        return 1;
    }
    
    # generic field1,field2,field3:value1,value2 notation
    if ($or_operand =~ /^([^:]+):([^:]+)$/) {
        my @fields = split(/,/, $1);
        my @values = split(/,/, $2);
        foreach my $field (@fields) {
            my $translated = _translate_field_name($field);
            # Skip and record any unknown fields
            if (!defined $translated) {
                push(@$unknownFields, $field);
                next;
            }
            # If we got back an array, that means the substring is
            # ambiguous and could match more than field name
            elsif (ref $translated) {
                $ambiguous_fields->{$field} = $translated;
                next;
            }
            foreach my $value (@values) {
                my $operator = FIELD_OPERATOR->{$translated} || 'substring';
                addChart($translated, $operator, $value, $negate);
            }
        }
        return 1;
    }
    
    return 0;
}

sub _translate_field_name {
    my $field = shift;
    $field = lc($field);
    my $field_map = FIELD_MAP;

    # If the field exactly matches a mapping, just return right now.
    return $field_map->{$field} if exists $field_map->{$field};

    # Check if we match, as a starting substring, exactly one field.
    my @field_names = keys %$field_map;
    my @matches = grep { $_ =~ /^\Q$field\E/ } @field_names;
    # Eliminate duplicates that are actually the same field
    # (otherwise "assi" matches both "assignee" and "assigned_to", and
    # the lines below fail when they shouldn't.)
    my %match_unique = map { $field_map->{$_} => $_ } @matches;
    @matches = values %match_unique;

    if (scalar(@matches) == 1) {
        return $field_map->{$matches[0]};
    }
    elsif (scalar(@matches) > 1) {
        return \@matches;
    }

    # Check if we match exactly one custom field, ignoring the cf_ on the
    # custom fields (to allow people to type things like "build" for 
    # "cf_build").
    my %cfless;
    foreach my $name (@field_names) {
        my $no_cf = $name;
        if ($no_cf =~ s/^cf_//) {
            if ($field eq $no_cf) {
                return $field_map->{$name};
            }
            $cfless{$no_cf} = $name;
        }
    }

    # See if we match exactly one substring of any of the cf_-less fields.
    my @cfless_matches = grep { $_ =~ /^\Q$field\E/ } (keys %cfless);

    if (scalar(@cfless_matches) == 1) {
        my $match = $cfless_matches[0];
        my $actual_field = $cfless{$match};
        return $field_map->{$actual_field};
    }
    elsif (scalar(@matches) > 1) {
        return \@matches;
    }

    return undef;
}

sub _special_field_syntax {
    my ($word, $negate) = @_;
    
    # P1-5 Syntax
    if ($word =~ m/^P(\d+)(?:-(\d+))?$/i) {
        my ($p_start, $p_end) = ($1, $2);
        my $legal_priorities = get_legal_field_values('priority');

        # If Pn exists explicitly, use it.
        my $start = firstidx { $_ eq "P$p_start" } @$legal_priorities;
        my $end;
        $end = firstidx { $_ eq "P$p_end" } @$legal_priorities if defined $p_end;

        # If Pn doesn't exist explicitly, then we mean the nth priority.
        if ($start == -1) {
            $start = max(0, $p_start - 1);
        }
        my $prios = $legal_priorities->[$start];

        if (defined $end) {
            # If Pn doesn't exist explicitly, then we mean the nth priority.
            if ($end == -1) {
                $end = min(scalar(@$legal_priorities), $p_end) - 1;
                $end = max(0, $end); # Just in case the user typed P0.
            }
            ($start, $end) = ($end, $start) if $end < $start;
            $prios = join(',', @$legal_priorities[$start..$end])
        }

        addChart('priority', 'anyexact', $prios, $negate);
        return 1;
    }
    return 0;    
}

sub _default_quicksearch_word {
    my ($word, $negate) = @_;
    
    if (!grep { lc($word) eq $_ } PRODUCT_EXCEPTIONS and length($word) > 2) {
        addChart('product', 'substring', $word, $negate);
    }
    
    if (!grep { lc($word) eq $_ } COMPONENT_EXCEPTIONS and length($word) > 2) {
        addChart('component', 'substring', $word, $negate);
    }
    
    my @legal_keywords = map($_->name, Bugzilla::Keyword->get_all);
    if (grep { lc($word) eq lc($_) } @legal_keywords) {
        addChart('keywords', 'substring', $word, $negate);
    }
    
    addChart('alias', 'substring', $word, $negate);
    addChart('short_desc', 'substring', $word, $negate);
    addChart('status_whiteboard', 'substring', $word, $negate);
    addChart('content', 'matches', _matches_phrase($word), $negate);
}

sub _handle_urls {
    my ($word, $negate) = @_;
    # URL field (for IP addrs, host.names,
    # scheme://urls)
    if ($word =~ m/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/
        || $word =~ /^[A-Za-z]+(\.[A-Za-z]+)+/
        || $word =~ /:[\\\/][\\\/]/
        || $word =~ /localhost/
        || $word =~ /mailto[:]?/)
        # || $word =~ /[A-Za-z]+[:][0-9]+/ #host:port
    {
        addChart('bug_file_loc', 'substring', $word, $negate);
    }
}

###########################################################################
# Helpers
###########################################################################

# Split string on whitespace, retaining quoted strings as one
sub splitString {
    my $string = shift;
    my @quoteparts;
    my @parts;
    my $i = 0;

    # Now split on quote sign; be tolerant about unclosed quotes
    @quoteparts = split(/"/, $string);
    foreach my $part (@quoteparts) {
        # After every odd quote, quote special chars
        if ($i++ %2) {
            $part = url_quote($part);
            # Protect the minus sign from being considered
            # as negation, in quotes.
            $part =~ s/(?<=^)\-/%2D/;
        }
    }
    # Join again
    $string = join('"', @quoteparts);

    # Now split on unescaped whitespace
    @parts = split(/\s+/, $string);
    foreach (@parts) {
        # Protect plus signs from becoming a blank.
        # If "+" appears as the first character, leave it alone
        # as it has a special meaning. Strings which start with
        # "+" must be quoted.
        s/(?<!^)\+/%2B/g;
        # Remove quotes
        s/"//g;
    }
    return @parts;
}

# Quote and escape a phrase appropriately for a "content matches" search.
sub _matches_phrase {
    my ($phrase) = @_;
    $phrase =~ s/"/\\"/g;
    return "\"$phrase\"";
}

# Expand found prefixes to states or resolutions
sub matchPrefixes {
    my $hr_states = shift;
    my $hr_resolutions = shift;
    my $ar_prefixes = shift;
    my $ar_check_states = shift;
    my $ar_check_resolutions = shift;
    my $foundMatch = 0;

    foreach my $prefix (@$ar_prefixes) {
        foreach (@$ar_check_states) {
            if (/^$prefix/) {
                $$hr_states{$_} = 1;
                $foundMatch = 1;
            }
        }
        foreach (@$ar_check_resolutions) {
            if (/^$prefix/) {
                $$hr_resolutions{$_} = 1;
                $foundMatch = 1;
            }
        }
    }
    return $foundMatch;
}

# Negate comparison type
sub negateComparisonType {
    my $comparisonType = shift;

    if ($comparisonType eq 'anywords') {
        return 'nowords';
    }
    return "not$comparisonType";
}

# Add a boolean chart
sub addChart {
    my ($field, $comparisonType, $value, $negate) = @_;

    $negate && ($comparisonType = negateComparisonType($comparisonType));
    makeChart("$chart-$and-$or", $field, $comparisonType, $value);
    if ($negate) {
        $and++;
        $or = 0;
    }
    else {
        $or++;
    }
}

# Create the CGI parameters for a boolean chart
sub makeChart {
    my ($expr, $field, $type, $value) = @_;

    my $cgi = Bugzilla->cgi;
    $cgi->param("field$expr", $field);
    $cgi->param("type$expr",  $type);
    $cgi->param("value$expr", url_decode($value));
}

1;
