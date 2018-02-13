#!/usr/bin/python
#
# For each bug that we see in our queries this week, run our bugdata.py
# script to pull relevant fields, e.g. resolution, whiteboard.
# Takes no arguments (generates bug lists by diff'ing last week's results
# with this week's.

import sys, os, smtplib, time, MySQLdb, operator
from datetime import date, timedelta
from time import strftime
from string import join, split
from settings import *

# extra debug output
if "--debug" in sys.argv: DEBUG = True
else: DEBUG = False

# set up database connection
try:
    db = MySQLdb.connect(host=DB_HOST, user=DB_USER, passwd=DB_PASS, db=DB_NAME)
    db.autocommit(True)
    c = db.cursor(MySQLdb.cursors.DictCursor)
except:
    print "updatechanged.py: can't connect to database\n"
    sys.exit()

def getThisWeekDate(slashed=False):
    sql = "select distinct date from secbugs_Details order by date desc limit 1;"
    c.execute(sql)
    row = c.fetchone()
    if slashed:
        return row["date"].strftime("%m/%d/%y")
    else:
        return row["date"].strftime("%Y-%m-%d")

def getLastWeekDate(slashed=False):
    sql = "select distinct date from secbugs_Details order by date desc limit 1,1;"
    c.execute(sql)
    row = c.fetchone()
    if slashed:
        return row["date"].strftime("%m/%d/%y")
    else:
        return row["date"].strftime("%Y-%m-%d")

def getDelta(n):
    if n > 0:
        return "+"+str(n)
    else:
        return n

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

# simple object to store and sort data from multiple queries
class DataRow():
    def __init__(self):
        self.numCritical = 0
        self.critList = ""
        self.numHigh = 0
        self.highList = ""
        self.numModerate = 0
        self.modList = ""
        self.numLow = 0
        self.lowList = ""
        self.total = 0
        self.product = ""
        self.component = ""
    def dump(self):
        s = "Critical: "+str(self.numCritical)+", "
        s += "High: "+str(self.numHigh)+", "
        s += "Moderate: "+str(self.numModerate)+", "
        s += "Low: "+str(self.numLow)+", "
        return s

# which bugs did we gather stats for this week
for cat in [("sg_critical", "Critical"), ("sg_high", "High"), ("sg_moderate", "Moderate"), ("sg_low", "Low")]:
    print cat[1]
    # get the stats from this week
    sql = "select d.bug_list from secbugs_Details d, secbugs_Stats s where d.sid=s.sid and s.category='%s' and d.date like '%s%%';" % (cat[0], getThisWeekDate())
    c.execute(sql)
    thisWkList = ""
    row = c.fetchone()
    while row != None:
        thisWkList += row["bug_list"] if not len(thisWkList) else ","+row["bug_list"]
        row = c.fetchone()
    # get the stats from last week
    sql = "select d.bug_list from secbugs_Details d, secbugs_Stats s where d.sid=s.sid and s.category='%s' and d.date like '%s%%';" % (cat[0], getLastWeekDate())
    c.execute(sql)
    lastWkList = ""
    row = c.fetchone()
    while row != None:
        lastWkList += row["bug_list"] if not len(lastWkList) else ","+row["bug_list"]
        row = c.fetchone()
    # run bugdata on all the bugs in thisWkList and lastWkList
    unique = set(thisWkList.split(",")+lastWkList.split(","))
    if DEBUG:
        print "thisWk: ", thisWkList
        print "lastWk: ", lastWkList
        print "unique: ", unique
    for bug in unique:
        cmd = "%s/bugdata.py %s" % (SCRIPTS_DIR, bug)
        print cmd
        if not DEBUG: os.popen(cmd)
