#!/bin/bash

exec perl \
    -I$HOME/perl/lib/perl5 \
    -I/vagrant/local/lib/perl5 \
    $HOME/perl/bin/re.pl "$@"
