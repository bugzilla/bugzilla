#!/usr/bin/env python3
# -*- mode: python -*-

"""
jb2bz.py - a nonce script to import bugs from JitterBug to Bugzilla
Written by Tom Emerson, tree@basistech.com and extended by Ondřej Kuzník,
ondra@mistotebe.net.

This script is provided in the hopes that it will be useful.  No
rights reserved. No guarantees expressed or implied. Use at your own
risk. May be dangerous if swallowed. If it doesn't work for you, don't
blame me. It did what I needed it to do.

This code requires a recent version of psycopg interface:

    https://www.psycopg.org/

Porting back to MySQL or making this backend agnostic is left as an exercise
for the reader.

Share and enjoy.

All servers must use UTC or GMT as their timezone for this script to function
properly
"""

import argparse
from datetime import datetime
import email
import email.utils
import glob
import mimetypes
import os
import os.path
import psycopg2
import pytz
import re
import time

from ast import literal_eval # a safe way of parsing python expressions
from psycopg2.extras import execute_values

# mimetypes doesn't include everything we might encounter, yet.
mimetypes.types_map.setdefault('.doc', 'application/msword')
mimetypes.types_map.setdefault('.log', 'text/plain')
mimetypes.add_type("text/plain", '.dif')

mimetypes.encodings_map.setdefault('.bz2', "bzip2")

IGNORED_MIMETYPES = {
    'application/ms-tnef',
    'application/pgp-signature',
    'application/pkcs7-signature',
    'application/x-pkcs7-signature',
    'message/rfc822',
    'text/x-vcard',
}

"""
Each bug in JitterBug is stored as a text file named by the bug number.
Additions to the bug are indicated by suffixes to this:

<bug>
<bug>.followup.*
<bug>.reply.* (with email taken from <bug>.audit)
<bug>.notes
<bug>.state
<bug>.audit

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

def get_timestamp(t):
    if isinstance(t, str):
        timestamp = email.utils.parsedate_to_datetime(t)
        if timestamp is None:
            return timestamp
        if timestamp.tzinfo is None:
            timestamp = timestamp.replace(tzinfo=options.tzinfo)
        elif abs(timestamp.tzinfo.utcoffset(timestamp)).total_seconds() > 12 * 3600:
            timestamp = timestamp.astimezone(None)
    elif isinstance(t, float):
        timestamp = datetime.fromtimestamp(t, options.tzinfo)
    else:
        raise TypeError('Unkown type %r' % type(t))

    return timestamp


def decode_text_payload(msgpart):
    "Handles base64 encoded payloads which get_payload doesn't by default"

    binary_payload = msgpart.get_payload(decode=True)
    charset = msgpart.get_param('charset', 'ascii')

    try:
        payload = binary_payload.decode(charset, 'replace')
    except LookupError:
        payload = binary_payload.decode('ascii', 'replace')

    return payload


def process_notes_file(current, fname):
    if os.path.isfile(fname):
        with open(fname, 'r') as notes:
            new_note = {}

            s = os.fstat(notes.fileno())
            timestamp = get_timestamp(s.st_mtime)

            text = notes.read()
            for keyword, name in options.keywords:
                if name.lower() in text.lower():
                    current['keywords'].add(keyword)

            new_note['text'] = text
            new_note['timestamp'] = timestamp
            new_note['from'] = options.reporter

            current['notes'].append(new_note)
            if timestamp > current['last_change']:
                current['last_change'] = timestamp


def process_reply_file(current, fname, meta=None):
    new_note = {}
    with open(fname, 'rb') as reply:
        msg = email.message_from_binary_file(reply)

    # Add any attachments that may have been in a followup or reply
    msgtype = msg.get_content_maintype()
    if msgtype == "multipart":
        for part in msg.walk():
            new_note = {}
            if part.get_filename() is None:
                if part.get_content_type() == "text/plain":
                    timestamp = get_timestamp(msg['Date'])
                    new_note['timestamp'] = timestamp
                    if timestamp > current['last_change']:
                        current['last_change'] = timestamp

                    new_note['text'] = decode_text_payload(part)

                    user = meta and meta['from'] or msg['From']
                    if user is not None:
                        new_note['from'] = user
                    else:
                        raise SystemExit("Error: Missing from address")
                    current["notes"].append(new_note)
            else:
                maybe_add_attachment(part, current, msg['From'], msg['Date'])
    else:
        timestamp = get_timestamp(msg['Date'])
        new_note['timestamp'] = timestamp
        if timestamp > current['last_change']:
            current['last_change'] = timestamp

        new_note['text'] = decode_text_payload(msg)

        user = meta and meta['from'] or msg['From']
        if user is not None:
            new_note['from'] = user
        else:
            raise SystemExit("Error: Missing from address")
        current["notes"].append(new_note)


def add_notes(current):
    """Add any notes that have been recorded for the current bug."""
    process_notes_file(current, current['path']+".notes")
    process_audit(current, current["path"]+".audit")

    for f in glob.glob(current["path"]+".reply.*"):
        reply_id = int(f.split('.')[-1])
        meta = current['replies'].get(reply_id)
        current['notes'].remove(meta)
        process_reply_file(current, f, meta)

    for f in glob.glob(current["path"]+".followup.*"):
        process_reply_file(current, f)


def maybe_add_attachment(submsg, current, fromaddr, date):
    """Adds the attachment to the current record"""

    attachment_filename = submsg.get_filename()
    if attachment_filename is None:
        return

    if (submsg.get_content_type() == 'application/octet-stream'):
        # try get a more specific content-type for this attachment
        mtype, encoding = mimetypes.guess_type(attachment_filename)
        if not mtype:
            mtype = submsg.get_content_type()
    else:
        mtype = submsg.get_content_type()

    if mtype in IGNORED_MIMETYPES:
        return

    try:
        data = submsg.get_payload(decode=True)
    except:
        print("Failed to decode payload for bug", current['path'])
        return

    timestamp = get_timestamp(date)
    if timestamp > current['last_change']:
        current['last_change'] = timestamp

    print("Added attachment %s with type %s" % (attachment_filename, mtype))
    current['attachments'].append((attachment_filename, mtype, data, timestamp, fromaddr))


def process_text_plain(msg, current):
    current['description'] = decode_text_payload(msg)


def process_multi_part(msg, current):
    for part in msg.walk():
        if part.get_filename() is None:
            if part.get_content_type() == "text/plain":
                process_text_plain(part, current)
        else:
            maybe_add_attachment(part, current, msg['From'], msg['Date'])


def process_state(current, fname):
    if os.path.isfile(fname):
        try:
            with open(fname, 'r') as state:
                bug_state = int(state.read())

            if bug_state == 0:
                current['bug_status'] = 'VERIFIED'

            if bug_state == 1:
                current['bug_status'] = 'UNCONFIRMED'

            if bug_state == 2:
                current['bug_status'] = 'RESOLVED'
                current['resolution'] = 'SUSPENDED'

            if bug_state == 3:
                current['bug_status'] = 'RESOLVED'
                current['resolution'] = 'FEEDBACK'

            if bug_state == 4:
                current['bug_status'] = 'RESOLVED'
                current['resolution'] = 'TEST'

            if bug_state == 5:
                current['bug_status'] = 'RESOLVED'

            if bug_state == 6:
                current['bug_status'] = 'IN_PROGRESS'

            if bug_state == 7:
                current['bug_status'] = 'RESOLVED'
                current['resolution'] = 'PARTIAL'

        except IOError:
            current['bug_status'] = 'UNCONFIRMED'

    else:
        current['bug_status'] = 'UNCONFIRMED'


def process_audit(current, fname):
    if os.path.isfile(fname):
        with open(fname, 'r') as f:
            new_note = None
            for line in f:
                line = line.strip()
                if not line:
                    continue

                date, user, note = line.split('\t')
                timestamp = get_timestamp(date)

                if timestamp > current['last_change']:
                    current['last_change'] = timestamp

                if new_note and timestamp == new_note['timestamp'] \
                        and new_note['from'] == user:
                    new_note['text'] += '\n' + note
                    continue

                if new_note:
                    current['notes'].append(new_note)
                new_note = {
                    'timestamp': timestamp,
                    'from': user,
                    'text': note,
                }

                if note.startswith("sent reply "):
                    current['replies'][int(note.split()[-1])] = new_note

            if new_note:
                current['notes'].append(new_note)


def get_real_address(addr):
    addr = addr.strip()
    if not addr:
        raise ValueError

    if '@' not in addr:
        addr += '@' + options.domain
    addr = addr.lower()

    return options.mapping.get(addr, addr)


def get_userid(eaddr):
    try:
        name, addr = email.utils.parseaddr(eaddr)
    except TypeError:
        name, addr = email.utils.parseaddr(str(eaddr))
    addr = get_real_address(addr)
    if not name:
        name = addr

    with conn.cursor() as cursor:
        if options.bz_version == (5, 1):
            cursor.execute("select userid from profiles where email=%s",
                           [addr])
            for uid in cursor:
                return uid

            cursor.execute("INSERT INTO profiles (login_name, email, realname) "
                           "VALUES %s RETURNING userid",
                           [(addr, addr, name)])
            return cursor.fetchone()
        else:
            cursor.execute("select userid from profiles where login_name=%s",
                           [addr])
            for uid in cursor:
                return uid

            cursor.execute("INSERT INTO profiles (login_name, realname) "
                           "VALUES %s RETURNING userid",
                           [(addr, name)])
            return cursor.fetchone()


def process_jitterbug(filename):
    current = {}
    current['path'] = filename
    current['number'] = int(os.path.basename(filename))
    current['notes'] = []
    current['attachments'] = []
    current['description'] = ''
    current['date-reported'] = ()
    current['short-description'] = ''
    current['bug_status'] = ''
    current['resolution'] = ''
    current['keywords'] = set()
    current['private'] = os.path.isfile(filename+'.private')
    current['replies'] = {}

    cursor = conn.cursor()

    cursor.execute('select bug_id from bugs where bug_id = %s', [current['number']])
    if cursor.fetchall():
        print("Bug", current['number'], "exists")
        return

    with open(filename, 'rb') as mfile:
        create_date = os.fstat(mfile.fileno())
        process_state(current, filename+".state")
        msg = email.message_from_binary_file(mfile)

    timestamp = get_timestamp(msg['Date'])
    if timestamp is None or timestamp.year < 1900:
        current['date-reported'] = get_timestamp(create_date.st_mtime)

    current['last_change'] = current['date-reported'] = timestamp

    if 'Subject' in msg:
        current['short-description'] = str(msg['Subject'])
    else:
        current['short-description'] = "Unknown"
        print('Setting short description to Unknown')

    if msg['From']:
        current['from'] = msg['From']
    else:
        raise SystemExit("Error: Missing from address")

    msgtype = msg.get_content_maintype()
    if msgtype == 'text':
        process_text_plain(msg, current)
    elif msgtype == "multipart":
        process_multi_part(msg, current)
    else:
        # Huh? This should never happen.
        raise SystemExit("Unknown content-type: %s" % msgtype)

    # set reported version
    desc_lines = current['description'].split('\n')
    version_line = desc_lines and len(desc_lines) > 1 and desc_lines[1]
    if version_line and version_line.startswith('Version:'):
        version = version_line[8:].strip()
        cursor.execute("select value from versions where value = %s and product_id = %s",
                       [version, options.product_id])
        result = cursor.fetchall()
        current['version'] = result[0][0] if result else options.version
    else:
        current['version'] = options.version

    add_notes(current)

    # At this point we have processed the message: we have all of the notes and
    # attachments stored, so it's time to add things to the database.
    # The schema for JitterBug 2.14 can be found at:
    #
    #    http://www.trilobyte.net/barnsons/html/dbschema.html
    #
    # The following fields need to be provided by the user:
    #
    # product
    # version
    # reporter
    # component
    # resolution
    # assignee

    if current['bug_status'] == 'RESOLVED':
        if current['resolution'] == '':
            current['resolution'] = 'FIXED'

    if current['bug_status'] == 'VERIFIED':
        current['resolution'] = 'FIXED'

    uid = get_userid(current['from'])

    try:
        if not current['private']:
            for prefix in ('SECURITY:', 'PRIVATE:'):
                if current['short-description'].startswith(prefix):
                    current['short-description'] = current['short-description'][len(prefix):].strip()

        cursor.execute(
            "INSERT INTO bugs "
            "(bug_id, assigned_to, bug_severity, bug_status, creation_ts, "
            "delta_ts, lastdiffed, short_desc, op_sys, priority, product_id, "
            "rep_platform, reporter, version, component_id, resolution, "
            "everconfirmed) VALUES %s",
            [(current['number'], options.assignee, 'normal', current['bug_status'], current['date-reported'],
              current['last_change'], current['last_change'], current['short-description'], 'All', '---', options.product_id,
              'All', uid, current['version'], options.component_id, current['resolution'],
              0 if current['bug_status'] == 'UNCONFIRMED' else 1)]
        )

        # Set keywords
        if current['keywords']:
            execute_values(
                cursor,
                "INSERT INTO keywords "
                "VALUES %s",
                [(current['number'], keyword) for keyword in current['keywords']]
            )

        # if private, assign to group immediately
        if current['private']:
            cursor.execute(
                "INSERT INTO bug_group_map "
                "(bug_id, group_id) VALUES %s",
                [(current['number'], options.group_id)]
            )

        # This is the initial long description associated with the bug report
        cursor.execute(
            "INSERT INTO longdescs "
            "(bug_id, who, bug_when, thetext, isprivate) "
            "VALUES %s",
            [(current['number'], uid, current['date-reported'], current['description'], int(current['private']))]
        )

        if current['private']:
            current['fulltext'] = ''
        else:
            current['fulltext'] = current['description']
        current['fulltext_private'] = current['description']

        # Add whatever notes are associated with this defect
        for n in sorted(current['notes'], key=lambda x: x['timestamp']):
            note_userid = get_userid(n['from'])
            cursor.execute(
                "INSERT INTO longdescs "
                "(bug_id, who, bug_when, thetext, isprivate) "
                "VALUES %s",
                [(current['number'], note_userid, n['timestamp'], n['text'], int(current['private']))]
            )
            if not current['private']:
                current['fulltext'] += n['text']
            current['fulltext_private'] += n['text']

        cursor.execute(
            "INSERT INTO bugs_fulltext "
            "(bug_id, short_desc, comments, comments_noprivate) "
            "VALUES %s",
            [(current['number'], current['short-description'],
              current['fulltext_private'], current['fulltext'])]
        )

        # add attachments associated with this defect
        for a in current['attachments']:
            ispatch = a[1] in ('text/x-diff', 'text/x-patch')
            cursor.execute(
                "INSERT INTO attachments "
                "(bug_id, creation_ts, modification_time, description, "
                "mimetype, ispatch, filename, submitter_id) "
                "VALUES %s RETURNING attach_id",
                [(current['number'], a[3], a[3], a[0],
                  a[1], int(ispatch), a[0], get_userid(a[4]))]
            )
            insert_id = cursor.fetchone()
            cursor.execute(
                "INSERT INTO attach_data "
                "(id, thedata) VALUES %s",
                [(insert_id, a[2])]
            )

    except psycopg2.IntegrityError as message:
        print(message)
        raise

    conn.commit()


def usage():
    raise SystemExit("""Usage: jb2bz.py [OPTIONS] Product

Where OPTIONS are one or more of the following:

  -h                This help information.
  -c COMPONENT      The component to attach to each bug as it is important.
                    This should be valid component for the Product.
  -v VERSION        Version to assign to these defects.

Product is the Product to assign these defects to.

All of the JitterBugs in the current directory are imported, including replies,
notes, attachments, and similar noise.
""")


def main():
    global conn, options

    parser = argparse.ArgumentParser()

    parser.add_argument('-a', '--assignee', required=True,
                        help='Email of the default assignee')
    parser.add_argument('-r', '--reporter', required=True,
                        help='Email of user who should be marked as reporting notes')
    parser.add_argument('-g', '--group', required=True,
                        help='Group to assign private tickets to')
    parser.add_argument('-d', '--domain', required=True,
                        help='Domain for internal users')

    parser.add_argument('-p', '--product', required=True,
                        help='Product to assign these defects to.')
    parser.add_argument('-c', '--component',
                        help='The component to attach to each bug, required if there are more than one component on the product')
    parser.add_argument('-v', '--version', default='unspecified',
                        help='Version to assign to these defects.')

    parser.add_argument('--email-mapping', type=argparse.FileType('r'),
                        help='Email address mapping file (should contain a Python dict)')
    parser.add_argument('-z', '--timezone', default=time.localtime().tm_zone,
                        help='Server timezone')
    parser.add_argument('--bugzilla-version', default='5.2',
                        help='Bugzilla version')

    parser.add_argument('directory', nargs='+',
                        help='List of directories with bugs to import')

    options = parser.parse_args()
    options.tzinfo = pytz.timezone(options.timezone)
    options.bz_version = options.bugzilla_version.split('.')
    options.mapping = {}
    if options.email_mapping:
        options.mapping = literal_eval(options.email_mapping.read())

    conn = psycopg2.connect(database='bugs', user='bugs')

    # change this to the numeric userid of the user who should be the default
    # assignee
    options.assignee = get_userid(options.assignee)

    with conn.cursor() as cursor:
        cursor.execute('select id from products where name = %s',
                       [options.product])
        products = cursor.fetchall()
        if not products:
            raise SystemExit("No product found: %r" % options.product)
        options.product_id = products[0][0]

        if options.component:
            cursor.execute(
                'SELECT id from components where name = %s and product_id = %s',
                (options.component, options.product_id))
            components = cursor.fetchall()
            if not components:
                raise SystemExit("No such component in product %r: %r" %
                                 [options.product, options.component])
        else:
            cursor.execute(
                'SELECT id, name from components where product_id = %s',
                (options.product_id))
            components = cursor.fetchall()
            if len(components) != 1:
                raise SystemExit("Cannot pick default component in product %r: need to choose from %r" %
                                 [options.product, [item[1] for item in components]])

        options.component_id = components[0][0]

        cursor.execute('select id from groups where name = %s',
                       [options.group])
        groups = cursor.fetchall()
        if not groups:
            raise SystemExit("No group found: %r" % options.group)
        options.group_id = groups[0][0]

        cursor.execute('select id, name from keyworddefs')
        options.keywords = cursor.fetchall()

    # Bug entries are just a number, other files are ancillary
    for directory in options.directory:
        dir_fd = os.open(directory, os.O_RDONLY)
        total = len([name for name in os.listdir(dir_fd) if name.isdigit()])
        index = 0
        for name in os.listdir(dir_fd):
            if not name.isdigit():
                continue

            index += 1
            print("[%d/%d]" % (index, total), "Processing", name, "in directory", directory)
            with conn:
                process_jitterbug(os.path.join(directory, name))

    with conn.cursor() as cursor:
        cursor.execute("SELECT setval('bugs_bug_id_seq', (select max(bug_id) from bugs), true)")
    conn.commit()
    conn.close()


if __name__ == "__main__":
    main()
