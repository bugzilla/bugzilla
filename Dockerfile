FROM bugzilla/bugzilla-perl-slim:20240316.1

ENV DEBIAN_FRONTEND noninteractive

ARG CI
ARG CIRCLE_SHA1
ARG CIRCLE_BUILD_URL

ENV CI=${CI}
ENV CIRCLE_BUILD_URL=${CIRCLE_BUILD_URL}
ENV CIRCLE_SHA1=${CIRCLE_SHA1}

ENV LOG4PERL_CONFIG_FILE=log4perl-json.conf

RUN apt-get install -y rsync

# we run a loopback logging server on this TCP port.
ENV LOGGING_PORT=5880

ENV LOCALCONFIG_ENV=1

WORKDIR /app

COPY . /app

RUN chown -R app:app /app && \
    perl -I/app -I/app/local/lib/perl5 -c -E 'use Bugzilla; BEGIN { Bugzilla->extensions }' && \
    perl -c /app/scripts/entrypoint.pl

USER app

RUN perl checksetup.pl --no-database --default-localconfig && \
    rm -rf /app/data /app/localconfig && \
    mkdir /app/data

EXPOSE 8000

ENTRYPOINT ["/app/scripts/entrypoint.pl"]
CMD ["httpd"]
