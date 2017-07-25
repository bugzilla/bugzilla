FROM mozillabteam/bmo-base:slim
MAINTAINER Dylan William Hardison <dylan@mozilla.com>

RUN wget -q https://s3.amazonaws.com/moz-devservices-bmocartons/bmo/vendor.tar.gz && \
    tar -C /opt -zxf /vendor.tar.gz bmo/local/ bmo/LIBS.txt bmo/cpanfile bmo/cpanfile.snapshot && \
    rm /vendor.tar.gz && \
    mkdir /opt/bmo/httpd && \
    ln -s /usr/lib64/httpd/modules /opt/bmo/httpd/modules && \
    mkdir /opt/bmo/httpd/conf && \
    cp {/etc/httpd/conf,/opt/bmo/httpd}/magic && \
    awk '{print $1}' > LIBS.txt \
        | perl -nE 'chomp; unless (-f $_) { $missing++; say $_ } END { exit 1 if $missing }' && \
    useradd -u 10001 -U app -m

COPY . /app
WORKDIR /app
RUN ln -sv /opt/bmo/local /app/local && \
    chown -R app:app /app && \
    cp /app/docker_files/httpd.conf /opt/bmo/httpd/ && \
    mkdir /opt/bmo/bin && \
    cp /app/docker_files/init.pl /opt/bmo/bin/init.pl

USER app
RUN perl checksetup.pl --no-database --default-localconfig && \
    prove t && \
    rm -rf /app/data && mkdir /app/data

ENV PORT=8000

EXPOSE $PORT

ENTRYPOINT ["/opt/bmo/bin/init.pl"]
CMD ["httpd"]
