# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Initial Developer of the Original Code is Everything Solved.
# Portions created by Everything Solved are Copyright (C) 2007
# Everything Solved. All Rights Reserved.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# Contributor(s): Max Kanat-Alexander <mkanat@bugzilla.org>

# This file contains a single hash named %strings, which is used by the
# installation code to display strings before Template-Toolkit can safely
# be loaded.
#
# Each string supports a very simple substitution system, where you can
# have variables named like ##this## and they'll be replaced by the string
# variable with that name.
#
# Please keep the strings in alphabetical order by their name.

%strings = (
    any  => 'any',
    blacklisted => '(blacklisted)',
    checking_for => 'Checking for',
    checking_dbd      => 'Checking available perl DBD modules...',
    checking_optional => 'The following Perl modules are optional:',
    checking_modules  => 'Checking perl modules...',
    chmod_failed      => '##path##: Failed to change permissions: ##error##',
    chown_failed      => '##path##: Failed to change ownership: ##error##',
    commands_dbd      => <<EOT,
YOU MUST RUN ONE OF THE FOLLOWING COMMANDS (depending on which database
you use):
EOT
    commands_optional => 'COMMANDS TO INSTALL OPTIONAL MODULES:',
    commands_required => <<EOT,
COMMANDS TO INSTALL REQUIRED MODULES (You *must* run all these commands
and then re-run this script):
EOT
    done => 'done.',
    extension_must_return_name => <<END,
##file## returned ##returned##, which is not a valid name for an extension.
Extensions must return their name, not <code>1</code> or a number. See
the documentation of Bugzilla::Extension for details.
END
    feature_auth_ldap         => 'LDAP Authentication',
    feature_auth_radius       => 'RADIUS Authentication',
    feature_graphical_reports => 'Graphical Reports',
    feature_html_desc         => 'More HTML in Product/Group Descriptions',
    feature_inbound_email     => 'Inbound Email',
    feature_jobqueue          => 'Mail Queueing',
    feature_jsonrpc           => 'JSON-RPC Interface',
    feature_new_charts        => 'New Charts',
    feature_old_charts        => 'Old Charts',
    feature_mod_perl          => 'mod_perl',
    feature_moving            => 'Move Bugs Between Installations',
    feature_patch_viewer      => 'Patch Viewer',
    feature_smtp_auth         => 'SMTP Authentication',
    feature_updates           => 'Automatic Update Notifications',
    feature_xmlrpc            => 'XML-RPC Interface',

    header => "* This is Bugzilla ##bz_ver## on perl ##perl_ver##\n"
            . "* Running on ##os_name## ##os_ver##",
    install_all => <<EOT,

To attempt an automatic install of every required and optional module
with one command, do:

  ##perl## install-module.pl --all

EOT
    install_data_too_long => <<EOT,
WARNING: Some of the data in the ##table##.##column## column is longer than
its new length limit of ##max_length## characters. The data that needs to be
fixed is printed below with the value of the ##id_column## column first and
then the value of the ##column## column that needs to be fixed:

EOT
    install_module => 'Installing ##module## version ##version##...',
    installation_failed => '*** Installation aborted. Read the messages above. ***',
    max_allowed_packet => <<EOT,
WARNING: You need to set the max_allowed_packet parameter in your MySQL
configuration to at least ##needed##. Currently it is set to ##current##.
You can set this parameter in the [mysqld] section of your MySQL
configuration file.
EOT
    min_version_required => "Minimum version required: ",

# Note: When translating these "modules" messages, don't change the formatting
# if possible, because there is hardcoded formatting in 
# Bugzilla::Install::Requirements to match the box formatting.
    modules_message_db => <<EOT,
***********************************************************************
* DATABASE ACCESS                                                     *
***********************************************************************
* In order to access your database, Bugzilla requires that the        *
* correct "DBD" module be installed for the database that you are     *
* running. See below for the correct command to run to install the    *
* appropriate module for your database.                               *
EOT
    modules_message_optional => <<EOT,
***********************************************************************
* OPTIONAL MODULES                                                    *
***********************************************************************
* Certain Perl modules are not required by Bugzilla, but by           *
* installing the latest version you gain access to additional         *
* features.                                                           *
*                                                                     *
* The optional modules you do not have installed are listed below,    *
* with the name of the feature they enable. Below that table are the  *
* commands to install each module.                                    *
EOT
    modules_message_required => <<EOT,
***********************************************************************
* REQUIRED MODULES                                                    *
***********************************************************************
* Bugzilla requires you to install some Perl modules which are either *
* missing from your system, or the version on your system is too old. *
* See below for commands to install these modules.                    *
EOT

    module_found => "found v##ver##",
    module_not_found => "not found",
    module_ok => 'ok',
    module_unknown_version => "found unknown version",
    ppm_repo_add => <<EOT,
***********************************************************************
* Note For Windows Users                                              *
***********************************************************************
* In order to install the modules listed below, you first have to run * 
* the following command as an Administrator:                          *
*                                                                     *
*   ppm repo add theory58S ##theory_url##
EOT
    ppm_repo_up => <<EOT,
*                                                                     *
* Then you have to do (also as an Administrator):                     *
*                                                                     *
*   ppm repo up theory58S                                             *
*                                                                     *
* Do that last command over and over until you see "theory58S" at the *
* top of the displayed list.                                          *
EOT
    template_precompile   => "Precompiling templates...",
    template_removal_failed => <<END,
WARNING: The directory '##datadir##/template' could not be removed.
         It has been moved into '##datadir##/deleteme', which should be
         deleted manually to conserve disk space.
END
    template_removing_dir => "Removing existing compiled templates...",
);

1;
