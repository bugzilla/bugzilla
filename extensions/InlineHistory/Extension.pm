# ***** BEGIN LICENSE BLOCK *****
# Version: MPL 1.1
# 
# The contents of this file are subject to the Mozilla Public License Version
# 1.1 (the "License"); you may not use this file except in compliance with the
# License. You may obtain a copy of the License at http://www.mozilla.org/MPL/
# 
# Software distributed under the License is distributed on an "AS IS" basis,
# WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for
# the specific language governing rights and limitations under the License.
# 
# The Original Code is the InlineHistory Bugzilla Extension;
# Derived from the Bugzilla Tweaks Addon.
# 
# The Initial Developer of the Original Code is the Mozilla Foundation.
# Portions created by the Initial Developer are Copyright (C) 2011 the Initial
# Developer. All Rights Reserved.
# 
# Contributor(s):
#   Johnathan Nightingale <johnath@mozilla.com>
#   Ehsan Akhgari <ehsan@mozilla.com>
#   Byron Jones <glob@mozilla.com>
#
# ***** END LICENSE BLOCK *****

package Bugzilla::Extension::InlineHistory;
use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::User::Setting;
use Bugzilla::Constants;
use Bugzilla::Attachment;

our $VERSION = '1.4';

# don't show inline history for bugs with lots of changes
use constant MAXIMUM_ACTIVITY_COUNT => 500;

sub template_before_process {
    my ($self, $args) = @_;
    my $file = $args->{'file'};
    my $vars = $args->{'vars'};
    my $user = Bugzilla->user;
    my $dbh = Bugzilla->dbh;

    return unless $user && $user->id && $user->settings;
    return unless $user->settings->{'inline_history'}->{'value'} eq 'on';

    # in the header we just need to set the var, to ensure the css and
    # javascript get included
    if ($file eq 'bug/show-header.html.tmpl') {
        $vars->{'ih_activity'} = 1;
        return;
    } elsif ($file ne 'bug/edit.html.tmpl') {
        return;
    }

    # note: bug/edit.html.tmpl doesn't support multiple bugs
    my $bug_id = exists $vars->{'bugs'}
        ? $vars->{'bugs'}[0]->id
        : $vars->{'bug'}->id;

    # build bug activity
    my ($activity) = Bugzilla::Bug::GetBugActivity($bug_id);
    $activity = _add_duplicates($bug_id, $activity);

    if (scalar @$activity > MAXIMUM_ACTIVITY_COUNT) {
        $activity = [];
        $vars->{'ih_activity'} = 0;
        $vars->{'ih_activity_max'} = 1;
        return;
    }

    # augment and tweak
    foreach my $operation (@$activity) {
        # make operation.who an object
        $operation->{who} = Bugzilla::User->new({ name => $operation->{who} });
        for (my $i = 0; $i < scalar(@{$operation->{changes}}); $i++) {
            my $change = $operation->{changes}->[$i];

            # make an attachment object
            if ($change->{attachid}) {
                $change->{attach} = Bugzilla::Attachment->new($change->{attachid});
            }

            # empty resolutions are displayed as --- by default
            # make it explicit here to enable correct display of the change
            if ($change->{fieldname} eq 'resolution') {
                $change->{removed} = '---' if $change->{removed} eq '';
                $change->{added} = '---' if $change->{added} eq '';
            }

            # make boolean fields true/false instead of 1/0
            my ($table, $field) = ('bugs', $change->{fieldname});
            if ($field =~ /^([^\.]+)\.(.+)$/) {
                ($table, $field) = ($1, $2);
            }
            my $column = $dbh->bz_column_info($table, $field);
            if ($column && $column->{TYPE} eq 'BOOLEAN') {
                $change->{removed} = '';
                $change->{added} = $change->{added} ? 'true' : 'false';
            }

            # identify buglist changes
            $change->{buglist} = 
                $change->{fieldname} eq 'blocked' ||
                $change->{fieldname} eq 'dependson' ||
                $change->{fieldname} eq 'dupe';

            # split multiple flag changes (must be processed last)
            if ($change->{fieldname} eq 'flagtypes.name') {
                my @added = split(/, /, $change->{added});
                my @removed = split(/, /, $change->{removed});
                next if scalar(@added) <= 1 && scalar(@removed) <= 1;
                # remove current change
                splice(@{$operation->{changes}}, $i, 1);
                # restructure into added/removed for each flag
                my %flags;
                foreach my $added (@added) {
                    my ($value, $name) = $added =~ /^((.+).)$/;
                    $flags{$name}{added} = $value;
                    $flags{$name}{removed} |= '';
                }
                foreach my $removed (@removed) {
                    my ($value, $name) = $removed =~ /^((.+).)$/;
                    $flags{$name}{added} |= '';
                    $flags{$name}{removed} = $value;
                }
                # clone current change, modify and insert
                foreach my $flag (sort keys %flags) {
                    my $flag_change = {};
                    foreach my $key (keys %$change) {
                        $flag_change->{$key} = $change->{$key};
                    }
                    $flag_change->{removed} = $flags{$flag}{removed};
                    $flag_change->{added} = $flags{$flag}{added};
                    splice(@{$operation->{changes}}, $i, 0, $flag_change);
                }
                $i--;
            }
        }
    }

    $vars->{'ih_activity'} = $activity;
}

sub _add_duplicates {
    # insert 'is a dupe of this bug' comment to allow js to display
    # as activity

    my ($bug_id, $activity) = @_;

    my $dbh = Bugzilla->dbh;
    my $sth = $dbh->prepare("
        SELECT profiles.login_name, " .
               $dbh->sql_date_format('bug_when', '%Y.%m.%d %H:%i:%s') . ",
               extra_data,
               thetext
          FROM longdescs
               INNER JOIN profiles ON profiles.userid = longdescs.who
         WHERE bug_id = ?
               AND (
                 type = ?
                 OR thetext LIKE '%has been marked as a duplicate of this%'
               )
         ORDER BY bug_when
    ");
    $sth->execute($bug_id, CMT_HAS_DUPE);

    while (my($who, $when, $dupe_id, $the_text) = $sth->fetchrow_array) {
        if (!$dupe_id) {
            next unless $the_text =~ / (\d+) has been marked as a duplicate of this/;
            $dupe_id = $1;
        }
        my $entry = {
            'when' => $when,
            'who' => $who,
            'changes' => [
                {
                    'removed' => '',
                    'added' => $dupe_id,
                    'attachid' => undef,
                    'fieldname' => 'dupe',
                    'dupe' => 1,
                }
            ],
        };
        push @$activity, $entry;
    }

    return [ sort { $a->{when} cmp $b->{when} } @$activity ];
}

sub install_before_final_checks {
    my ($self, $args) = @_;
    add_setting('inline_history', ['on', 'off'], 'off');
}

__PACKAGE__->NAME;
