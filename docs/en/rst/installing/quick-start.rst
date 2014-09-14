.. _quick-start:

Quick Start (Ubuntu 14.04 LTS)
##############################

This quick start guide makes installing Bugzilla as simple as possible for
those who are able to choose their environment. It creates a system using
Ubuntu 14.04 LTS, Apache and MySQL, and installs Bugzilla as the default
home page. It requires a little familiarity with Linux and the command line.

0. Obtain Your Hardware

   Ubuntu 14.04 LTS Server requires a 64-bit processor.
   Bugzilla itself has no prerequisites beyond that, although you should pick
   reliable hardware. You can also probably use any 64-bit virtual machine
   or cloud instance that you have root access on. 

1. Install the OS

   Get `Ubuntu Server 14.04 LTS <http://www.ubuntu.com/download/server>`_
   and follow the `installation instructions <http://www.ubuntu.com/download/server/install-ubuntu-server>`_.
   Here are some tips:

   * Choose any server name you like.
   * When creating the initial Linux user, call it "bugzilla", give it a 
     strong password, and write that password down.
   * You do not need an encrypted home directory.
   * Choose all the defaults for the "partitioning" part (excepting of course
     where the default is "No" and you need to press "Yes" to continue).
   * Choose "install security updates automatically" unless you want to do
     them manually.
   * From the install options, choose "OpenSSH Server" and "LAMP Server".
   * Set the password for the MySQL root user to a strong password, and write
     that password down.
   * Install the Grub boot loader to the Master Boot Record.

   Reboot when the installer finishes.

2. Become root

   ssh to the machine as the 'bugzilla' user, or start a console. Then:
   
   :command:`sudo su`
   
3. Install Prerequisites

   :command:`apt-get install git nano`
   
   :command:`apt-get install apache2 mysql-server libappconfig-perl libdate-calc-perl libtemplate-perl libmime-perl build-essential libdatetime-timezone-perl libdatetime-perl libemail-send-perl libemail-mime-perl libemail-mime-modifier-perl libdbi-perl libdbd-mysql-perl libcgi-pm-perl libmath-random-isaac-perl libmath-random-isaac-xs-perl apache2-mpm-prefork libapache2-mod-perl2 libapache2-mod-perl2-dev libchart-perl libxml-perl libxml-twig-perl perlmagick libgd-graph-perl libtemplate-plugin-gd-perl libsoap-lite-perl libhtml-scrubber-perl libjson-rpc-perl libdaemon-generic-perl libtheschwartz-perl libtest-taint-perl libauthen-radius-perl libfile-slurp-perl libencode-detect-perl libmodule-build-perl libnet-ldap-perl libauthen-sasl-perl libtemplate-perl-doc libfile-mimeinfo-perl libhtml-formattext-withlinks-perl libgd-dev lynx-cur`

   This will take a little while. It's split into two commands so you can do
   the next steps (up to step 7) in another terminal while you wait for the
   second command to finish. If you start another terminal, you will need to
   :command:`sudo su` again.

4. Download Bugzilla

   Get it from our Git repository:

   :command:`cd /var/www`

   :command:`rm -rf html`

   :command:`git clone https://git.mozilla.org/bugzilla/bugzilla html`

   :command:`cd html`

   :command:`git checkout bugzilla-stable`

   You will get a notification about having a detached HEAD. Don't worry,
   your head is still firmly on your shoulders.

   XXX is this the right way to get the current bugzilla-stable code? Or
   should we pull directly from a branch?
   
5. Configure MySQL

   The following instructions use the simple :file:`nano` editor, but feel
   free to use any text editor you are comfortable with.

   :command:`nano /etc/mysql/my.cnf`

   Set the following values, which increase the maximum attachment size and
   make it possible to search for short words and terms:

   * Alter on Line 52: ``max_allowed_packet=100M``
   * Add as new line 31, in [mysqld] section: ``ft_min_word_len=2``

   Save and exit.

   XXX default value of maxattachmentsize is 1MB. Default value of max_allowed_packet
   is 16MB. Should we just omit this step entirely, for simplicity? Do we need
   ft_min_word_len changed?

   XXX docs for maxattachmentsize should mention max_allowed_packet. File bug.

   Restart MySQL:
   
   :command:`service mysql restart`
    
6. Configure Apache

   :command:`nano /etc/apache2/sites-available/bugzilla.conf`

   Paste in the following and save:

   .. code-block:: none

     ServerName localhost

     <Directory /var/www/html>
       AddHandler cgi-script .cgi
       Options +ExecCGI
       DirectoryIndex index.cgi index.html
       AllowOverride Limit FileInfo Indexes Options
     </Directory>

   :command:`a2ensite bugzilla`

   :command:`a2enmod cgi headers expires`

   :command:`service apache2 restart`

8. Check Setup

   Bugzilla comes with a :file:`checksetup.pl` script which helps with the
   installation process. It will need to be run twice. The first time, it
   generates a config file (called :file:`localconfig`) for the database
   access information, and the second time (step 10)
   it uses the info you put in the config file to set up the database.

   :command:`cd /var/www/html`
   
   :command:`./checksetup.pl`

9. Edit :file:`localconfig`

   :command:`nano localconfig`

   You will need to set the following values:
   
   * Line 29: set $webservergroup to ``www-data``
   * Line 60: set $db_user to ``root``
   * Line 67: set $db_pass to the MySQL root user password you created when
     installing Ubuntu

   XXX Given this is a quick setup on a dedicated box, is it OK to use the
   MySQL root user?
    
   XXX Why can't checksetup determine webservergroup automatically,
   and prompt for db_user and db_pass, and just keep going? Perhaps with a
   --simple switch?

10. Check Setup (again)

    Run the :file:`checksetup.pl` script again to set up the database.
   
    :command:`./checksetup.pl`

    It will ask you to give an email address, real name and password for the
    first Bugzilla account to be created, which will be an administrator.
    Write down the email address and password you set.

11. Test Server

    :command:`./testserver.pl http://localhost/`

    All the tests should pass. (Note: currently, the first one will give a
    warning instead. You can ignore that. Bug 1040728.)

    XXX Also, Chart::Base gives deprecation warnings :-|
   
12. Access Via Web Browser

    Access the front page:

    :command:`lynx http://localhost/`

    It's not really possible to use Bugzilla for real through Lynx, but you
    can view the front page to validate visually that it's up and running.
    
    You might well need to configure your DNS such that the server has, and
    is reachable by, a name rather than IP address. Doing so is out of scope
    of this document. In the mean time, it is available on your local network
    at ``http://<ip address>/``, where ``<ip address>`` is (unless you have
    a complext network setup) the "inet addr" value displayed when you run
    :command:`ifconfig eth0`.

13. Configure Bugzilla

    Once you have worked out how to access your Bugzilla in a graphical
    web browser, bring up the front page, click "Log In" in the header, and
    log in as the admin user you defined in step 10.

    Click the "Parameters" link on the page it gives you, and set the
    following parameters in the 'Required Settings' section:

    * urlbase: ``http://<servername>/`` or ``http://<ip address>/``

    Click "Save Changes" at the bottom of the page.

    There are several ways to get Bugzilla to send email. The easiest is to
    use Gmail, so we do that here so you have it working. Visit
    https://gmail.com and create a new Gmail account for your Bugzilla to use.
    Then, open the "Email" section of the Parameters using the link in the
    left column, and set the following parameter values:
    
    * mail_delivery_method: SMTP
    * mailfrom: ``new_gmail_address@gmail.com``
    * smtpserver: ``smtp.gmail.com:465``
    * smtp_username: ``new_gmail_address@gmail.com``
    * smtp_password: ``new_gmail_password``
    * smtp_ssl: On

    Click "Save Changes" at the bottom of the page.

    XXX There should be a "send test email" button on that page

    Now proceed to Chapter XXX, "Initial Configuration".
