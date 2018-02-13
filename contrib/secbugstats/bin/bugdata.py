#!/usr/bin/python
#
# Pull some data on an individual bug, e.g. creation_time, resolution, etc.
# from the Bugzilla API
# Usage: ./bugdata <bug_id>

import sys, string, time, re, sys, os, MySQLdb
import simplejson as json
from urllib2 import urlopen
from settings import *

if "--debug" in sys.argv:
  DEBUG = True
else:
  DEBUG = False

# set up database connection
db = MySQLdb.connect(host=DB_HOST, user=DB_USER, passwd=DB_PASS, db=DB_NAME)
db.autocommit(True)
cur = db.cursor()

# list of bug fields we care about
my_bug_fields = ["creation_time"]

# list of history fields we care about
my_history_fields = ["keywords","resolution"]

def bugurl(bug):
    return "https://api-dev.bugzilla.mozilla.org/latest/bug/%d?%s" % (bug, BZ_AUTH)

def histurl(bug):
    return "https://api-dev.bugzilla.mozilla.org/latest/bug/%s/history?%s" % (bug, BZ_AUTH)

# convert API timestamp a MySQL datetime
# d fmt: '2010-06-22T14:56:08Z'
def convertDate(d):
    old = time.strptime(d, "%Y-%m-%dT%H:%M:%SZ")
    return time.strftime("%Y-%m-%d %H:%M:%S", old)

# parse the severity from the keywords text
# e.g. [sg:high][OOPP]
def getSeverity(s):
    if DEBUG: print "getSeverity: ", s
    for keyword in s:
        if re.match("^sec-", keyword):
            sevmatch = re.search("(?<=sec-)[\w]+", keyword)
            if DEBUG: print "--> "+sevmatch.group(0)
            return sevmatch.group(0)
    if DEBUG: print "--> <none>"
    return ""

# get the bug number to process
try:
    BUGID = int(sys.argv[1])
except:
    print "Usage: "+sys.argv[0]+" <bug_id>"
    sys.exit()

# get fields from bug table
if DEBUG: print "Fetching %s" % (bugurl(BUGID))
resp = urlopen( bugurl(BUGID) )
bugobj = json.loads( resp.read() )
# bugobj.keys() == ['cf_blocking_193', 'cf_blocking_192', 'cf_blocking_191',
#                   'attachments', 'classification', 'cc', 'depends_on',
#                   'creation_time', 'is_reporter_accessible', 'keywords',
#                   'summary', 'id', 'cf_status_192', 'severity', 'platform',
#                   'priority', 'cf_status_193', 'cf_status_191', 'version',
#                   'ref', 'status', 'product', 'blocks', 'qa_contact',
#                   'reporter', 'is_everconfirmed', 'component', 'groups',
#                   'target_milestone', 'is_cc_accessible', 'whiteboard',
#                   'last_change_time', 'token', 'flags', 'assigned_to',
#                   'resolution', 'op_sys', 'cf_blocking_fennec']
opendate = convertDate(bugobj["creation_time"])
summary = bugobj["summary"]
# last severity rating in Bugs table (could be blank)
severity = getSeverity(bugobj["keywords"])

# get fields from bug history
resp = urlopen( histurl(BUGID) )
histobj = json.loads( resp.read() )

history = histobj["history"]
# last change to Bugs table
sql = "SELECT updated from secbugs_Bugs where bugid=%s;" % (BUGID)
if DEBUG: print sql
cur.execute(sql)
row = cur.fetchone()
if row:
    updated = str(row[0])
else:
    updated = opendate

# date bug was resolved
closedate = ""

# history is organized in groups of changes
for group in history:
    # group.keys() == ['changes', 'changer', 'change_time']
    # store change time
    change_time = convertDate(group["change_time"])
    for change in group["changes"]:
        # change ex. {'removed': 'unspecified', 'field_name': 'version',
        #             'added': 'Trunk'}
        # skip changes we don't care about
        if change["field_name"] not in my_history_fields:
            continue

        # Look for resolution time
        # e.g. resolution - old: '', new: 'FIXED'
        if change["field_name"] == "resolution":
            if len(change["added"]):
                closedate = change_time
            # bug was reopened
            else:
                closedate = ""

        # NOTE: for items that will change one of the Bugs fields,
        # make sure to check if change_time > secbugs_Bugs.updated and if so
        # update that field with the change time.  Right now, only
        # keywords is doing so...

        # Use most recent sec- keywords marking to determine severity
        elif change["field_name"] == "keywords":
            # keep track of last update to Bugs table
            # e.g. last severity assigned
            #if DEBUG: print "change_time: %s, updated: %s" % (str(change_time), updated)
            if change_time > updated:
                updated = str(change_time)
                severity = getSeverity([change["added"]])

        # default case: log the change to a field we care about
        else:
            sql = "INSERT INTO secbugs_BugHistory VALUES (%s, '%s', '%s', '%s', '%s');" % (BUGID, change_time, db.escape_string(change["field_name"]), db.escape_string(change["added"]), db.escape_string(change["removed"]))
            if DEBUG: print sql
            else: cur.execute(sql)

# check if our bug has a closedate. If not, we may need to set all open bugs'
# "closedate" with the current date so they align right on the chart (maybe not)
if not len(closedate):
    closedate = "0000-00-00 00:00:00"

sql = "INSERT INTO secbugs_Bugs VALUES (%s, '%s', '%s', '%s', '%s', '%s') ON DUPLICATE KEY UPDATE opendate='%s', closedate='%s', severity='%s', summary='%s', updated='%s';" % (BUGID, opendate, closedate, db.escape_string(severity), db.escape_string(summary), updated, opendate, closedate, db.escape_string(severity), db.escape_string(summary), updated)
if DEBUG: print sql
else: cur.execute(sql)
