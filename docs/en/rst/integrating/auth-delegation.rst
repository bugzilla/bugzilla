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
2. Assuming the user is agreeable, the following will happen:
  1. Bugzilla will issue a POST request to `http://app.example.org/callback`
     with a the request body data being a JSON object with keys `client_api_key` and `client_api_login`.
  2. The callback, when responding to the POST request must return a JSON object with a key `result`. This result
     is intended to be a unique token used to identify this transaction.
  3. Bugzilla will then cause the useragent to redirect (using a GET request) to `http://app.example.org/callback`
     with additional query string parameters `client_api_login` and `callback_result`.
  4. At this point, the consumer now has the api key and login information. Be sure to compare the `callback_result` to whatever result was initially sent back
     to Bugzilla.
3. Finally, you should check that the API key and login are valid, using the :ref:`rest_user_valid_login` REST
   resource.

Your application should take measures to ensure when receiving a user at your
callback URL that you previously redirected them to Bugzilla. The simplest method would be ensuring the callback url always has the
hostname and path you specified, with only the query string parameters varying.

The description should include the name of your application, in a form that will be recognizable to users.
This description is used in the :ref:`API Keys tab <api-keys>` in the Preferences page.

The API key passed to the callback will be valid until the user revokes it.
