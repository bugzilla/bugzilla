FROM mozillabteam/bmo-slim:20181011.1

ARG CI
ARG CIRCLE_SHA1
ARG CIRCLE_BUILD_URL

ENV CI=${CI}
ENV CIRCLE_BUILD_URL=${CIRCLE_BUILD_URL}
ENV CIRCLE_SHA1=${CIRCLE_SHA1}

ENV LOG4PERL_CONFIG_FILE=log4perl-json.conf

ENV PORT=8000

# we run a loopback logging server on this TCP port.
ENV LOGGING_PORT=5880

WORKDIR /app
COPY . .

RUN mv /opt/bmo/local /app && \
    chown -R app:app /app && \
    perl -I/app -I/app/local/lib/perl5 -c -E 'use Bugzilla; BEGIN { Bugzilla->extensions }' && \
    perl -c /app/scripts/entrypoint.pl && \
    setcap 'cap_net_bind_service=+ep' /usr/bin/perl && \
    for file in patches/*.patch; do \
        patch -p0 < $file; \
    done

USER app

RUN perl checksetup.pl --no-database --default-localconfig && \
    rm -rf /app/data /app/localconfig && \
    mkdir /app/data

EXPOSE $PORT

ENTRYPOINT ["/app/scripts/entrypoint.pl"]
CMD ["httpd"]
