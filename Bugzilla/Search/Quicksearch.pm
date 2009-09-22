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

use base qw(Exporter);
@Bugzilla::Search::Quicksearch::EXPORT = qw(quicksearch);

# Word renamings
use constant MAPPINGS => {
                # Status, Resolution, Platform, OS, Priority, Severity
                "status" => "bug_status",
                "resolution" => "resolution",  # no change
                "platform" => "rep_platform",
                "os" => "op_sys",
                "opsys" => "op_sys",
                "priority" => "priority",    # no change
                "pri" => "priority",
                "severity" => "bug_severity",
                "sev" => "bug_severity",
                # People: AssignedTo, Reporter, QA Contact, CC, Added comment (?)
                "owner" => "assigned_to",    # deprecated since bug 76507
                "assignee" => "assigned_to",
                "assignedto" => "assigned_to",
                "reporter" => "reporter",    # no change
                "rep" => "reporter",
                "qa" => "qa_contact",
                "qacontact" => "qa_contact",
                "cc" => "cc",          # no change
                # Product, Version, Component, Target Milestone
                "product" => "product",     # no change
                "prod" => "product",
                "version" => "version",     # no change
                "ver" => "version",
                "component" => "component",   # no change
                "comp" => "component",
                "milestone" => "target_milestone",
                "target" => "target_milestone",
                "targetmilestone" => "target_milestone",
                # Summary, Description, URL, Status whiteboard, Keywords
                "summary" => "short_desc",
                "shortdesc" => "short_desc",
                "desc" => "longdesc",
                "description" => "longdesc",
                #"comment" => "longdesc",    # ???
                          # reserve "comment" for "added comment" email search?
                "longdesc" => "longdesc",
                "url" => "bug_file_loc",
                "whiteboard" => "status_whiteboard",
                "statuswhiteboard" => "status_whiteboard",
                "sw" => "status_whiteboard",
                "keywords" => "keywords",    # no change
                "kw" => "keywords",
                "group" => "bug_group",
                "flag" => "flagtypes.name",
                "requestee" => "requestees.login_name",
                "req" => "requestees.login_name",
                "setter" => "setters.login_name",
                "set" => "setters.login_name",
                # Attachments
                "attachment" => "attachments.description",
                "attachmentdesc" => "attachments.description",
                "attachdesc" => "attachments.description",
                "attachmentdata" => "attach_data.thedata",
                "attachdata" => "attach_data.thedata",
                "attachmentmimetype" => "attachments.mimetype",
                "attachmimetype" => "attachments.mimetype"
};

# We might want to put this into localconfig or somewhere
use constant PLATFORMS => ('pc', 'sun', 'macintosh', 'mac');
use constant OPSYSTEMS => ('windows', 'win', 'linux');
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

        my @unknownFields;

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
                                             \@unknownFields))
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
        if (scalar(@unknownFields)) {
            ThrowUserError("quicksearch_unknown_field",
                           { fields => \@unknownFields });
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
        $cgi->param('bugidtype', 'include');
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
    elsif ($words->[0] =~ /^\+[A-Z]+(,[A-Z]+)*$/) {
        # e.g. +DUP,FIX
        if (matchPrefixes(\%states,
                          \%resolutions,
                          [split(/,/, substr($words->[0], 1))],
                          \@closedStates,
                          $legal_resolutions)) {
            shift @$words;
            # Allowing additional resolutions means we need to keep
            # the "no resolution" resolution.
            $resolutions{'---'} = 1;
        }
        else {
            # Carry on if no match found.
        }
    }
    elsif ($words->[0] =~ /^[A-Z]+(,[A-Z]+)*$/) {
        # e.g. NEW,ASSI,REOP,FIX
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

    if ($firstChar eq '+') {
        addChart('short_desc', 'substring', $_, $negate) foreach (@subWords);
        return 1;
    }
    if ($firstChar eq '#') {
        addChart('short_desc', 'substring', $baseWord, $negate);
        addChart('content', 'matches', $baseWord, $negate);
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
    my ($or_operand, $negate, $unknownFields) = @_;
    
    # votes:xx ("at least xx votes")
    if ($or_operand =~ /^votes:([0-9]+)$/) {
        addChart('votes', 'greaterthan', $1 - 1, $negate);
        return 1;
    }
    
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
            # Skip and record any unknown fields
            if (!defined(MAPPINGS->{$field})) {
                push(@$unknownFields, $field);
                next;
            }
            $field = MAPPINGS->{$field};
            foreach (@values) {
                addChart($field, 'substring', $_, $negate);
            }
        }
        return 1;
    }
    
    return 0;
}

sub _special_field_syntax {
    my ($word, $negate) = @_;
    # Platform and operating system
    if (grep { lc($word) eq $_ } PLATFORMS
        or grep { lc($word) eq $_ } OPSYSTEMS)
    {
        addChart('rep_platform', 'substring', $word, $negate);
        addChart('op_sys', 'substring', $word, $negate);
        return 1;
    }
    
    # Priority
    my $legal_priorities = get_legal_field_values('priority');
    if (grep { lc($_) eq lc($word) } @$legal_priorities) {
        addChart('priority', 'equals', $word, $negate);
        return 1;
    }

    # P1-5 Syntax
    if ($word =~ m/^P(\d+)(?:-(\d+))?$/i) {
        my $start = $1 - 1;
        $start = 0 if $start < 0;
        my $end = $2 - 1;
        $end = scalar(@$legal_priorities) - 1
            if $end > (scalar @$legal_priorities - 1);
        my $prios = $legal_priorities->[$start];
        if ($end) {
            $prios = join(',', @$legal_priorities[$start..$end])
        }
        addChart('priority', 'anyexact', $prios, $negate);
        return 1;
    }

    # Severity
    my $legal_severities = get_legal_field_values('bug_severity');
    if (grep { lc($word) eq substr($_, 0, 3)} @$legal_severities) {
        addChart('bug_severity', 'substring', $word, $negate);
        return 1;
    }
    
    # Votes (votes>xx)
    if ($word =~ m/^votes>([0-9]+)$/) {
        addChart('votes', 'greaterthan', $1, $negate);
        return 1;
    }
    
    # Votes (votes>=xx, votes=>xx)
    if ($word =~ m/^votes(>=|=>)([0-9]+)$/) {
        addChart('votes', 'greaterthan', $2-1, $negate);
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
    
    addChart('short_desc', 'substring', $word, $negate);
    addChart('status_whiteboard', 'substring', $word, $negate);
    addChart('content', 'matches', $word, $negate);
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
        $part = url_quote($part) if $i++ % 2;
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

    if ($comparisonType eq 'substring') {
        return 'notsubstring';
    }
    elsif ($comparisonType eq 'anywords') {
        return 'nowords';
    }
    elsif ($comparisonType eq 'regexp') {
        return 'notregexp';
    }
    else {
        # Don't know how to negate that
        ThrowCodeError('unknown_comparison_type');
    }
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
