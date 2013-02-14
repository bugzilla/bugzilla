# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Extension::MozProjectReview;

use strict;

use base qw(Bugzilla::Extension);

use Bugzilla::User;
use Bugzilla::Group;
use Bugzilla::Error;
use Bugzilla::Constants;

our $VERSION = '0.01';

sub post_bug_after_creation {
    my ($self, $args) = @_;
    my $vars   = $args->{vars};
    my $bug    = $vars->{bug};

    my $user     = Bugzilla->user;
    my $params   = Bugzilla->input_params;
    my $template = Bugzilla->template;

    return if !($params->{format}
                && $params->{format} eq 'moz-project-review'
                && $bug->component eq 'Project Review');

    my $error_mode_cache = Bugzilla->error_mode;
    Bugzilla->error_mode(ERROR_MODE_DIE);

    # do a match if applicable
    Bugzilla::User::match_field({
        'legal_cc' => { 'type' => 'multi' }
    });

    my ($do_sec_review, $do_legal, $do_finance, $do_privacy_vendor,
        $do_data_safety, $do_privacy_tech, $do_privacy_policy);

    if ($params->{mozilla_data} eq 'Yes') {
        $do_legal = 1;
        $do_privacy_policy = 1;
        $do_privacy_tech = 1;
        $do_sec_review = 1;
    }

    if ($params->{mozilla_data} eq 'Yes'
        && $params->{data_safety_user_data} eq 'Yes')
    {
        $do_data_safety = 1;
    }

    if ($params->{new_or_change} eq 'New') {
        $do_legal = 1;
        $do_privacy_policy = 1;
    }
    elsif ($params->{new_or_change} eq 'Existing') {
        $do_legal = 1;
    }

    if ($params->{separate_party} eq 'Yes'
        && $params->{relationship_type} ne 'Hardware Purchase') 
    {
        $do_legal = 1;
    }

    if ($params->{data_access} eq 'Yes') {
        $do_privacy_policy = 1;
        $do_sec_review = 1;
    }

    if ($params->{data_access} eq 'Yes'
        && $params->{'privacy_policy_vendor_user_data'} eq 'Yes') 
    {
        $do_privacy_vendor = 1;
    }

    if ($params->{vendor_cost} eq '> $25,000' 
        || ($params->{vendor_cost} eq '<= $25,000'
            && $params->{po_needed} eq 'Yes')) 
    {
        $do_finance = 1;
    }

    my ($sec_review_bug, $legal_bug, $finance_bug, $privacy_vendor_bug,
        $data_safety_bug, $privacy_tech_bug, $privacy_policy_bug, $error, 
        @dep_bug_comment, @dep_bug_errors);

    if ($do_sec_review) {
        my $bug_data = {
            short_desc   => 'Security Review: ' . $bug->short_desc,
            product      => 'mozilla.org',
            component    => 'Security Assurance: Review Request',
            bug_severity => 'normal',
            groups       => [ 'mozilla-corporation-confidential' ],
            keywords     => 'sec-review-needed',
            op_sys       => 'All',
            rep_platform => 'All',
            version      => 'other',
            blocked      => $bug->bug_id,
        };
        _file_child_bug({ parent_bug => $bug, template_vars => $vars,
                          template_suffix => 'sec-review', bug_data => $bug_data,
                          dep_comment => \@dep_bug_comment, dep_errors => \@dep_bug_errors });
    }

    if ($do_legal) {
        my $component;
        if ($params->{new_or_change} eq 'New') {
            $component = 'General';
        }
        elsif ($params->{new_or_change} eq 'Existing') {
            $component = $params->{mozilla_project};
        }

        if ($params->{separate_party} eq 'Yes'
            && $params->{relationship_type})
        {
            $component = ($params->{relationship_type} eq 'Other'
                            || $params->{relationship_type} eq 'Hardware Purchase')
                         ? 'General'
                         : $params->{relationship_type};
        }

        my $legal_summary = "Legal Review: ";
        $legal_summary .= $params->{legal_other_party} . " - " if $params->{legal_other_party};
        $legal_summary .= $bug->short_desc;

        my $bug_data = {
            short_desc   => $legal_summary,
            product      => 'Legal',
            component    => $component,
            bug_severity => 'normal',
            priority     => '--',
            groups       => [ 'legal' ],
            op_sys       => 'All',
            rep_platform => 'All',
            version      => 'unspecified',
            blocked      => $bug->bug_id,
            cc           => $params->{'legal_cc'},
        };
        _file_child_bug({ parent_bug => $bug, template_vars => $vars,
                          template_suffix => 'legal', bug_data => $bug_data,
                          dep_comment => \@dep_bug_comment, dep_errors => \@dep_bug_errors });
    }

    if ($do_finance) {
        my $bug_data = {
            short_desc   => 'Finance Review: ' . $bug->short_desc,
            product      => 'Finance',
            component    => 'Purchase Request Form',
            bug_severity => 'normal',
            priority     => '--',
            groups       => [ 'finance' ],
            op_sys       => 'All',
            rep_platform => 'All',
            version      => 'unspecified',
            blocked      => $bug->bug_id,
        };
        _file_child_bug({ parent_bug => $bug, template_vars => $vars,
                          template_suffix => 'finance', bug_data => $bug_data,
                          dep_comment => \@dep_bug_comment, dep_errors => \@dep_bug_errors });
    }

    if ($do_data_safety) {
        my $bug_data = {
            short_desc   => 'Data Safety Review: ' . $bug->short_desc,
            product      => 'Data Safety',
            component    => 'General',
            bug_severity => 'normal',
            priority     => '--',
            groups       => [ 'mozilla-corporation-confidential' ],
            op_sys       => 'All',
            rep_platform => 'All',
            version      => 'unspecified',
            blocked      => $bug->bug_id,
        };

        _file_child_bug({ parent_bug => $bug, template_vars => $vars,
                          template_suffix => 'data-safety', bug_data => $bug_data,
                          dep_comment => \@dep_bug_comment, dep_errors => \@dep_bug_errors });
    }

    if ($do_privacy_tech) {
        my $bug_data = {
            short_desc   => 'Privacy-Technical Review: ' . $bug->short_desc,
            product      => 'mozilla.org',
            component    => 'Security Assurance: Review Request',
            bug_severity => 'normal',
            priority     => '--',
            keywords     => 'privacy-review-needed',
            groups       => [ 'mozilla-corporation-confidential' ],
            op_sys       => 'All',
            rep_platform => 'All',
            version      => 'other',
            blocked      => $bug->bug_id,
        };
        _file_child_bug({ parent_bug => $bug, template_vars => $vars,
                          template_suffix => 'privacy-tech', bug_data => $bug_data,
                          dep_comment => \@dep_bug_comment, dep_errors => \@dep_bug_errors });
    }

    if ($do_privacy_policy) {
        my $bug_data = {
            short_desc   => 'Privacy-Policy Review: ' . $bug->short_desc,
            product      => 'Privacy',
            component    => 'Product Review',
            bug_severity => 'normal',
            priority     => '--',
            groups       => [ 'mozilla-corporation-confidential' ],
            op_sys       => 'All',
            rep_platform => 'All',
            version      => 'unspecified',
            blocked      => $bug->bug_id,
        };
        _file_child_bug({ parent_bug => $bug, template_vars => $vars,
                          template_suffix => 'privacy-policy', bug_data => $bug_data,
                          dep_comment => \@dep_bug_comment, dep_errors => \@dep_bug_errors });
    }

    if ($do_privacy_vendor) {
        my $bug_data = {
            short_desc   => 'Privacy / Vendor Review: ' . $bug->short_desc,
            product      => 'Privacy',
            component    => 'Vendor Review',
            bug_severity => 'normal',
            priority     => '--',
            groups       => [ 'mozilla-corporation-confidential' ],
            op_sys       => 'All',
            rep_platform => 'All',
            version      => 'unspecified',
            blocked      => $bug->bug_id,
        };
        _file_child_bug({ parent_bug => $bug, template_vars => $vars,
                          template_suffix => 'privacy-vendor', bug_data => $bug_data,
                          dep_comment => \@dep_bug_comment, dep_errors => \@dep_bug_errors });
    }

    Bugzilla->error_mode($error_mode_cache);

    if (scalar @dep_bug_errors) {
        warn "[Bug " . $bug->id . "] Failed to create additional moz-project-review bugs:\n" .
             join("\n", @dep_bug_errors);
        $vars->{message} = 'moz_project_review_creation_failed';
    }

    if (scalar @dep_bug_comment) {
        my $comment = join("\n", @dep_bug_comment);
        if (scalar @dep_bug_errors) {
            $comment .= "\n\nSome erors occurred creating dependent bugs and have been recorded";
        }
        $bug->add_comment($comment);
        $bug->update();
    }
}

sub _file_child_bug {
    my ($params) = @_;
    my ($parent_bug, $template_vars, $template_suffix, $bug_data, $dep_comment, $dep_errors)
        = @$params{qw(parent_bug template_vars template_suffix bug_data dep_comment dep_errors)};
    my $template = Bugzilla->template;
    my $new_bug;
    eval {
        my $comment;
        my $full_template = "bug/create/comment-moz-project-review-$template_suffix.txt.tmpl";
        $template->process($full_template, $template_vars, \$comment)
            || ThrowTemplateError($template->error());
        $bug_data->{comment} = $comment;
        $new_bug = Bugzilla::Bug->create($bug_data);
        $parent_bug->set_all({ dependson => { add => [ $new_bug->bug_id ] }});
        Bugzilla::BugMail::Send($new_bug->id, { changer => Bugzilla->user });
    };
    if ($@) {
        push(@$dep_comment, "Error creating $template_suffix review bug");
        push(@$dep_errors, "$template_suffix : $@");
    }
    if ($new_bug) {
        push(@$dep_comment, "Bug " . $new_bug->id . " - " . $new_bug->short_desc);
    }
}

__PACKAGE__->NAME;
