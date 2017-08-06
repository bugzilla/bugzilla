FROM alpine:3.6 as builder
MAINTAINER Dylan Hardison <dylan@hardison.net>

RUN apk --update add perl curl wget \
    make gcc g++ \
    perl-dev \
    tzdata \
    libevent-dev \
    libc-dev \
    expat-dev \
    libressl-dev \
    libressl \
    mariadb-dev \
    postgresql-dev

RUN curl -s -L https://cpanmin.us > /usr/local/bin/cpanm && \
    chmod 755 /usr/local/bin/cpanm

COPY . /app

WORKDIR /app

RUN perl checksetup.pl --cpanm='all -oracle -auth_radius -auth_ldap'

FROM alpine:3.6

RUN apk --update --no-cache add \
    tzdata \
    curl \
    wget \
    perl \
    make \
    libevent \
    expat \
    libressl \
    mariadb-libs \
    postgresql-libs \
    ca-certificates

WORKDIR /app
COPY --from=builder /app /app
