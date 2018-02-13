#!/usr/bin/python
# Fill the secbugs_Bugs table
# Should not be run regularly as it runs bugdata.py (API script) on every
# bug_id we have stored in the DB.
import sys, MySQLdb, os
from settings import *

if "--debug" in sys.argv:
    DEBUG = True
else:
    DEBUG = False

# set up database connection
db = MySQLdb.connect(host=DB_HOST, user=DB_USER, passwd=DB_PASS, db=DB_NAME)
db.autocommit(True)
cur = db.cursor()

severities = ["sg_critical","sg_high","sg_moderate","sg_low"]

for sev in severities:
    sql = "SELECT d.bug_list FROM secbugs_Details d WHERE d.sid IN (SELECT s.sid FROM secbugs_Stats s WHERE category='%s' and date > '2008-07-01');" % (sev)
    # complete list of bugs for this severity level
    complete = []
    # print "#", sql
    cur.execute(sql)
    row = cur.fetchone()
    while row is not None:
        # row e.g. ('408736,430127',)
        # print "#  ", row
        bugs = row[0].split(",")
        for bug in bugs:
            if len(bug): complete.append(bug)
        row = cur.fetchone()

    unique = list(set(complete))
    print "Going to fetch data for %d %s bugs..." % (len(unique), sev[3:])

    for bug in unique:
        cmd = "%s/bugdata.py %s" % (SCRIPTS_DIR, bug)
        print cmd
        if not DEBUG: os.popen(cmd)
