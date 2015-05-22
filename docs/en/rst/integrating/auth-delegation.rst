.. _auth-delegation:

Authentication Delegation via API Keys
######################################

Bugzilla provides a mechanism for web apps to request (with the user's consent)
an API key. API keys allow the web app to perform any action as the user and are as
a result very powerful. Because of this power, this feature is disabled by default.

Authentication Flow
-------------------

The authentication process begins by directing the user to th the Bugzilla site's auth.cgi.
For the sake of this example, our application's URL is `http://app.example.org`
and the Bugzilla site is `http://bugs.example.org`.

1. Provide a link or redirect the user to `http://bugs.example.org/auth.cgi?callback=http://app.example.org/callback&description=app%description`
2. Assuming the user is agreeable, they will be redirected to `http://app.example.org/callback` via a GET request
   with two additional parameters: `client_api_key` and `client_api_login`.
3. Finally, you should check that the API key and login are valid, using the :ref:`rest_user_valid_login` REST
   resource.

Your application should take measures to ensure when receiving a user at your
callback URL that you previously redirected them to Bugzilla. The simplest method would be ensuring the callback url always has the
hostname and path you specified, with only the query string parameters varying.

The description should include the name of your application, in a form that will be recognizable to users.
This description is used in the :ref:`API Keys tab <api-keys>` in the Preferences page.

The API key passed to the callback will be valid until the user revokes it.
