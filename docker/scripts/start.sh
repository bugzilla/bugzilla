docker run -d \
    --name dkl_bugzilla_1 \
    --hostname dkl_bugzilla_1 \
    --publish 80:80 \
    --publish 2222:22 \
    --volume /home/dkl/devel:/home/bugzilla/devel \
    --volume /home/dkl/data/bzdev/mysql:/var/lib/mysql \
    dkl_bugzilla
