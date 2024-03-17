FROM perl:5.38.0-slim

RUN apt-get update \
 && apt-get dist-upgrade -y \
 && apt-get install -y \
    build-essential curl libssl-dev zlib1g-dev openssl \
    libexpat-dev cmake git libcairo-dev libgd-dev \
    unzip wget

# The Perl image is based on Debian, which doesn't have MySQL 8, and the
# current DBD::mysql requires MySQL 8 libraries to build, so we have
# to get the client libraries from mysql.com
RUN gpg --homedir /tmp --no-default-keyring --keyring /usr/share/keyrings/mysql-8.0.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 5072E1F5 \
 && gpg --homedir /tmp --no-default-keyring --keyring /usr/share/keyrings/mysql-8.0.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3A79BD29 \
 && gpg --homedir /tmp --no-default-keyring --keyring /usr/share/keyrings/mysql-8.0.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys B7B3B788A8D3785C \
 && echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/mysql-8.0.gpg] http://repo.mysql.com/apt/debian/ bookworm mysql-8.0' > /etc/apt/sources.list.d/mysql-8.0.list
RUN apt-get update \
 && apt-get install -y libmysqlclient-dev

RUN cpanm --notest --quiet App::cpm Module::CPANfile Carton::Snapshot

WORKDIR /app

COPY Makefile.PL Bugzilla.pm gen-cpanfile.pl /app/
COPY extensions/ /app/extensions/

RUN perl Makefile.PL
RUN make cpanfile

RUN carton install

