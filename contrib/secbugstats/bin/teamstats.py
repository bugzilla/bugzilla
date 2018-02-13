#!/usr/bin/python
# aggregate trend data for Eng. teams performance on fixing security bugs
import sys, MySQLdb
from string import join, capitalize, split
from time import mktime
from settings import *

if "--debug" in sys.argv: DEBUG = True
else: DEBUG = False

# set up database connection
db = MySQLdb.connect(host=DB_HOST, user=DB_USER, passwd=DB_PASS, db=DB_NAME)
db.autocommit(True)
c = db.cursor()

def getCleared(curBugs, lastBugs):
    cur = split(curBugs, ",")
    last = split(lastBugs, ",")
    cleared = []
    for bug in last:
        if len(bug) and bug not in cur: cleared.append(bug)
    return cleared

def getAdded(curBugs, lastBugs):
    cur = split(curBugs, ",")
    last = split(lastBugs, ",")
    added = []
    for bug in cur:
        if len(bug) and bug not in last: added.append(bug)
    return added

def cleanCat(cat):
    return cat[3:].capitalize()

# return a UNIX timestamp
def formatDate(d):
    return mktime(d.timetuple())


severities = ["sg_critical", "sg_high", "sg_moderate", "sg_low"]

# print a list of JSON objects
print "{"

for sev in severities:
    print "  '%s': [" % (cleanCat(sev))
    for t in TEAMS:
        # keep track of how many bugs were opened/closed from the last period
        last = { "Critical": "", "High": "", "Moderate": "", "Low": "" }

        # only select from one severity at a time
        sql = "SELECT secbugs_Details.date, sum(secbugs_Details.count), GROUP_CONCAT(secbugs_Details.bug_list), secbugs_Stats.category, round(sum(secbugs_Details.avg_age_days*secbugs_Details.count)/(sum(secbugs_Details.count))) as avg_age_days FROM secbugs_Details INNER JOIN secbugs_Stats ON secbugs_Details.sid=secbugs_Stats.sid WHERE (%s) AND secbugs_Stats.category='%s' GROUP BY date, category ORDER BY date, category;" % (t[1], sev)
        if DEBUG: print "sql:", sql
        c.execute(sql)
        row = c.fetchone()
        while row is not None:
            # how many bugs are new from last period
            new = getAdded(row[2], last[cleanCat(row[3])])
            if DEBUG: print "new:", new
            # how many bugs are closed since last period
            cleared = getCleared(row[2], last[cleanCat(row[3])])
            if DEBUG: print "cleared:", cleared
            # emit data for this (team, date, category)
            print "    { 'date': '%s', 'timestamp': %s, 'team': '%s', 'count': %s, 'new': %s, 'cleared': %s, 'avg_age': %s }," % (str(row[0]), formatDate(row[0]), t[0], row[1], len(new), len(cleared), row[4])
            # remember old values
            last[cleanCat(row[3])] = row[2]
            row = c.fetchone()
    print "  ],"
print "}"
