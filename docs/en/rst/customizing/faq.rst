.. _customization-faq:

Customization FAQ
=================

How do I...

...add a new field on a bug?
  Use :ref:`custom-fields` or, if you just want new form fields on bug entry
  but don't need Bugzilla to track the field seperately thereafter, you can
  use a :ref:`custom bug entry form <custom-bug-entry>`.

...change the name of a built-in bug field?
  :ref:`Edit <templates>` the relevant value in the template
  :file:`template/en/default/global/field-descs.none.tmpl`.

...use a word other than 'bug' to describe bugs?
  :ref:`Edit or override <templates>` the appropriate values in the template
  :file:`template/en/default/global/variables.none.tmpl`.
  
...call the system something other than 'Bugzilla'?
  :ref:`Edit or override <templates>` the appropriate value in the template
  :file:`template/en/default/global/variables.none.tmpl`.
  
...alter who can change what field when?
  See :ref:`who-can-change-what`.

...make Bugzilla send mails?
  See :ref:`email` and check the settings according to your environment, especially you should check if a maybe configured SMTP server can be reached from your Bugzilla server and if the maybe needed auth credentials are valid. If things seem correct and your mails are still not send, check if your OS uses SELinux or AppArmor which may prevent your web server from sending mails. Some keywords for often used SELinux are are httpd_can_sendmail and httpd_can_network_connect.

.. todo:: Ask Thorsten for his input on what questions are common.
