FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get -y dist-upgrade && \
    apt-get -y install --no-install-recommends \
    apache2 \
    graphviz \
    libapache2-mod-perl2 \
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
    libdbd-mariadb-perl \
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
    libgd-graph-perl \
    libhtml-formattext-withlinks-perl \
    libhtml-scrubber-perl \
    libjson-rpc-perl \
    libjson-xs-perl \
    liblocale-codes-perl \
    libmath-random-isaac-perl \
    libmath-random-isaac-xs-perl \
    libmodule-build-perl \
    libnet-ldap-perl \
    libsoap-lite-perl \
    libtemplate-perl \
    libtemplate-plugin-gd-perl \
    libtest-taint-perl \
    libtheschwartz-perl \
    libxml-perl \
    libxmlrpc-lite-perl \
    libxml-twig-perl \
    mariadb-client \
    netcat-traditional \
    patchutils \
    perlmagick \
    tzdata \
    vim-common && \
    apt-get -y install --no-install-recommends make && \
    cpan install PatchReader && \
    rm -rf /root/.cpan && \
    apt-get purge -y --auto-remove make && \
    rm -rf /var/lib/apt/lists/*

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
CMD ["/root/docker/startup.sh"]
