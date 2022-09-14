.. This document is shared among all non-Windows OSes.

.. _nginx:

Nginx
#####

To run Bugzilla under Nginx, you will need ``fcgiwrap`` and ``spawn-fcgi``
packages. If they aren't provided by your distribution, follow
`fcgiwrap <https://www.nginx.com/resources/wiki/start/topics/examples/fcgiwrap/>`_ and
`spawn-fcgi <https://github.com/lighttpd/spawn-fcgi>`_ installation instructions.

These instructions provide you with site configuration that needs to be put in a
separate file in :file:`/etc/nginx/conf.d/` directory. Its name has to end with
``.conf`` extension. Some operating systems also provide :file:`/etc/nginx/vhosts.d/`
directory, which would be much more fitting for this, if that's a directory that exists
for you.

In these instructions, when asked to restart Nginx, the command is:

:command:`sudo nginx -s reopen`

(or run it as root if your OS installation does not use sudo).

Main Nginx configuration
========================

To configure your Nginx web server to work with Bugzilla do the following:

#. Edit the Nginx site configuration file (see above).

#. Create a ``server`` directive that applies to the location
   of your Bugzilla installation. In this example, Bugzilla has
   been installed at :file:`/var/www/html/bugzilla`. On macOS, use
   :file:`/Library/WebServer/Documents/bugzilla`.

.. code-block:: nginx

   # Log Format without query parameters, for added security
   log_format no_query '$remote_addr - $remote_user [$time_local] '
                       '"$uri" $status $body_bytes_sent '
                       '"$http_referer" "$http_user_agent"';

   server {
       listen 80;
       server_name server.example.com;

       # You may need that directory if it doesn't exist, or to make it easier to find these logs
       access_log /var/log/nginx/bugzilla_access.log no_query;

       keepalive_timeout 70;

       charset utf-8;

       root /var/www/html/bugzilla/;
       index index.cgi index.html;

       location ~ ^.*\.cgi$ {
           fastcgi_pass  unix:/var/run/fcgiwrap.sock;
           fastcgi_index index.cgi;
           fastcgi_param SCRIPT_FILENAME /var/www/html/bugzilla/$fastcgi_script_name;
           include /etc/nginx/fastcgi_params;
       }
   }

These instructions allow Nginx to run .cgi files found within the Bugzilla
directory; instructs the server to look for a file called :file:`index.cgi`
or, if not found, :file:`index.html` if someone only types the directory name
into the browser.
