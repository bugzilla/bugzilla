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
# The Original Code is the GuidedBugEntry Bugzilla Extension.
#
# The Initial Developer of the Original Code is the Mozilla Foundation
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Byron Jones <glob@mozilla.com>

package Bugzilla::Extension::GuidedBugEntry;
use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::Token;
use Bugzilla::Error;
use Bugzilla::Status;
use Bugzilla::Util 'url_quote';
use Bugzilla::UserAgent;

our $VERSION = '1';

sub enter_bug_start {
    my ($self, $args) = @_;
    my $vars = $args->{vars};
    my $template = Bugzilla->template;
    my $cgi = Bugzilla->cgi;
    my $user = Bugzilla->user;

    # hack for skipping old guided code when enabled
    $vars->{'disable_guided'} = 1;

    # force guided format for new users
    my $format = $cgi->param('format') || '';
    if (
        $format eq 'guided' ||
        (
            $format eq '' &&
            !$user->in_group('canconfirm')
        )
    ) {
        # skip the first step if a product is provided
        if ($cgi->param('product')) {
            print $cgi->redirect('enter_bug.cgi?format=guided#h=dupes|' .
                url_quote($cgi->param('product')));
            exit;
        }

        $self->_init_vars($vars);
        print $cgi->header();
        $template->process('guided/guided.html.tmpl', $vars)
          || ThrowTemplateError($template->error());          
        exit;       
    }

    # we use the __default__ format to bypass the guided entry
    # it isn't understood upstream, so remove it once a product
    # has been selected.
    if (
        ($cgi->param('format') && $cgi->param('format') eq "__default__")
        && ($cgi->param('product') && $cgi->param('product') ne '')
    ) {
        $cgi->delete('format') 
    }
}

sub _init_vars {
    my ($self, $vars) = @_;
    my $user = Bugzilla->user;

    my @enterable_products = @{$user->get_enterable_products};
    ThrowUserError('no_products') unless scalar(@enterable_products);

    my @classifications = ({object => undef, products => \@enterable_products});

    my $class;
    foreach my $product (@enterable_products) {
        $class->{$product->classification_id}->{'object'} ||=
            new Bugzilla::Classification($product->classification_id);
        push(@{$class->{$product->classification_id}->{'products'}}, $product);
    }
    @classifications =
        sort {
            $a->{'object'}->sortkey <=> $b->{'object'}->sortkey
            || lc($a->{'object'}->name) cmp lc($b->{'object'}->name)
        } (values %$class);
    $vars->{'classifications'} = \@classifications;

    my @open_states = BUG_STATE_OPEN();
    $vars->{'open_states'} = \@open_states;

    $vars->{'token'} = issue_session_token('create_bug');

    $vars->{'platform'} = detect_platform();
    $vars->{'op_sys'} = detect_op_sys();
}

sub page_before_template {
    my ($self, $args) = @_;
    my $page = $args->{'page_id'};
    my $vars = $args->{'vars'};

    return unless $page eq 'guided_products.js';

    # import product -> security group mappings from the BMO ext

    our %product_sec_groups;
    eval q#use Bugzilla::Extension::BMO::Data '%product_sec_groups'#;
    return if $@;

    $vars->{'products'} = \%product_sec_groups;
}

__PACKAGE__->NAME;
