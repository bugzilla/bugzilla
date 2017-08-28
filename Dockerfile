FROM mozillabteam/bmo-slim:20170824.1
MAINTAINER Dylan William Hardison <dylan@mozilla.com>

ENV BUNDLE=https://s3.amazonaws.com/moz-devservices-bmocartons/bmo/vendor.tar.gz
ENV PORT=8000

WORKDIR /app
COPY . .

RUN mv /opt/bmo/local /app && \
    chown -R app:app /app && \
    perl -c /app/scripts/entrypoint.pl

USER app

RUN perl checksetup.pl --no-database --default-localconfig && \
    rm -rf /app/data /app/localconfig && \
    mkdir /app/data

EXPOSE $PORT

ENTRYPOINT ["/app/scripts/entrypoint.pl"]
CMD ["httpd"]
