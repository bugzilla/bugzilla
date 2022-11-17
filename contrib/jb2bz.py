#!/usr/local/bin/python
# -*- mode: python -*-

"""
jb2bz.py - a nonce script to import bugs from JitterBug to Bugzilla
Written by Tom Emerson, tree@basistech.com

This script is provided in the hopes that it will be useful.  No
rights reserved. No guarantees expressed or implied. Use at your own
risk. May be dangerous if swallowed. If it doesn't work for you, don't
blame me. It did what I needed it to do.

This code requires a recent version of Andy Dustman's MySQLdb interface,

    http://sourceforge.net/projects/mysql-python

Share and enjoy.

All servers must use UTC or GMT as their timezone for this script to function properly.

The following items should be configured prior to importing:

a) The assignee variable
b) Any email address mappings desired in the get_real_address function
c) The resolution variable
d) The reporter variable
"""

import email, mimetypes, email.utils
import sys, re, glob, os, stat, time
import MySQLdb, getopt

# mimetypes doesn't include everything we might encounter, yet.
if not mimetypes.types_map.has_key('.doc'):
    mimetypes.types_map['.doc'] = 'application/msword'

if not mimetypes.encodings_map.has_key('.bz2'):
    mimetypes.encodings_map['.bz2'] = "bzip2"

if not mimetypes.types_map.has_key('.log'):
    mimetypes.types_map['.log'] = "text/plain"

mimetypes.types_map['.dif'] = "text/plain"

bug_status='CONFIRMED'
component="default"
version="unspecified"
product="" # this is required, the rest of these are defaulted as above

"""
Each bug in JitterBug is stored as a text file named by the bug number.
Additions to the bug are indicated by suffixes to this:

<bug>
<bug>.followup.*
<bug>.reply.*
<bug>.notes

The dates on the files represent the respective dates they were created/added.

All <bug>s and <bug>.reply.*s include RFC 822 mail headers. These could include
MIME file attachments as well that would need to be extracted.

There are other additions to the file names, such as

<bug>.notify

which are ignored.

Bugs in JitterBug are organized into directories. At Basis we used the following
naming conventions:

<product>-bugs         Open bugs
<product>-requests     Open Feature Requests
<product>-resolved     Bugs/Features marked fixed by engineering, but not verified
<product>-verified     Resolved defects that have been verified by QA

where <product> is either:

<product-name>

or

<product-name>-<version>
"""

def process_notes_file(current, fname):
    try:
        new_note = {}
        notes = open(fname, "r")
        s = os.fstat(notes.fileno())

        new_note['text']  = notes.read()
        new_note['timestamp'] = time.gmtime(s[stat.ST_MTIME])
        new_note['from'] = reporter

        notes.close()

        current['notes'].append(new_note)

    except IOError:
        pass

def process_reply_file(current, fname):
    new_note = {}
    reply = open(fname, "r")
    msg = email.message_from_file(reply)

    # Add any attachments that may have been in a followup or reply
    msgtype = msg.get_content_maintype()
    if msgtype == "multipart":
        for part in msg.walk():
            new_note = {}
            if part.get_filename() is None:
                if part.get_content_type() == "text/plain":
                    new_note['timestamp'] = time.gmtime(email.utils.mktime_tz(email.utils.parsedate_tz(msg['Date'])))
                    new_note['text'] = part.get_payload()
                    if msg['From'] is not None:
                        new_note['from'] = msg['From']
                    else:
                        print "Error: Missing from address"
                        sys.exit(1)
                    current["notes"].append(new_note)
            else:
                maybe_add_attachment(part, current, msg['From'], msg['Date'])
    else:
        new_note['text'] = msg.get_payload()
        new_note['timestamp'] = time.gmtime(email.utils.mktime_tz(email.utils.parsedate_tz(msg['Date'])))
        if msg['From'] is not None:
            new_note['from'] = msg['From']
        else:
            print "Error: Missing from address"
            sys.exit(1)
        current["notes"].append(new_note)

def add_notes(current):
    """Add any notes that have been recorded for the current bug."""
    process_notes_file(current, "%d.notes" % current['number'])

    for f in glob.glob("%d.reply.*" % current['number']):
        process_reply_file(current, f)

    for f in glob.glob("%d.followup.*" % current['number']):
        process_reply_file(current, f)

def maybe_add_attachment(submsg, current, fromaddr, date):
    """Adds the attachment to the current record"""
    attachment_filename = submsg.get_filename()
    if attachment_filename is None:
        return

    if (submsg.get_content_type() == 'application/octet-stream'):
        # try get a more specific content-type for this attachment
        mtype, encoding = mimetypes.guess_type(attachment_filename)
        if mtype == None:
            mtype = submsg.get_content_type()
    else:
        mtype = submsg.get_content_type()

    if mtype == 'application/x-pkcs7-signature':
        return

    if mtype == 'application/pkcs7-signature':
        return

    if mtype == 'application/pgp-signature':
        return

    if mtype == 'message/rfc822':
        return

    if mtype == 'application/ms-tnef':
        return

    if mtype == 'text/x-vcard':
        return

    try:
        data = submsg.get_payload(decode=True)
    except:
        return

    timestamp = time.gmtime(email.utils.mktime_tz(email.utils.parsedate_tz(date)))
    print "Added attachment %s with type %s" % (attachment_filename, mtype, )
    current['attachments'].append( ( attachment_filename, mtype, data, timestamp, fromaddr ) )

def process_text_plain(msg, current):
    current['description'] = msg.get_payload()

def process_multi_part(msg, current):
    for part in msg.walk():
        if part.get_filename() is None:
            process_text_plain(part, current)
        else:
            maybe_add_attachment(part, current, msg['From'], msg['Date'])

"""
  Jitterbugs allows people to submit bugs under any number of email addresses.
  This function allows mapping those addresses into a single BZ instance address.
"""
def get_real_address(addr):
    if addr == 'user2@example.com':
        addr = 'user1@example.com'

    return addr

def add_user(eaddr):
    addr = get_real_address(email.utils.parseaddr(eaddr)[1].lower())

    try:
        mdb = MySQLdb.connect(db='bugs',user='bugs',host='localhost',passwd='passw0rd')
        cursor = mdb.cursor()
        cursor.execute("INSERT INTO profiles SET " \
                       "login_name='%s'," \
                       "disabledtext=''" \
                        % addr )

        cursor.execute("COMMIT")
        cursor.close()
        mdb.close()

    except MySQLdb.IntegrityError, e:
        errorcode = e[0]
        if errorcode == 1062: # duplicate
            cursor.close()
            mdb.close()
            return
        else:
            raise

def get_userid_from_email(eaddr):
    addr = get_real_address(email.utils.parseaddr(eaddr)[1].lower())

    try:
                mdb = MySQLdb.connect(db='bugs',user='bugs',host='localhost',passwd='passw0rd')
                cursor = mdb.cursor()

                cursor.execute("select userid from profiles where login_name='%s'" % addr )
                uid = cursor.fetchone()
                cursor.close()
                mdb.close()
                return uid

    except MySQLdb.ProgrammingError, e:
                print "Error: %d: %s" % (e.args[0],e.args[1])
                sys.exit(1)

def process_jitterbug(filename):
    current = {}
    current['number'] = int(filename)
    current['notes'] = []
    current['attachments'] = []
    current['description'] = ''
    current['date-reported'] = ()
    current['short-description'] = ''

    print "Processing: %d" % current['number']

    mfile = open(filename, "r")
    create_date = os.fstat(mfile.fileno())
    msg = email.message_from_file(mfile)

    current['date-reported'] = time.gmtime(email.utils.mktime_tz(email.utils.parsedate_tz(msg['Date'])))
    if current['date-reported'] is None:
       current['date-reported'] = time.gmtime(create_date[stat.ST_MTIME])

    if current['date-reported'][0] < 1900:
       current['date-reported'] = time.gmtime(create_date[stat.ST_MTIME])

    if msg.has_key('Subject') is not False:
        current['short-description'] = msg['Subject']
    else:
        current['short-description'] = "Unknown"
        print('Setting short description to Unknown')

    if msg['From'] is not None:
        current['from'] = msg['From']
    else:
        print "Error: Missing from address"
        sys.exit(1)

    msgtype = msg.get_content_maintype()
    if msgtype == 'text':
        process_text_plain(msg, current)
    elif msgtype == "multipart":
        process_multi_part(msg, current)
    else:
        # Huh? This should never happen.
        print "Unknown content-type: %s" % msgtype
        sys.exit(1)

    add_notes(current)

    # At this point we have processed the message: we have all of the notes and
    # attachments stored, so it's time to add things to the database.
    # The schema for JitterBug 2.14 can be found at:
    #
    #    http://www.trilobyte.net/barnsons/html/dbschema.html
    #
    # The following fields need to be provided by the user:
    #
    # bug_status
    # product
    # version
    # reporter
    # component
    # resolution
    # assignee

    # change this to the numeric userid of the user who should be the default assignee
    assignee=4

    # the resolution will need to be set manually
    resolution=""

    db = MySQLdb.connect(db='bugs',user='root',host='localhost',passwd='password')
    cursor = db.cursor()

    add_user(current['from'])

    try:
        uid = get_userid_from_email(current['from'])
        cursor.execute( "INSERT INTO bugs SET " \
                        "bug_id=%s," \
                        "priority='---'," \
                        "bug_severity='normal',"  \
                        "op_sys='All'," \
                        "bug_status=%s," \
                        "creation_ts=%s,"  \
                        "delta_ts=%s,"  \
                        "short_desc=%s," \
                        "product_id=%s," \
                        "rep_platform='All'," \
                        "assigned_to=%s," \
                        "reporter=%s," \
                        "version=%s,"  \
                        "component_id=%s,"  \
                        "resolution=%s",
                        [ current['number'],
                          bug_status,
                          time.strftime("%Y-%m-%d %H:%M:%S", current['date-reported'][:9]),
                          time.strftime("%Y-%m-%d %H:%M:%S", current['date-reported'][:9]),
                          current['short-description'],
                          product,
                          assignee,
                          uid,
                          version,
                          component,
                          resolution] )

        # This is the initial long description associated with the bug report
        cursor.execute( "INSERT INTO longdescs SET " \
                        "bug_id=%s," \
                        "who=%s," \
                        "bug_when=%s," \
                        "thetext=%s",
                        [ current['number'],
                          get_userid_from_email(current['from']),
                          time.strftime("%Y-%m-%d %H:%M:%S", current['date-reported'][:9]),
                          current['description'] ] )

        current['fulltext'] = current['description']

        # Add whatever notes are associated with this defect
        for n in current['notes']:
                            add_user(n['from'])
                            cursor.execute( "INSERT INTO longdescs SET " \
                            "bug_id=%s," \
                            "who=%s," \
                            "bug_when=%s," \
                            "thetext=%s",
                            [current['number'],
                             get_userid_from_email(n['from']),
                             time.strftime("%Y-%m-%d %H:%M:%S", n['timestamp'][:9]),
                             n['text']])
                            current['fulltext'] += n['text']

        cursor.execute( "INSERT INTO bugs_fulltext SET " \
        "bug_id=%s," \
        "short_desc=%s," \
        "comments=%s," \
        "comments_noprivate=%s",
        [current['number'],
        current['short-description'],
        current['fulltext'],
        current['fulltext'] ] )

        # add attachments associated with this defect
        for a in current['attachments']:
            cursor.execute( "INSERT INTO attachments SET " \
                            "bug_id=%s, creation_ts=%s, description=%s, mimetype=%s," \
                            "filename=%s, submitter_id=%s",
                            [ current['number'],
                              time.strftime("%Y-%m-%d %H:%M:%S", a[3][:9]),
                              a[0], a[1], a[0], get_userid_from_email(a[4]) ])
            cursor.execute( "INSERT INTO attach_data SET " \
                            "id=LAST_INSERT_ID(), thedata=%s",
                            [ a[2] ])

    except MySQLdb.IntegrityError, message:
        errorcode = message[0]
        if errorcode == 1062: # duplicate
            return
        else:
            raise

    cursor.execute("COMMIT")
    cursor.close()
    db.close()

def usage():
    print """Usage: jb2bz.py [OPTIONS] Product

Where OPTIONS are one or more of the following:

  -h                This help information.
  -s STATUS         One of UNCONFIRMED, CONFIRMED, IN_PROGRESS, RESOLVED, VERIFIED
                    (default is CONFIRMED)
  -c COMPONENT      The component to attach to each bug as it is important. This should be
                    valid component for the Product.
  -v VERSION        Version to assign to these defects.

Product is the Product to assign these defects to.

All of the JitterBugs in the current directory are imported, including replies, notes,
attachments, and similar noise.
"""
    sys.exit(1)


def main():
    global bug_status, component, version, product, reporter
    opts, args = getopt.getopt(sys.argv[1:], "hs:c:v:")
    # Change this to the email address of the Bugzilla user who should be marked
    # as reporting notes
    reporter=""


    for o,a in opts:
        if o == "-s":
            if a in ('UNCONFIRMED','CONFIRMED','IN_PROGRESS','RESOLVED','VERIFIED'):
                bug_status = a
        elif o == '-c':
            component = a
        elif o == '-v':
            version = a
        elif o == '-h':
            usage()

    if len(args) != 1:
        sys.stderr.write("Must specify the Product.\n")
        sys.exit(1)

    product = args[0]

    for bug in filter(lambda x: re.match(r"\d+$", x), glob.glob("*")):
        process_jitterbug(bug)
        

if __name__ == "__main__":
    main()
