# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connector::TCL;

use strict;
use warnings;

use base 'Bugzilla::Extension::Push::Connector::Base';

use Bugzilla::Constants;
use Bugzilla::Extension::Push::Constants;
use Bugzilla::Extension::Push::Serialise;
use Bugzilla::Extension::Push::Util;
use Bugzilla::User;

use Digest::MD5 qw(md5_hex);
use File::Temp;

sub options {
    return (
        {
            name     => 'tcl_user',
            label    => 'Bugzilla TCL User',
            type     => 'string',
            default  => 'tcl@bugzilla.tld',
            required => 1,
            validate => sub {
                Bugzilla::User->new({ name => $_[0] })
                    || die "Invalid Bugzilla user ($_[0])\n";
            },
        },
        {
            name     => 'sftp_host',
            label    => 'SFTP Host',
            type     => 'string',
            default  => '',
            required => 1,
        },
        {
            name     => 'sftp_port',
            label    => 'SFTP Port',
            type     => 'string',
            default  => '22',
            required => 1,
            validate => sub {
                $_[0] =~ /\D/ && die "SFTP Port must be an integer\n";
            },
        },
        {
            name     => 'sftp_user',
            label    => 'SFTP Username',
            type     => 'string',
            default  => '',
            required => 1,
        },
        {
            name     => 'sftp_pass',
            label    => 'SFTP Password',
            type     => 'password',
            default  => '',
            required => 1,
        },
        {
            name     => 'sftp_remote_path',
            label    => 'SFTP Remote Path',
            type     => 'string',
            default  => '',
            required => 0,
        },
    );
}

my $_instance;

sub init {
    my ($self) = @_;
    $_instance = $self;
}

sub load_config {
    my ($self) = @_;
    $self->SUPER::load_config(@_);
}

sub should_send {
    my ($self, $message) = @_;

    my $data = $message->payload_decoded;
    my $bug_data = $self->_get_bug_data($data)
        || return 0;

    # sanity check user
    $self->{tcl_user} ||= Bugzilla::User->new({ name => $self->config->{tcl_user} });
    if (!$self->{tcl_user} || !$self->{tcl_user}->is_enabled) {
        return 0;
    }

    # only send bugs created by the tcl user
    unless ($bug_data->{reporter}->{id} == $self->{tcl_user}->id) {
        return 0;
    }

    # don't push changes made by the tcl user
    if ($data->{event}->{user}->{id} == $self->{tcl_user}->id) {
        return 0;
    }

    # send comments
    if ($data->{event}->{routing_key} eq 'comment.create') {
        return 0 if $data->{comment}->{is_private};
        return 1;
    }

    # send status and resolution updates
    foreach my $change (@{ $data->{event}->{changes} }) {
        return 1 if $change->{field} eq 'bug_status' || $change->{field} eq 'resolution';
    }

    # and nothing else
    return 0;
}

sub send {
    my ($self, $message) = @_;
    my $logger = Bugzilla->push_ext->logger;
    my $config = $self->config;

    require XML::Simple;
    require Net::SFTP;

    $self->{tcl_user} ||= Bugzilla::User->new({ name => $self->config->{tcl_user} });
    if (!$self->{tcl_user}) {
        return (PUSH_RESULT_TRANSIENT, "Invalid bugzilla-user (" . $self->config->{tcl_user} . ")");
    }

    # load the bug
    my $data = $message->payload_decoded;
    my $bug_data = $self->_get_bug_data($data);

    # build payload
    my %xml = (
        Mozilla_ID => $bug_data->{id},
        When       => $data->{event}->{time},
        Who        => $data->{event}->{user}->{login},
        Status     => $bug_data->{status}->{name},
        Resolution => $bug_data->{resolution},
    );
    if ($data->{event}->{routing_key} eq 'comment.create') {
        $xml{Comment} = $data->{comment}->{body};
    }

    # convert to xml
    my $xml = XML::Simple::XMLout(
        \%xml,
        NoAttr => 1,
        RootName => 'sync',
        XMLDecl => 1,
    );

    # generate md5
    my $md5 = md5_hex($xml);

    # build filename
    my ($sec, $min, $hour, $day, $mon, $year) = localtime(time);
    my $change_set = $data->{event}->{change_set};
    $change_set =~ s/\.//g;
    my $filename = sprintf(
        '%04s%02d%02d%02d%02d%02d%s',
        $year + 1900,
        $mon + 1,
        $day,
        $hour,
        $min,
        $sec,
        $change_set,
    );

    # create temp files;
    my $temp_dir = File::Temp->newdir();
    my $local_dir = $temp_dir->dirname;
    _write_file("$local_dir/$filename.sync", $xml);
    _write_file("$local_dir/$filename.sync.check", $md5);
    _write_file("$local_dir/$filename.done", '');

    my $remote_dir = $self->config->{sftp_remote_path} eq ''
        ? ''
        : $self->config->{sftp_remote_path} . '/';

    # send files via sftp
    $logger->debug("Connecting to " . $self->config->{sftp_host} . ":" . $self->config->{sftp_port});
    my $sftp = Net::SFTP->new(
        $self->config->{sftp_host},
        ssh_args => {
            port => $self->config->{sftp_port},
        },
        user => $self->config->{sftp_user},
        password => $self->config->{sftp_pass},
    );

    $logger->debug("Uploading $local_dir/$filename.add");
    $sftp->put("$local_dir/$filename.add", "$remote_dir$filename.add")
        or return (PUSH_RESULT_ERROR, "Failed to upload $local_dir/$filename.add");

    $logger->debug("Uploading $local_dir/$filename.add.check");
    $sftp->put("$local_dir/$filename.add.check", "$remote_dir$filename.add.check")
        or return (PUSH_RESULT_ERROR, "Failed to upload $local_dir/$filename.add.check");

    $logger->debug("Uploading $local_dir/$filename.done");
    $sftp->put("$local_dir/$filename.done", "$remote_dir$filename.done")
        or return (PUSH_RESULT_ERROR, "Failed to upload $local_dir/$filename.done");

    # success
    return (PUSH_RESULT_OK, "uploaded $filename.add");
}

sub _get_bug_data {
    my ($self, $data) = @_;
    my $target = $data->{event}->{target};
    if ($target eq 'bug') {
        return $data->{bug};
    } elsif (exists $data->{$target}->{bug}) {
        return $data->{$target}->{bug};
    } else {
        return;
    }
}

sub _write_file {
    my ($filename, $content) = @_;
    open(my $fh, ">$filename") or die "Failed to write to $filename: $!\n";
    print $fh $content;
    close($fh) or die "Failed to write to $filename: $!\n";
}

1;

