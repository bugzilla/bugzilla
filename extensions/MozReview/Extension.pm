# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozReview;

use 5.10.1;
use strict;
use warnings;
use parent qw(Bugzilla::Extension);

use Bugzilla::Attachment;
use Bugzilla::Error;
use Bugzilla::Extension::MozReview::WebService;
use List::MoreUtils qw( any );

our $VERSION = '0.01';

my @METHOD_WHITELIST = (
    'User.get',
    'User.login',
    'User.valid_login',
    'Bug.add_comment',
    'Bug.add_attachment',
    'Bug.attachments',
    'Bug.get',
    'Bug.update_attachment',
);

BEGIN {
    package Bugzilla::User::APIKey;

    sub is_mozreview {
        my ($self) = @_;
        my $mozreview_app_id = Bugzilla->params->{mozreview_app_id};
        return 0 unless $mozreview_app_id;

        return 1 if $self->app_id && $self->app_id eq $mozreview_app_id;
    }
}

sub template_before_process {
    my ($self, $args) = @_;
    my $file = $args->{'file'};
    my $vars = $args->{'vars'};

    return unless (($file =~ /bug\/(show-header|edit).html.tmpl$/ ||
                    $file =~ /bug_modal\/(header|edit).html.tmpl$/ ||
                    $file eq 'attachment/create.html.tmpl') &&
                   Bugzilla->params->{mozreview_base_url});

    my $bug = exists $vars->{'bugs'} ? $vars->{'bugs'}[0] : $vars->{'bug'};

    if ($bug) {
        if ($file eq 'attachment/create.html.tmpl') {
            if ($bug->product eq 'Core' || $bug->product eq 'Firefox' ||
                $bug->product eq 'Firefox for Android') {
                $vars->{'mozreview_enabled'} = 1;
            }
        } else {
            my $has_mozreview = 0;
            my $attachments = Bugzilla::Attachment->get_attachments_by_bug($bug);

            foreach my $attachment (@$attachments) {
                if ($attachment->contenttype eq 'text/x-review-board-request'
                    && !$attachment->isobsolete) {
                    $has_mozreview = 1;
                    last;
                }
            }

            if ($has_mozreview) {
                $vars->{'mozreview'} = 1;
            }
        }
    }
}

sub auth_delegation_confirm {
    my ($self, $args) = @_;
    my $mozreview_callback_url = Bugzilla->params->{mozreview_auth_callback_url};
    my $mozreview_app_id       = Bugzilla->params->{mozreview_app_id};

    return unless $mozreview_callback_url;
    return unless $mozreview_app_id;

    if (index($args->{callback}, $mozreview_callback_url) == 0 && $args->{app_id} eq $mozreview_app_id) {
        ${$args->{skip_confirmation}} = 1;
    }
}

sub config_add_panels {
    my ($self, $args) = @_;
    my $modules = $args->{panel_modules};
    $modules->{MozReview} = "Bugzilla::Extension::MozReview::Config";
}

sub webservice {
    my ($self,  $args) = @_;
    my $dispatch = $args->{dispatch};
    $dispatch->{MozReview} = "Bugzilla::Extension::MozReview::WebService";
}

sub webservice_before_call {
    my ($self, $args) = @_;
    my ($method, $full_method) = ($args->{method}, $args->{full_method});
    my $mozreview_app_id = Bugzilla->params->{mozreview_app_id} // '';
    my $user             = Bugzilla->user;
    my $getter           = eval { $user->authorizer->successful_info_getter() } or return;
    my $app_id           = $getter->can("app_id") ? $getter->app_id // '' : '';

    $full_method =~ s/^Bugzilla::Extension::(\w+)::WebService\./$1./;

    my $is_mozreview_method = $full_method =~ /^MozReview\./;

    if ($is_mozreview_method && (!$mozreview_app_id || !$app_id || $mozreview_app_id ne $app_id)) {
        ThrowUserError('forbidden_method', { method => $full_method });
    }

    return unless $mozreview_app_id && $app_id;

    if ($app_id eq $mozreview_app_id && !$is_mozreview_method) {
        unless (any { $full_method eq $_ } @METHOD_WHITELIST) {
            ThrowUserError('forbidden_method', { method => $full_method });
        }
    }
}

__PACKAGE__->NAME;
