FROM ubuntu:22.04

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && apt-get -y dist-upgrade
RUN apt-get -y install \
 apache2 \
 mariadb-client \
 netcat-traditional \
 libappconfig-perl \
 libdate-calc-perl \
 libtemplate-perl \
 build-essential \
 libdatetime-timezone-perl \
 libdatetime-perl \
 libemail-address-perl \
 libemail-sender-perl \
 libemail-mime-perl \
 libemail-mime-modifier-perl \
 libdbi-perl \
 libdbix-connector-perl \
 libcgi-pm-perl \
 liblocale-codes-perl \
 libmath-random-isaac-perl \
 libmath-random-isaac-xs-perl \
 libapache2-mod-perl2 \
 libapache2-mod-perl2-dev \
 libchart-perl \
 libxml-perl \
 libxml-twig-perl \
 perlmagick \
 libgd-graph-perl \
 libtemplate-plugin-gd-perl \
 libsoap-lite-perl \
 libhtml-scrubber-perl \
 libjson-rpc-perl \
 libdaemon-generic-perl \
 libtheschwartz-perl \
 libtest-taint-perl \
 libauthen-radius-perl \
 libfile-slurp-perl \
 libencode-detect-perl \
 libmodule-build-perl \
 libnet-ldap-perl \
 libauthen-sasl-perl \
 libfile-mimeinfo-perl \
 libhtml-formattext-withlinks-perl \
 libgd-dev \
 libmysqlclient-dev \
 graphviz \
 vim-common

# Ubuntu22 doesn't ship new enough versions of a few modules, so get them from CPAN
RUN cpan install Template::Toolkit Email::Address::XS Email::Sender DBD::MariaDB

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
