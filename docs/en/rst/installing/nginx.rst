.. _nginx:

Nginx
#####

Note: Running with nginx requires much more setup and a fair bit of knowledge
about web server configuration. Most users will want to use Apache instead.

You can run Bugzilla under nginx using the traditional CGI emulation method
with fcgiwrap, as a PSGI application using Plack's FCGI handler, or via proxy
to a server directly supporting CGI or PSGI. The last method is not recommended
and will not be discussed further here.

If using fcgiwrap, configure that in the normal way.

If using Plack, install that, then arrange for the following command to be run
on startup:

:command:`plackup -s FCGI --listen /run/bugzilla.sock /var/www/html/bugzilla/app.psgi`

For any configuration:

It is highly recommended that you configure a system user specifically for
Bugzilla and set the ``$use_suexec`` variable in localconfig to 1. Either way,
make sure that ``$webservergroup`` is set to the user that is actually running
Bugzilla.

Use the following server block, adjusting to taste. Angle brackets are placed
around the strings that must be changed.

.. code-block:: nginx

    server {
        server_name <bugs.example.com>;

        root </var/www/html/bugzilla>;

        # optional if you don't have the autoindex module or have it off already
        autoindex off;

        # these do not conflict. see nginx's "location" documentation for more
        # information.
        location /attachments { return 403; }
        location /Bugzilla { return 403; }
        location /lib { return 403; }
        location /template { return 403; }
        location /contrib { return 403; }
        location /t { return 403; }
        location /xt { return 403; }
        location /data { return 403; }
        location /graphs { return 403; }
        location /rest {
            rewrite ^/rest/(.*)$ rest.cgi/$1 last;
        }

        location ~ (\.pm|\.pl|\.psgi|\.tmpl|localconfig.*|cpanfile)$ { return 403; }
        # if you are using webdot. adjust the IP to point to your webdot server.
        #location ~ ^/data/webdot/[^/]*\.dot$ { allow 127.0.0.1; deny all; }
        location ~ ^/data/webdot/[^/]*\.png$ { }
        location ~ ^/graphs/[^/]*\.(png|gif) { }
        location ~ \.(css|js)$ {
            expires 1y;
            add_header Cache-Control public;
        }
        location ~ \.cgi$ {
            location ~ ^/(json|xml)rpc\.cgi {
                # authenticated queries contain plain text passwords in the
                # query string, so we replace $request with $uri. adjust if you
                # aren't using "combined" log format.
                access_log </var/log/nginx/bugzilla.log>
                    '$remote_addr - $remote_user [$time_local] '
                    '"$uri" $status $body_bytes_sent '
                    '"$http_referer" "$http_user_agent"';
            }
            include fastcgi_params;
            # omit the following two lines if using fcgiwrap
            fastcgi_param SCRIPT_NAME '';
            fastcgi_param PATH_INFO $uri;
            fastcgi_param BZ_CACHE_CONTROL 1;
            fastcgi_pass <unix:/run/bugzilla.sock>;
        }

        # optional but highly recommended due to the large sizes of these files
        gzip on;
        # add whatever global types you have specified; this option does not stack.
        gzip_types text/xml application/rdf+xml;
    }
