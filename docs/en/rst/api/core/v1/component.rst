Components
==========

This part of the Bugzilla API allows you to deal with the available product
components. You will be able to get information about them as well as manipulate
them.

.. _rest_create_component:

Create Component
----------------

This allows you to create a new component in Bugzilla. You must be authenticated
and be in the *editcomponents* group to perform this action.

**Request**

To create a new component:

.. code-block:: text

   POST /rest/component

.. code-block:: js

   {
     "product" : "TestProduct",
     "name" : "New Component",
     "description" : "This is a new component",
     "default_assignee" : "dkl@mozilla.com"
   }

Some params must be set, or an error will be thrown. These params are
shown in **bold**.

====================  =======  ==================================================
name                  type     description
====================  =======  ==================================================
**name**              string   The name of the new component.
**product**           string   The name of the product that the component must
                               be added to. This product must already exist, and
                               the user have the necessary permissions to edit
                               components for it.
**description**       string   The description of the new component.
**default_assignee**  string   The login name of the default assignee of the
                               component.
default_cc            array    Each string representing one login name of the
                               default CC list.
default_qa_contact    string   The login name of the default QA contact for the
                               component.
is_open               boolean  1 if you want to enable the component for bug
                               creations. 0 otherwise. Default is 1.
====================  =======  ==================================================

**Response**

.. code-block:: js

   {
     "id": 27
   }

====  ====  ========================================
name  type  description
====  ====  ========================================
id    int   The ID of the newly-added component.
====  ====  ========================================

**Errors**

* 304 (Authorization Failure)
  You are not authorized to create a new component.
* 1200 (Component already exists)
  The name that you specified for the new component already exists in the
  specified product.

.. _rest_update_component:

Update Component
----------------

This allows you to update one or more components in Bugzilla.

**Request**

.. code-block:: text

   PUT /rest/component/<component_id>
   PUT /rest/component/<product_name>/<component_name>

The params to include in the PUT body as well as the returned data format,
are the same as below. The "ids" and "names" params will be overridden as
it is pulled from the URL path.

==================  =======  ==============================================================
name                type     description
==================  =======  ==============================================================
**ids**             array    Numeric ids of the components that you wish to update.
**names**           array    Objects with names of the components that you wish to update.
                             The object keys are "product" and "component", representing
                             the name of the product and the component you wish to change.
name                string   A new name for this component. If you try to set this while
                             updating more than one component for a product, an error
                             will occur, as component names must be unique per product.
description         string   Update the long description for these components to this value.
default_assignee    string   The login name of the default assignee of the component.
default_cc          array    An array of strings with each element representing one
                             login name of the default CC list.
default_qa_contact  string   The login name of the default QA contact for the component.
is_open             boolean  True if the component is currently allowing bugs to be
                             entered into it, False otherwise.
==================  =======  ==============================================================

**Response**

.. code-block:: js

   {
     "components" : [
       {
         "id" : 123,
         "changes" : {
           "name" : {
             "removed" : "FooName",
             "added"   : "BarName"
           },
           "default_assignee" : {
             "removed" : "foo@company.com",
             "added"   : "bar@company.com"
           }
         }
       }
     ]
   }

An object with a single field "components". This points to an array of objects
with the following fields:

=======  =======  =================================================================
name     type     description
=======  =======  =================================================================
id       int      The id of the component that was updated.
changes  object   The changes that were actually done on this component. The keys
                  are the names of the fields that were changed, and the values
                  are an object with two keys:

                  added (string) The value that this field was changed to.
                  removed (string) The value that was previously set in this field.
=======  =======  =================================================================

Note that booleans will be represented with the strings '1' and '0'.

**Errors**

* 51 (User does not exist)
  One of the contact e-mail addresses is not a valid Bugzilla user.
* 106 (Product access denied)
  The product you are trying to modify does not exist or you don't have access to it.
* 706 (Product admin denied)
  You do not have the permission to change components for this product.
* 105 (Component name too long)
  The name specified for this component was longer than the maximum
  allowed length.
* 1200 (Component name already exists)
  You specified the name of a component that already exists.
  (Component names must be unique per product in Bugzilla.)
* 1210 (Component blank name)
  You must specify a non-blank name for this component.
* 1211 (Component must have description)
  You must specify a description for this component.
* 1212 (Component name is not unique)
  You have attempted to set more than one component in the same product with the
  same name. Component names must be unique in each product.
* 1213 (Component needs a default assignee)
  A default assignee is required for this component.

.. _rest_delete_component:

Delete Component
----------------

This allows you to delete one or more components in Bugzilla.

**Request**

.. code-block:: text

   DELETE /rest/component/<component_id>
   DELETE /rest/component/<product_name>/<component_name>

=========  =====  ============================================================
name       type   description
=========  =====  ============================================================
**ids**    int    Numeric ids of the components that you wish to delete.
**names**  array  Objects containing the names of the components that you wish
                  to delete. The object keys are "product" and "component",
                  representing the name of the product and the component you
                  wish to delete.
=========  =====  ============================================================

**Response**

An object with a single field "components". This points to an array of objects
with the following field:

====  ====  =========================================
name  type  description
====  ====  =========================================
id    int   The id of the component that was deleted.
====  ====  =========================================

.. code-block:: js

   {
     "components" : [
       {
         "id" : 123,
       }
     ]
   }

**Errors**

* 106 (Product access denied)
  The product you are trying to modify does not exist or you don't have access to it.
* 706 (Product admin denied)
  You do not have the permission to delete components for this product.
* 1202 (Component has bugs)
  The component you are trying to delete currently has bugs assigned to it.
  You must move these bugs before trying to delete the component.
