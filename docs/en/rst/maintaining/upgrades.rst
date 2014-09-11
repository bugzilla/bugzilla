.. _upgrades:

Upgrades
########

For details on how to upgrade Bugzilla, see the :ref:`upgrading` chapter.

Bugzilla can automatically notify administrators when new releases are
available if the  :guilabel:`upgrade_notification` parameter is set. Administrators
will see these notifications when they access the Bugzilla home page. Bugzilla
will check once per day for new releases. If you are behind a proxy, you may
have to set the :guilabel:`proxy_url` parameter accordingly. If the proxy
requires authentication, use the ``http://user:pass@proxy_url/`` syntax.
