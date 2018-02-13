#!/usr/bin/python
# Generate a JSON feed of all the security bug lifespans
# The output is used as the data source for charts/buglife

import sys, MySQLdb, cgi
from string import join, capitalize, split
from time import mktime, strftime
from datetime import datetime
from settings import *

if "--debug" in sys.argv: DEBUG = True
else: DEBUG = False

# set up database connection
db = MySQLdb.connect(host=DB_HOST, user=DB_USER, passwd=DB_PASS, db=DB_NAME)
db.autocommit(True)
cur = db.cursor()

# Bugs sample
# bugid	opendate	closedate	severity	summary	updated
# 286382	2005-03-16 09:41:00	0000-00-00 00:00:00	critical	[Windows] Many insecure uses of LoadLibrary (filename without path)	2010-06-01 20:55:22
# 552002	2010-03-12 18:57:00	0000-00-00 00:00:00	critical	Crash in  [@ nsDOMEvent::QueryInterface(nsID const&, void**) ]	2010-06-01 20:38:05

def cleanCat(cat):
    return cat.capitalize()

# return a UNIX timestamp
# if the date passed in is None then return a timestamp for today rounded
# to the top of the current hour
def formatDate(d):
    if d is None:
        d = datetime(int(strftime("%Y")), int(strftime("%m")), int(strftime("%d")),
                     int(strftime("%H")), 0)
    return mktime(d.timetuple())

# bug severities to include
severities = ["critical", "high", "moderate", "low"]

# display JSON
print "{"

for sev in severities:
    print "  '%s': [" % (cleanCat(sev))
    sql = "SELECT * from secbugs_Bugs WHERE severity='%s' order by opendate;" % (sev)
    cur.execute(sql)
    row = cur.fetchone()
    while row is not None:
        # row e.g. (572428L, datetime.datetime(2010, 6, 16, 16, 6), None, 'critical', 'Crash [@ js_CallGCMarker]', datetime.datetime(2010, 6, 22, 9, 28, 59))
        print "    { 'bugid': %s, 'opendate': %s, 'closedate': %s, 'summary': '%s' }," % \
            (str(row[0]), formatDate(row[1]), formatDate(row[2]), cgi.escape(db.escape_string(row[4])))
        row = cur.fetchone()
    print "  ],"

print "}"
