.. _auth0:

Adding an Auth0 Custom Social Integration
#########################################

Bugzilla can be added as a 'Custom Social Connection'.

====================  ============================================      ======================================================
Parameter             Example(s)                                        Notes
--------------------  --------------------------------------------      ------------------------------------------------------
Name                  BMO-Stage                                         Whatever makes you happy
Client ID             aaaaaaaaaaaaaaaaaaaa                              Ask your Bugzilla admin to create one for you.
Client Secret         aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa          Same as above.
Authorization URL     https://bugzilla.allizom.org/oauth/authorize      Note the http client must use the correct HOST header.
Token URL             https://bugzilla.allizom.org/oauth/access_token   (none)
Scope                 user:read                                         As of this writing, this is the only scope available.
Fetch User Profile    (see below)                                       (none)

.. code-block:: javascript
  function (access_token, ctx, callback) {
    request.get('https://bugzilla.allizom.org/api/user/profile', {
      'headers': {
        'Authorization': 'Bearer ' + access_token,
        'User-Agent': 'Auth0'
      }
    }, function (e, r, b) {
      if (e) {
        return callback(e);
      }
      if (r.statusCode !== 200) {
        return callback(new Error(`StatusCode: ${r.statusCode}`));
      }
      var profile = JSON.parse(b);
      callback(null, {
        user_id: profile.id,
        nickname: profile.nick,
        name: profile.name,
        email: profile.login,
        email_verified: true
      });
    });
  }
