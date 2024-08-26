FROM ubuntu:24.04

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && apt-get -y dist-upgrade
RUN apt-get -y install \
    apache2 \
    graphviz \
    libapache2-mod-perl2 \
    libapache2-mod-perl2-dev \
    libappconfig-perl \
    libauthen-radius-perl \
    libauthen-sasl-perl \
    libcache-memcached-perl \
    libcgi-pm-perl \
    libchart-perl \
    libdaemon-generic-perl \
    libdate-calc-perl \
    libdatetime-perl \
    libdatetime-timezone-perl \
    libdbi-perl \
    libdbix-connector-perl \
    libemail-address-perl \
    libemail-address-xs-perl \
    libemail-mime-modifier-perl \
    libemail-mime-perl \
    libemail-reply-perl \
    libemail-sender-perl \
    libencode-detect-perl \
    libfile-copy-recursive-perl \
    libfile-mimeinfo-perl \
    libfile-slurp-perl \
    libfile-which-perl \
    libgd-dev \
    libgd-graph-perl \
    libhtml-formattext-withlinks-perl \
    libhtml-scrubber-perl \
    libjson-rpc-perl \
    liblocale-codes-perl \
    libmath-random-isaac-perl \
    libmath-random-isaac-xs-perl \
    libmodule-build-perl \
    libmysqlclient-dev \
    libnet-ldap-perl \
    libsoap-lite-perl \
    libtemplate-perl \
    libtemplate-plugin-gd-perl \
    libtest-taint-perl \
    libtheschwartz-perl \
    libxml-perl \
    libxml-twig-perl \
    mariadb-client \
    netcat-traditional \
    patchutils \
    perlmagick \
    vim-common

# Ubuntu 24 doesn't ship new enough versions of a few modules or doesn't ship them at all, so get them from CPAN
RUN apt-get -y install build-essential && \
    cpan install Template::Toolkit DBD::MariaDB PatchReader && \
    apt-get -y autoremove build-essential

WORKDIR /var/www/html
COPY --chown=root:www-data . /var/www/html
COPY ./docker/000-default.conf /etc/apache2/sites-available/000-default.conf
COPY ./docker /root/docker

# we don't want Docker droppings accessible by the web browser since they
# might contain setup info you don't want public
RUN rm -rf /var/www/html/docker* /var/www/html/Dockerfile*
RUN rm -rf /var/www/html/data /var/www/html/localconfig /var/www/html/index.html && \
    mkdir /var/www/html/data
RUN a2enmod expires && a2enmod headers && a2enmod rewrite && a2dismod mpm_event && a2enmod mpm_prefork
EXPOSE 80/tcp
CMD docker/startup.sh
