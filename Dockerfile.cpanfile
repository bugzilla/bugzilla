FROM perl:5.30.0-slim

RUN apt-get update
RUN apt-get install -y \
    build-essential curl libssl-dev zlib1g-dev openssl \
    libexpat-dev cmake git libcairo-dev libgd-dev \
    default-libmysqlclient-dev unzip wget
RUN cpanm --notest --quiet App::cpm Module::CPANfile Carton::Snapshot

WORKDIR /app

COPY Makefile.PL Bugzilla.pm gen-cpanfile.pl /app/
COPY extensions/ /app/extensions/

RUN perl Makefile.PL
RUN make cpanfile

RUN carton install

