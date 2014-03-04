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
# Contributor(s): Terry Weissman <terry@mozilla.org>
#                 Dawn Endico <endico@mozilla.org>
#                 Dan Mosedale <dmose@mozilla.org>
#                 Joe Robins <jmrobins@tgix.com>
#                 Jacob Steenhagen <jake@bugzilla.org>
#                 J. Paul Reed <preed@sigkill.com>
#                 Bradley Baetz <bbaetz@student.usyd.edu.au>
#                 Joseph Heenan <joseph@heenan.me.uk>
#                 Erik Stambaugh <erik@dasbistro.com>
#                 Frédéric Buclin <LpSolit@gmail.com>
#                 Max Kanat-Alexander <mkanat@bugzilla.org>

package Bugzilla::Config::Advanced;
use strict;

use Bugzilla::Config::Common;

our $sortkey = 1700;

use constant get_param_list => (
  {
   name => 'cookiedomain',
   type => 't',
   default => ''
  },

  {
   name => 'inbound_proxies',
   type => 't',
   default => '',
   checker => \&check_ip
  },

  {
   name => 'proxy_url',
   type => 't',
   default => ''
  },

  {
   name => 'strict_transport_security',
   type => 's',
   choices => ['off', 'this_domain_only', 'include_subdomains'],
   default => 'off',
   checker => \&check_multi
  },

  {
   name => 'disable_bug_updates',
   type => 'b',
   default => 0
  },

  {
   name => 'sentry_uri',
   type => 't',
   default => '',
  },

  {
   name => 'metrics_enabled',
   type => 'b',
   default => 0
  },
  {
   name => 'metrics_user_ids',
   type => 't',
   default => '3881,5038,5898,13647,20209,251051,373476,409787'
  },
  {
   name => 'metrics_elasticsearch_server',
   type => 't',
   default => '127.0.0.1:9200'
  },
  {
   name => 'metrics_elasticsearch_index',
   type => 't',
   default => 'bmo-metrics'
  },
  {
   name => 'metrics_elasticsearch_type',
   type => 't',
   default => 'timings'
  },
  {
   name => 'metrics_elasticsearch_ttl',
   type => 't',
   default => '1210000000' # 14 days
  },
);

1;
