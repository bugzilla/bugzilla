FROM mozillabteam/bmo-slim:20171228.1

ARG CI
ARG CIRCLE_SHA1
ARG CIRCLE_BUILD_URL

ENV CI=${CI}
ENV CIRCLE_BUILD_URL=${CIRCLE_BUILD_URL}
ENV CIRCLE_SHA1=${CIRCLE_SHA1}

ENV HTTPD_StartServers=8
ENV HTTPD_MinSpareServers=5
ENV HTTPD_MaxSpareServers=20
ENV HTTPD_ServerLimit=256
ENV HTTPD_MaxClients=256
ENV HTTPD_MaxRequestsPerChild=4000
ENV PORT=8000

WORKDIR /app
COPY . .

RUN mv /opt/bmo/local /app && \
    chown -R app:app /app && \
    perl -c /app/scripts/entrypoint.pl && \
    setcap 'cap_net_bind_service=+ep' /usr/sbin/httpd

USER app

RUN perl checksetup.pl --no-database --default-localconfig && \
    rm -rf /app/data /app/localconfig && \
    mkdir /app/data

EXPOSE $PORT

ENTRYPOINT ["/app/scripts/entrypoint.pl"]
CMD ["httpd"]
