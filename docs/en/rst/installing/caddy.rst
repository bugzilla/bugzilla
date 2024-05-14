
.. _caddy:

Caddy
#####

The Caddy web server has built in support for reverse proxies. 

It also automates the creation of Let's Encrypt certificates for 
the hosts specified in the Caddyfile.

An example Caddyfile for Bugzilla would be:

.. code-block::
    
    hostname {
        reverse_proxy 127.0.0.1:3001
    }

.. note:: 
    You may need to start the Bugzilla web app using ``MOJO_REVERSE_PROXY=1 ./bugzilla.pl daemon`` when running behind Caddy.
