# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::ProductDashboard;

use strict;

use base qw(Bugzilla::Extension);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::Product;
use Bugzilla::Field;

use Bugzilla::Extension::ProductDashboard::Queries;
use Bugzilla::Extension::ProductDashboard::Util;

our $VERSION = BUGZILLA_VERSION;

sub page_before_template {
    my ($self, $args) = @_;

    my $page = $args->{page_id};
    my $vars = $args->{vars};

    if ($page =~ m{^productdashboard\.}) {
        _page_dashboard($vars);
    }
}

sub _page_dashboard {
    my $vars  = shift;

    my $cgi   = Bugzilla->cgi;
    my $input = Bugzilla->input_params;
    my $user  = Bugzilla->user;

    # Switch to shadow db since we are just reading information
    Bugzilla->switch_to_shadow_db();

    # All pages point to the same part of the documentation.
    $vars->{'doc_section'} = 'bugreports.html';

    # Forget any previously selected product
    $cgi->send_cookie(-name => 'PRODUCT_DASHBOARD',
                      -value => 'X',
                      -expires => "Fri, 01-Jan-1970 00:00:00 GMT");

    # If the user cannot enter bugs in any product, stop here.
    scalar @{$user->get_selectable_products}
        || ThrowUserError('no_products');

    # Create data structures representing each classification
    my @classifications = ();
    foreach my $c (@{$user->get_selectable_classifications}) {
        # Create hash to hold attributes for each classification.
        my %classification = (
            'name'       => $c->name,
            'products'   => [ @{$user->get_selectable_products($c->id)} ]
        );
        # Assign hash back to classification array.
        push @classifications, \%classification;
    }
    $vars->{'classifications'} = \@classifications;

    my $product_name = trim($input->{'product'} || '');

    if (!$product_name && $cgi->cookie('PRODUCT_DASHBOARD')) {
        $product_name = $cgi->cookie('PRODUCT_DASHBOARD');
    }

    return if !$product_name;

    # Do not use Bugzilla::Product::check_product() here, else the user
    # could know whether the product doesn't exist or is not accessible.
    my $product = new Bugzilla::Product({'name' => $product_name});

    # We need to check and make sure that the user has permission
    # to enter a bug against this product.
    if (!$product || !$user->can_enter_product($product->name)) {
        return;
    }

    # Remember selected product
    $cgi->send_cookie(-name => 'PRODUCT_DASHBOARD',
                      -value => $product->name,
                      -expires => "Fri, 01-Jan-2038 00:00:00 GMT");

    my $current_tab_name = $input->{'tab'} || "summary";
    trick_taint($current_tab_name);
    $vars->{'current_tab_name'} = $current_tab_name;

    my $bug_status = trim($input->{'bug_status'} || 'open');

    $vars->{'bug_status'}        = $bug_status;
    $vars->{'product'}           = $product;
    $vars->{'bug_link_all'}      = bug_link_all($product);
    $vars->{'bug_link_open'}     = bug_link_open($product);
    $vars->{'bug_link_closed'}   = bug_link_closed($product);
    $vars->{'total_bugs'}        = total_bugs($product);
    $vars->{'total_open_bugs'}   = total_open_bugs($product);
    $vars->{'total_closed_bugs'} = total_closed_bugs($product);
    $vars->{'severities'}        = get_legal_field_values('bug_severity');

    if ($current_tab_name eq 'summary') {
        $vars->{'by_priority'} = by_priority($product, $bug_status);
        $vars->{'by_severity'} = by_severity($product, $bug_status);
        $vars->{'by_assignee'} = by_assignee($product, $bug_status, 25);
        $vars->{'by_status'}   = by_status($product, $bug_status);
    }

    if ($current_tab_name eq 'recents') {
        my $recent_days = $input->{'recent_days'} || 7;
        (detaint_natural($recent_days) && $recent_days > 0 && $recent_days < 101)
            || ThrowUserError('product_dashboard_invalid_recent_days');

        my $params = {
            product   => $product,
            days      => $recent_days,
            date_from => $input->{'date_from'} || '',
            date_to   => $input->{'date_to'} || '',
        };

        $vars->{'recently_opened'} = recently_opened($params);
        $vars->{'recently_closed'} = recently_closed($params);
        $vars->{'recent_days'} = $recent_days;
        $vars->{'date_from'}   = $input->{'date_from'};
        $vars->{'date_to'}     = $input->{'date_to'};
    }

    if ($current_tab_name eq 'components') {
        if ($input->{'component'}) {
            $vars->{'summary'} = by_value_summary($product, 'component', $input->{'component'}, $bug_status);
            $vars->{'summary'}{'type'} = 'component';
            $vars->{'summary'}{'value'} = $input->{'component'};
        } 
        elsif ($input->{'version'}) {
            $vars->{'summary'} = by_value_summary($product, 'version', $input->{'version'}, $bug_status); 
            $vars->{'summary'}{'type'} = 'version';
            $vars->{'summary'}{'value'} = $input->{'version'};
        } 
        elsif ($input->{'target_milestone'} && Bugzilla->params->{'usetargetmilestone'}) {
            $vars->{'summary'} = by_value_summary($product, 'target_milestone', $input->{'target_milestone'}, $bug_status); 
            $vars->{'summary'}{'type'} = 'target_milestone';
            $vars->{'summary'}{'value'} = $input->{'target_milestone'};
        }
        else {
            $vars->{'by_component'} = by_component($product, $bug_status);
            $vars->{'by_version'}   = by_version($product, $bug_status);
            if (Bugzilla->params->{'usetargetmilestone'}) {
                $vars->{'by_milestone'} = by_milestone($product, $bug_status);
            }
        }
    }

    if ($current_tab_name eq 'duplicates') {
        $vars->{'by_duplicate'} = by_duplicate($product, $bug_status);
    }

    if ($current_tab_name eq 'popularity') {
        $vars->{'by_popularity'} = by_popularity($product, $bug_status);
    }

    if ($current_tab_name eq 'roadmap') {
        foreach my $milestone (@{$product->milestones}){
            my %milestone_stats;
            $milestone_stats{'name'} = $milestone->name;
            $milestone_stats{'total_bugs'} = total_bug_milestone($product, $milestone);
            $milestone_stats{'open_bugs'}  = bug_milestone_by_status($product, $milestone, 'open');
            $milestone_stats{'closed_bugs'} = bug_milestone_by_status($product, $milestone, 'closed'); 
            $milestone_stats{'link_total'} = bug_milestone_link_total($product, $milestone);
            $milestone_stats{'link_open'} = bug_milestone_link_open($product, $milestone);
            $milestone_stats{'link_closed'} = bug_milestone_link_closed($product, $milestone);
            push (@{$vars->{by_roadmap}}, \%milestone_stats);
        }
    }
}

__PACKAGE__->NAME;

