package Bugzilla::Extension::Splinter;

use strict;

use base qw(Bugzilla::Extension);

use Bugzilla;
use Bugzilla::Bug;
use Bugzilla::Template;
use Bugzilla::Attachment;
use Bugzilla::BugMail;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Field;
use Bugzilla::Util qw(trim detaint_natural);

use Bugzilla::Extension::Splinter::Util;

our $VERSION = '0.1';

BEGIN {
    *Bugzilla::splinter_review_base = \&get_review_base;
    *Bugzilla::splinter_review_url = \&_get_review_url;
}

sub _get_review_url {
    my ($class, $bug_id, $attach_id) = @_;
    return get_review_url(Bugzilla::Bug->check({ id => $bug_id, cache => 1 }), $attach_id);
}

sub page_before_template {
    my ($self, $args) = @_;
    my ($vars, $page) = @$args{qw(vars page_id)};

    if ($page eq 'splinter.html') {
        my $user = Bugzilla->user;

        # We can either provide just a bug id to see a list
        # of prior reviews by the user, or just an attachment
        # id to go directly to a review page for the attachment.
        # If both are give they will be checked later to make
        # sure they are connected.

        my $input = Bugzilla->input_params;
        if ($input->{'bug'}) {
            $vars->{'bug_id'} = $input->{'bug'};
            $vars->{'attach_id'} = $input->{'attachment'};
            $vars->{'bug'} = Bugzilla::Bug->check({ id => $input->{'bug'}, cache => 1 });
        }

        if ($input->{'attachment'}) {
            my $attachment = Bugzilla::Attachment->check({ id => $input->{'attachment'} });

            # Check to see if the user can see the bug this attachment is connected to.
            Bugzilla::Bug->check($attachment->bug_id);
            if ($attachment->isprivate
                && $user->id != $attachment->attacher->id
                && !$user->is_insider)
            {
                ThrowUserError('auth_failure', {action => 'access',
                                                object => 'attachment'});
            }

            # If the user provided both a bug id and an attachment id, they must
            # be connected to each other
            if ($input->{'bug'} && $input->{'bug'} != $attachment->bug_id) {
                ThrowUserError('bug_attach_id_mismatch');
            }

            # The patch is going to be displayed in a HTML page and if the utf8
            # param is enabled, we have to encode attachment data as utf8.
            if (Bugzilla->params->{'utf8'}) {
                $attachment->data;  # load data
                utf8::decode($attachment->{data});
            }

            $vars->{'attach_id'} = $attachment->id;
            $vars->{'attach_data'} = $attachment->data;
            $vars->{'attach_is_crlf'} = $attachment->{data} =~ /\012\015/ ? 1 : 0;
        }

        my $field_object = new Bugzilla::Field({ name => 'attachments.status' });
        my $statuses;
        if ($field_object) {
            $statuses = [map { $_->name } @{ $field_object->legal_values }];
        } else {
            $statuses = [];
        }
        $vars->{'attachment_statuses'} = $statuses;
    }
}


sub bug_format_comment {
    my ($self, $args) = @_;
    
    my $bug = $args->{'bug'};
    my $regexes = $args->{'regexes'};
    my $text = $args->{'text'};
    
    # Add [review] link to the end of "Created attachment" comments
    #
    # We need to work around the way that the hook works, which is intended
    # to avoid overlapping matches, since we *want* an overlapping match
    # here (the normal handling of "Created attachment"), so we add in
    # dummy text and then replace in the regular expression we return from
    # the hook.
    $$text =~ s~((?:^Created\ |\b)attachment\s*\#?\s*(\d+)(\s\[details\])?)
               ~(push(@$regexes, { match => qr/__REVIEW__$2/,
                                   replace => get_review_link("$2", "[review]") })) &&
                (attachment_id_is_patch($2) ? "$1 __REVIEW__$2" : $1)
               ~egmx;
    
    # And linkify "Review of attachment", this is less of a workaround since
    # there is no issue with overlap; note that there is an assumption that
    # there is only one match in the text we are linkifying, since they all
    # get the same link.
    my $REVIEW_RE = qr/Review\s+of\s+attachment\s+(\d+)\s*:/;

    if ($$text =~ $REVIEW_RE) {
        my $attach_id = $1;
        my $review_link = get_review_link($attach_id, "Review");
        my $attach_link = Bugzilla::Template::get_attachment_link($attach_id, "attachment $attach_id");

        push(@$regexes, { match => $REVIEW_RE,
                          replace => "$review_link of $attach_link:"});
    }
}

sub config_add_panels {
    my ($self, $args) = @_;

    my $modules = $args->{panel_modules};
    $modules->{Splinter} = "Bugzilla::Extension::Splinter::Config";
}

sub mailer_before_send {
    my ($self, $args) = @_;
    
    # Post-process bug mail to add review links to bug mail.
    # It would be nice to be able to hook in earlier in the
    # process when the email body is being formatted in the
    # style of the bug-format_comment link for HTML but this
    # is the only hook available as of Bugzilla-3.4.
    add_review_links_to_email($args->{'email'});
}

__PACKAGE__->NAME;
