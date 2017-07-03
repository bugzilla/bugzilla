FROM centos:6.7
MAINTAINER Dylan William Hardison <dylan@mozilla.com>

RUN yum update -y && \
    yum install -y perl perl-core mod_perl httpd wget tar openssl mysql-libs gd git && \
    wget -q https://s3.amazonaws.com/moz-devservices-bmocartons/bmo/vendor.tar.gz && \
    tar -C /opt -zxvf /vendor.tar.gz bmo/local/ bmo/LIBS.txt bmo/cpanfile bmo/cpanfile.snapshot && \
    rm /vendor.tar.gz && \
    mkdir /opt/bmo/httpd && \
    ln -s /usr/lib64/httpd/modules /opt/bmo/httpd/modules && \
    mkdir /opt/bmo/httpd/conf && \
    cp {/etc/httpd/conf,/opt/bmo/httpd}/magic && \
    awk '{print $1}' > LIBS.txt \
        | perl -nE 'chomp; unless (-f $_) { $missing++; say $_ } END { exit 1 if $missing }' && \
    useradd -u 10001 -U app -m && \
    curl -L https://cpanmin.us > /usr/local/bin/cpanm && \
    chmod 755 /usr/local/bin/cpanm && \
    mkdir /opt/bmo/build && \
    rpm -qa > /tmp/rpms.list && \
    yum install -y gcc mod_perl-devel && \
    cpanm -l /opt/bmo/build --notest Apache2::SizeLimit && \
    yum erase -y $(rpm -qa | diff -u - /tmp/rpms.list | sed -n '/^-[^-]/ s/^-//p') && \
    rm -rf /opt/bmo/build/lib/perl5/{CPAN,Parse,JSON,ExtUtils} && \
    mkdir /usr/local/share/perl5 && \
    mv /opt/bmo/build/lib/perl5/x86_64-linux-thread-multi/ /usr/local/lib64/perl5/ && \
    mv /opt/bmo/build/lib/perl5/Linux /usr/local/share/perl5/ && \
    rm -vfr /opt/bmo/build && \
    rm /tmp/rpms.list /usr/local/bin/cpanm && \
    yum clean all -y

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
