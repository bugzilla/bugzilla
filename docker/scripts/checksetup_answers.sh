#!/bin/bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

: ${WEB_HOST:=localhost}
: ${DB_PORT_3306_TCP_ADDR:=localhost}
: ${DB_PORT_3306_TCP_PORT:=3306}
: ${DB_ENV_MYSQL_DATABASE:=bugs}
: ${DB_ENV_MYSQL_USER:=bugs}
: ${DB_ENV_MYSQL_PASSWORD:=bugs}
: ${MEMCACHED_PORT_11211_TCP_ADDR:=localhost}

cat <<EOF
\$answer{'ADMIN_EMAIL'} = 'admin@mozilla.test';
\$answer{'ADMIN_OK'} = 'Y';
\$answer{'ADMIN_PASSWORD'} = 'password';
\$answer{'ADMIN_REALNAME'} = 'QA Admin';
\$answer{'NO_PAUSE'} = 1;
\$answer{'bugzilla_version'} = '4.2';
\$answer{'create_htaccess'} = '';
\$answer{'cvsbin'} = '/usr/bin/cvs';
\$answer{'db_check'} = 1;
\$answer{'db_driver'} = 'mysql';
\$answer{'db_host'} = '$DB_PORT_3306_TCP_ADDR';
\$answer{'db_mysql_ssl_ca_file'} = '';
\$answer{'db_mysql_ssl_ca_path'} = '';
\$answer{'db_mysql_ssl_client_cert'} = '';
\$answer{'db_mysql_ssl_client_key'} = '';
\$answer{'db_name'} = '$DB_ENV_MYSQL_DATABASE';
\$answer{'db_pass'} = '$DB_ENV_MYSQL_PASSWORD';
\$answer{'db_port'} = $DB_PORT_3306_TCP_PORT;
\$answer{'db_sock'} = '';
\$answer{'db_user'} = '$DB_ENV_MYSQL_USER';
\$answer{'diffpath'} = '/usr/bin';
\$answer{'index_html'} = 0;
\$answer{'interdiffbin'} = '/usr/bin/interdiff';
\$answer{'memcached_servers'} = '$MEMCACHED_PORT_11211_TCP_ADDR:11211';
\$answer{'urlbase'} = 'http://$WEB_HOST/docker-bmo/';
\$answer{'use_suexec'} = '';
\$answer{'webservergroup'} = 'bugzilla';
EOF

