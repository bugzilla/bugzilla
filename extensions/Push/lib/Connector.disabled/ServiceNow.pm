# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connector::ServiceNow;

use strict;
use warnings;

use base 'Bugzilla::Extension::Push::Connector::Base';

use Bugzilla::Attachment;
use Bugzilla::Bug;
use Bugzilla::Component;
use Bugzilla::Constants;
use Bugzilla::Extension::Push::Constants;
use Bugzilla::Extension::Push::Serialise;
use Bugzilla::Extension::Push::Util;
use Bugzilla::Field;
use Bugzilla::Mailer;
use Bugzilla::Product;
use Bugzilla::User;
use Bugzilla::Util qw(trim trick_taint);
use Email::MIME;
use FileHandle;
use LWP;
use MIME::Base64;
use Net::LDAP;

use constant SEND_COMPONENTS => (
    {
        product   => 'mozilla.org',
        component => 'Server Operations: Desktop Issues',
    },
);

sub options {
    return (
        {
            name     => 'bugzilla_user',
            label    => 'Bugzilla Service-Now User',
            type     => 'string',
            default  => 'service.now@bugzilla.tld',
            required => 1,
            validate => sub {
                Bugzilla::User->new({ name => $_[0] })
                    || die "Invalid Bugzilla user ($_[0])\n";
            },
        },
        {
            name     => 'ldap_scheme',
            label    => 'Mozilla LDAP Scheme',
            type     => 'select',
            values   => [ 'LDAP', 'LDAPS' ],
            default  => 'LDAPS',
            required => 1,
        },
        {
            name     => 'ldap_host',
            label    => 'Mozilla LDAP Host',
            type     => 'string',
            default  => '',
            required => 1,
        },
        {
            name     => 'ldap_user',
            label    => 'Mozilla LDAP Bind Username',
            type     => 'string',
            default  => '',
            required => 1,
        },
        {
            name     => 'ldap_pass',
            label    => 'Mozilla LDAP Password',
            type     => 'password',
            default  => '',
            required => 1,
        },
        {
            name     => 'ldap_poll',
            label    => 'Mozilla LDAP Poll Frequency',
            type     => 'string',
            default  => '3',
            required => 1,
            help     => 'minutes',
            validate => sub {
                $_[0] =~ /\D/
                    && die "LDAP Poll Frequency must be an integer\n";
                $_[0]  == 0
                    && die "LDAP Poll Frequency cannot be less than one minute\n";
            },
        },
        {
            name     => 'service_now_url',
            label    => 'Service Now JSON URL',
            type     => 'string',
            default  => 'https://mozilladev.service-now.com',
            required => 1,
            help     => "Must start with https:// and end with ?JSON",
            validate => sub {
                $_[0] =~ m#^https://[^\.\/]+\.service-now\.com\/#
                    || die "Invalid Service Now JSON URL\n";
                $_[0] =~ m#\?JSON$#
                    || die "Invalid Service Now JSON URL (must end with ?JSON)\n";
            },
        },
        {
            name     => 'service_now_user',
            label    => 'Service Now JSON Username',
            type     => 'string',
            default  => '',
            required => 1,
        },
        {
            name     => 'service_now_pass',
            label    => 'Service Now JSON Password',
            type     => 'password',
            default  => '',
            required => 1,
        },
    );
}

sub options_validate {
    my ($self, $config) = @_;
    my $host = $config->{ldap_host};
    trick_taint($host);
    my $scheme = lc($config->{ldap_scheme});
    eval {
        my $ldap = Net::LDAP->new($host, scheme => $scheme, onerror => 'die', timeout => 5)
            or die $!;
        $ldap->bind($config->{ldap_user}, password => $config->{ldap_pass});
    };
    if ($@) {
        die sprintf("Failed to connect to %s://%s/: %s\n", $scheme, $host, $@);
    }
}

my $_instance;

sub init {
    my ($self) = @_;
    $_instance = $self;
}

sub load_config {
    my ($self) = @_;
    $self->SUPER::load_config(@_);
    $self->{bugzilla_user} ||= Bugzilla::User->new({ name => $self->config->{bugzilla_user} });
}

sub should_send {
    my ($self, $message) = @_;

    my $data = $message->payload_decoded;
    my $bug_data = $self->_get_bug_data($data)
        || return 0;

    # we don't want to send the initial comment in a separate message
    # because we inject it into the inital message
    if (exists $data->{comment} && $data->{comment}->{number} == 0) {
        return 0;
    }

    my $target = $data->{event}->{target};
    unless ($target eq 'bug' || $target eq 'comment' || $target eq 'attachment') {
        return 0;
    }

    # ensure the service-now user can see the bug
    if (!$self->{bugzilla_user} || !$self->{bugzilla_user}->is_enabled) {
        return 0;
    }
    $self->{bugzilla_user}->can_see_bug($bug_data->{id})
        || return 0;

    # don't push changes made by the service-now account
    $data->{event}->{user}->{id} == $self->{bugzilla_user}->id
        && return 0;

    # filter based on the component
    my $bug = Bugzilla::Bug->new($bug_data->{id});
    my $send = 0;
    foreach my $rh (SEND_COMPONENTS) {
        if ($bug->product eq $rh->{product} && $bug->component eq $rh->{component}) {
            $send = 1;
            last;
        }
    }
    return $send;
}

sub send {
    my ($self, $message) = @_;
    my $logger = Bugzilla->push_ext->logger;
    my $config = $self->config;

    # should_send intiailises bugzilla_user; make sure we return a useful error message
    if (!$self->{bugzilla_user}) {
        return (PUSH_RESULT_TRANSIENT, "Invalid bugzilla-user (" . $self->config->{bugzilla_user} . ")");
    }

    # load the bug
    my $data = $message->payload_decoded;
    my $bug_data = $self->_get_bug_data($data);
    my $bug = Bugzilla::Bug->new($bug_data->{id});

    if ($message->routing_key eq 'bug.create') {
        # inject the comment into the data for new bugs
        my $comment = shift @{ $bug->comments };
        if ($comment->body ne '') {
            $bug_data->{comment} = Bugzilla::Extension::Push::Serialise->instance->object_to_hash($comment, 1);
        }

    } elsif ($message->routing_key eq 'attachment.create') {
        # inject the attachment payload
        my $attachment = Bugzilla::Attachment->new($data->{attachment}->{id});
        $data->{attachment}->{data} = encode_base64($attachment->data);
    }

    # map bmo login to ldap login and insert into json payload
    $self->_add_ldap_logins($data, {});

    # flatten json data
    $self->_flatten($data);

    # add sysparm_action
    $data->{sysparm_action} = 'insert';

    if ($logger->debugging) {
        $logger->debug(to_json(ref($data) ? $data : from_json($data), 1));
    }

    # send to service-now
    my $request = HTTP::Request->new(POST => $self->config->{service_now_url});
    $request->content_type('application/json');
    $request->content(to_json($data));
    $request->authorization_basic($self->config->{service_now_user}, $self->config->{service_now_pass});

    $self->{lwp} ||= LWP::UserAgent->new(agent => Bugzilla->params->{urlbase});
    my $result = $self->{lwp}->request($request);

    # http level errors
    if (!$result->is_success) {
        # treat these as transient
        return (PUSH_RESULT_TRANSIENT, $result->status_line);
    }

    # empty response
    if (length($result->content) == 0) {
        # malformed request, treat as transient to allow code to fix
        # may also be misconfiguration on servicenow, also transient
        return (PUSH_RESULT_TRANSIENT, "Empty response");
    }

    # json errors
    my $result_data;
    eval {
        $result_data = from_json($result->content);
    };
    if ($@) {
        return (PUSH_RESULT_TRANSIENT, clean_error($@));
    }
    if ($logger->debugging) {
        $logger->debug(to_json($result_data, 1));
    }
    if (exists $result_data->{error}) {
        return (PUSH_RESULT_ERROR, $result_data->{error});
    };

    # malformed/unexpected json response
    if (!exists $result_data->{records}
        || ref($result_data->{records}) ne 'ARRAY'
        || scalar(@{$result_data->{records}}) == 0
    ) {
        return (PUSH_RESULT_ERROR, "Malformed JSON response from ServiceNow: missing or empty 'records' array");
    }

    my $record = $result_data->{records}->[0];
    if (ref($record) ne 'HASH') {
        return (PUSH_RESULT_ERROR, "Malformed JSON response from ServiceNow: 'records' array does not contain an object");
    }

    # sys_id is the unique identifier for this action
    if (!exists $record->{sys_id} || $record->{sys_id} eq '') {
        return (PUSH_RESULT_ERROR, "Malformed JSON response from ServiceNow: 'records object' does not contain a valid sys_id");
    }

    # success
    return (PUSH_RESULT_OK, "sys_id: " . $record->{sys_id});
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

sub _flatten {
    # service-now expects a flat json object
    my ($self, $data) = @_;

    my $target = $data->{event}->{target};

    # delete unnecessary deep objects
    if ($target eq 'comment' || $target eq 'attachment') {
        $data->{$target}->{bug_id} = $data->{$target}->{bug}->{id};
        delete $data->{$target}->{bug};
    }
    delete $data->{event}->{changes};

    $self->_flatten_hash($data, $data, 'u');
}

sub _flatten_hash {
    my ($self, $base_hash, $hash, $prefix) = @_;
    foreach my $key (keys %$hash) {
        if (ref($hash->{$key}) eq 'HASH') {
            $self->_flatten_hash($base_hash, $hash->{$key}, $prefix . "_$key");
        } elsif (ref($hash->{$key}) ne 'ARRAY') {
            $base_hash->{$prefix . "_$key"} = $hash->{$key};
        }
        delete $hash->{$key};
    }
}

sub _add_ldap_logins {
    my ($self, $rh, $cache) = @_;
    if (exists $rh->{login}) {
        my $login = $rh->{login};
        $cache->{$login} ||= $self->_bmo_to_ldap($login);
        Bugzilla->push_ext->logger->debug("BMO($login) --> LDAP(" . $cache->{$login} . ")");
        $rh->{ldap} = $cache->{$login};
    }
    foreach my $key (keys %$rh) {
        next unless ref($rh->{$key}) eq 'HASH';
        $self->_add_ldap_logins($rh->{$key}, $cache);
    }
}

sub _bmo_to_ldap {
    my ($self, $login) = @_;
    my $ldap = $self->_ldap_cache();

    return '' unless $login =~ /\@mozilla\.(?:com|org)$/;

    foreach my $check ($login, canon_email($login)) {
        # check for matching bugmail entry
        foreach my $mail (keys %$ldap) {
            next unless $ldap->{$mail}{bugmail_canon} eq $check;
            return $mail;
        }

        # check for matching mail
        if (exists $ldap->{$check}) {
            return $check;
        }

        # check for matching email alias
        foreach my $mail (sort keys %$ldap) {
            next unless grep { $check eq $_ } @{$ldap->{$mail}{aliases}};
            return $mail;
        }
    }

    return '';
}

sub _ldap_cache {
    my ($self) = @_;
    my $logger = Bugzilla->push_ext->logger;
    my $config = $self->config;

    # cache of all ldap entries; updated infrequently
    if (!$self->{ldap_cache_time} || (time) - $self->{ldap_cache_time} > $config->{ldap_poll} * 60) {
        $logger->debug('refreshing LDAP cache');

        my $cache = {};

        my $host = $config->{ldap_host};
        trick_taint($host);
        my $scheme = lc($config->{ldap_scheme});
        my $ldap = Net::LDAP->new($host, scheme => $scheme, onerror => 'die')
            or die $!;
        $ldap->bind($config->{ldap_user}, password => $config->{ldap_pass});
        foreach my $ldap_base ('o=com,dc=mozilla', 'o=org,dc=mozilla') {
            my $result = $ldap->search(
                base   => $ldap_base,
                scope  => 'sub',
                filter => '(mail=*)',
                attrs  => ['mail', 'bugzillaEmail', 'emailAlias', 'cn', 'employeeType'],
            );
            foreach my $entry ($result->entries) {
                my ($name, $bugMail, $mail, $type) =
                    map { $entry->get_value($_) || '' }
                    qw(cn bugzillaEmail mail employeeType);
                next if $type eq 'DISABLED';
                $mail = lc $mail;
                $bugMail = '' if $bugMail !~ /\@/;
                $bugMail = trim($bugMail);
                if ($bugMail =~ / /) {
                    $bugMail = (grep { /\@/ } split / /, $bugMail)[0];
                }
                $name =~ s/\s+/ /g;
                $cache->{$mail}{name} = trim($name);
                $cache->{$mail}{bugmail} = $bugMail;
                $cache->{$mail}{bugmail_canon} = canon_email($bugMail);
                $cache->{$mail}{aliases} = [];
                foreach my $alias (
                    @{$entry->get_value('emailAlias', asref => 1) || []}
                ) {
                    push @{$cache->{$mail}{aliases}}, canon_email($alias);
                }
            }
        }

        $self->{ldap_cache}      = $cache;
        $self->{ldap_cache_time} = (time);
    }

    return $self->{ldap_cache};
}

1;

