FROM centos:centos7
MAINTAINER David Lawrence <dkl@mozilla.com>

ADD CLOBBER /CLOBBER

# Environment configuration
ENV container docker
ENV BUGS_DB_DRIVER mysql
ENV BUGS_DB_NAME bugs
ENV BUGS_DB_PASS bugs
ENV BUGS_DB_HOST localhost

ENV BUGZILLA_USER bugzilla
ENV BUGZILLA_HOME /home/$BUGZILLA_USER/devel/htdocs/bmo
ENV BUGZILLA_URL http://localhost/bmo

ENV GITHUB_BASE_GIT https://github.com/mozilla/webtools-bmo-bugzilla
ENV GITHUB_BASE_BRANCH master
ENV GITHUB_QA_GIT https://github.com/mozilla/webtools-bmo-qa

ENV ADMIN_EMAIL admin@mozilla.bugs
ENV ADMIN_PASS password
ENV TEST_SUITE sanity
ENV CPANM cpanm --quiet --notest --skip-satisfied

# Software installation
RUN yum -y -q update && yum clean all
ADD rpm_list /rpm_list
RUN yum -y -q install https://dev.mysql.com/get/mysql-community-release-el7-5.noarch.rpm \
    && yum clean all
RUN yum -y -q install epel-release \
    && yum clean all
RUN yum -y -q install `cat /rpm_list` && yum clean all

# User configuration
RUN useradd -m -G wheel -u 1000 -s /bin/bash $BUGZILLA_USER
RUN passwd -u -f $BUGZILLA_USER
RUN echo "bugzilla:bugzilla" | chpasswd

# sshd
RUN mkdir -p /var/run/sshd; chmod -rx /var/run/sshd
RUN ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N ''
RUN ssh-keygen -t dsa -f /etc/ssh/ssh_host_dsa_key -N ''
RUN ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -N ''
RUN sed -ri 's/#UseDNS yes/UseDNS no/'g /etc/ssh/sshd_config

# Apache configuration
ADD bugzilla.conf /etc/httpd/conf.d/bugzilla.conf

# MySQL configuration
ADD my.cnf /etc/my.cnf
RUN chmod 644 /etc/my.cnf; chown root.root /etc/my.cnf
RUN rm -rf /etc/mysql
RUN rm -rf /var/lib/mysql/*
RUN /usr/bin/mysql_install_db --user=$BUGZILLA_USER --basedir=/usr --datadir=/var/lib/mysql

# Sudoer configuration
ADD sudoers /etc/sudoers
RUN chown root.root /etc/sudoers; chmod 440 /etc/sudoers

# Clone the code repo
RUN su $BUGZILLA_USER -c "git clone $GITHUB_BASE_GIT -b $GITHUB_BASE_BRANCH $BUGZILLA_HOME"

# Install Perl dependencies
# Some modules are explicitly installed due to strange dependency issues
RUN $CPANM Email::MIME::Attachment::Stripper \
    && $CPANM File::Slurp \
    && $CPANM Image::Magick@6.77 \
    && $CPANM JSON::RPC \
    && $CPANM MIME::Parser \
    && $CPANM Template::Plugin::GD::Image \
    && $CPANM Test::WWW::Selenium \
    && $CPANM TheSchwartz \
    && $CPANM XMLRPC::Lite
RUN cd $BUGZILLA_HOME \
    && ./checksetup.pl --cpanfile \
    && $CPANM --installdeps --with-recommends --with-all-features \
       --without-feature oracle --without-feature sqlite --without-feature pg .

# Bugzilla configuration
ADD checksetup_answers.txt /checksetup_answers.txt
ADD generate_bmo_data.pl /generate_bmo_data.pl
ADD bugzilla_config.sh /bugzilla_config.sh
RUN chmod 755 /bugzilla_config.sh /generate_bmo_data.pl
RUN /bugzilla_config.sh

# Final permissions fix
RUN chmod 711 /home/$BUGZILLA_USER
RUN chown -R $BUGZILLA_USER.$BUGZILLA_USER /home/$BUGZILLA_USER

# Run any custom configuration
ADD my_config.sh /my_config.sh
RUN chmod 755 /my_config.sh
RUN /my_config.sh

# Networking
RUN echo "NETWORKING=yes" > /etc/sysconfig/network
EXPOSE 80
EXPOSE 22

# Testing script for CI
RUN wget https://selenium-release.storage.googleapis.com/2.45/selenium-server-standalone-2.45.0.jar \
    -O /selenium-server.jar
RUN wget https://raw.githubusercontent.com/taskcluster/buildbot-step/master/buildbot_step \
    -O /buildbot_step
RUN chmod 755 /buildbot_step
ADD runtests.sh /runtests.sh
RUN chmod 755 /runtests.sh

# Supervisor
ADD supervisord.conf /etc/supervisord.conf
RUN chmod 700 /etc/supervisord.conf
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
