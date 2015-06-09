FROM centos:centos7
MAINTAINER David Lawrence <dkl@mozilla.com>

# Environment configuration
ENV BUGS_DB_DRIVER mysql
ENV BUGS_DB_NAME bugs
ENV BUGS_DB_PASS bugs
ENV BUGS_DB_HOST localhost

ENV BUGZILLA_USER bugzilla
ENV BUGZILLA_HOME /home/$BUGZILLA_USER
ENV BUGZILLA_ROOT $BUGZILLA_HOME/devel/htdocs/bmo
ENV BUGZILLA_URL http://localhost/bmo

ENV GITHUB_BASE_GIT https://github.com/mozilla/webtools-bmo-bugzilla
ENV GITHUB_BASE_BRANCH master
ENV GITHUB_QA_GIT https://github.com/mozilla/webtools-bmo-qa

ENV ADMIN_EMAIL admin@mozilla.bugs
ENV ADMIN_PASS password

# Distribution package installation
COPY rpm_list /rpm_list
RUN yum -y -q install https://dev.mysql.com/get/mysql-community-release-el7-5.noarch.rpm \
    epel-release && yum clean all
RUN yum -y -q install `cat /rpm_list` && yum clean all

# User configuration
RUN useradd -m -G wheel -u 1000 -s /bin/bash $BUGZILLA_USER \
    && passwd -u -f $BUGZILLA_USER \
    && echo "bugzilla:bugzilla" | chpasswd

# sshd
RUN mkdir -p /var/run/sshd \
    && chmod -rx /var/run/sshd \
    && ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N '' \
    && ssh-keygen -t dsa -f /etc/ssh/ssh_host_dsa_key -N '' \
    && ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -N '' \
    && sed -ri 's/#UseDNS yes/UseDNS no/'g /etc/ssh/sshd_config

# Apache configuration
COPY bugzilla.conf /etc/httpd/conf.d/bugzilla.conf

# MySQL configuration
COPY my.cnf /etc/my.cnf
RUN chmod 644 /etc/my.cnf \
    && chown root.root /etc/my.cnf \
    && rm -rf /etc/mysql \
    && rm -rf /var/lib/mysql/* \
    && /usr/bin/mysql_install_db --user=$BUGZILLA_USER --basedir=/usr --datadir=/var/lib/mysql

# Sudoer configuration
COPY sudoers /etc/sudoers
RUN chown root.root /etc/sudoers && chmod 440 /etc/sudoers

# Clone the code repo
RUN su $BUGZILLA_USER -c "git clone $GITHUB_BASE_GIT -b $GITHUB_BASE_BRANCH $BUGZILLA_ROOT"

# Copy setup and test scripts
COPY *.sh buildbot_step generate_bmo_data.pl checksetup_answers.txt /
RUN chmod 755 /*.sh /buildbot_step

# Bugzilla dependencies and setup
RUN /install_deps.sh
RUN /bugzilla_config.sh
RUN /my_config.sh

# Final permissions fix
RUN chown -R $BUGZILLA_USER.$BUGZILLA_USER $BUGZILLA_HOME

# Networking
RUN echo "NETWORKING=yes" > /etc/sysconfig/network
EXPOSE 80
EXPOSE 22
EXPOSE 5900

# Testing scripts for CI
ADD https://selenium-release.storage.googleapis.com/2.45/selenium-server-standalone-2.45.0.jar /selenium-server.jar

# Supervisor
COPY supervisord.conf /etc/supervisord.conf
RUN chmod 700 /etc/supervisord.conf
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
