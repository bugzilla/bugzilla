# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

FROM centos
MAINTAINER David Lawrence <dkl@mozilla.com>

# Environment configuration
ENV USER bugzilla
ENV HOME /home/$USER
ENV BUGS_DB_DRIVER mysql
ENV BUGZILLA_ROOT $HOME/devel/htdocs/bugzilla
ENV GITHUB_BASE_GIT https://github.com/bugzilla/bugzilla
ENV GITHUB_BASE_BRANCH master
ENV GITHUB_QA_GIT https://github.com/bugzilla/qa

# Distribution package installation
COPY docker_files /docker_files
RUN yum -y -q update \
    && yum -y -q install https://dev.mysql.com/get/mysql-community-release-el7-5.noarch.rpm epel-release \
    && yum -y -q install `cat /docker_files/rpm_list` \
    && yum clean all

# User configuration
RUN useradd -m -G wheel -u 1000 -s /bin/bash $USER \
    && passwd -u -f $USER \
    && echo "bugzilla:bugzilla" | chpasswd

# Apache configuration
RUN cp /docker_files/bugzilla.conf /etc/httpd/conf.d/bugzilla.conf \
    && chown root.root /etc/httpd/conf.d/bugzilla.conf \
    && chmod 440 /etc/httpd/conf.d/bugzilla.conf

# MySQL configuration
RUN cp /docker_files/my.cnf /etc/my.cnf \
    && chmod 644 /etc/my.cnf \
    && chown root.root /etc/my.cnf \
    && rm -rf /etc/mysql \
    && rm -rf /var/lib/mysql/* \
    && /usr/bin/mysql_install_db --user=$USER --basedir=/usr --datadir=/var/lib/mysql

# Sudoer configuration
RUN cp /docker_files/sudoers /etc/sudoers \
    && chown root.root /etc/sudoers \
    && chmod 440 /etc/sudoers

# Clone the code repo initially
RUN su $USER -c "git clone $GITHUB_BASE_GIT -b $GITHUB_BASE_BRANCH $BUGZILLA_ROOT"

# Bugzilla dependencies and setup
RUN /bin/bash /docker_files/install_deps.sh
RUN /bin/bash /docker_files/bugzilla_config.sh
RUN /bin/bash /docker_files/my_config.sh

# Final permissions fix
RUN chown -R $USER.$USER $HOME

# Networking
RUN echo "NETWORKING=yes" > /etc/sysconfig/network
EXPOSE 80
EXPOSE 5900

# Testing scripts for CI
ADD https://selenium-release.storage.googleapis.com/2.45/selenium-server-standalone-2.45.0.jar /selenium-server.jar

# Supervisor
RUN cp /docker_files/supervisord.conf /etc/supervisord.conf \
    && chmod 700 /etc/supervisord.conf
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
