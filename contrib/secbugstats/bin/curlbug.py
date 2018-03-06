#!/usr/bin/python
# Bugzilla API script that queries for the number of open bugs by category, e.g.
# Critical, High, Moderate, Low, as well as some additional tracking categories.
# Saves the JSON results on the filesystem for further processing

import httplib, urllib, urllib2, cookielib, string, time, re, sys, os, MySQLdb, \
    simplejson
from base64 import b64decode
from settings import *
import logging
logger = logging.getLogger()

# set up database connection
db = MySQLdb.connect(host=DB_HOST, user=DB_USER, passwd=DB_PASS, db=DB_NAME)
db.autocommit(True)
c = db.cursor()

if "--debug" in sys.argv:
  # store the json files in /tmp and don't run SQL
  DEBUG = True
  JSONLOCATION = "/tmp"
else:
  DEBUG = False

opener = urllib2.build_opener(urllib2.HTTPCookieProcessor())

def fetchBugzillaPage(path):
    url = "https://api-dev.bugzilla.mozilla.org/latest/bug?%s&%s" % (path, BZ_AUTH)
    if DEBUG: print url
    return opener.open(url).read()

# Queries to run:
# Keys are the category of bugs and values are the query params to send to the
# Bugzilla API.
tocheck = {"sg_critical" : "keywords=sec-critical;keywords_type=allwords;bug_status=UNCONFIRMED;bug_status=NEW;bug_status=ASSIGNED;bug_status=REOPENED;classification=Client%20Software;classification=Components",
           "sg_high" : "keywords=sec-high;keywords_type=allwords;bug_status=UNCONFIRMED;bug_status=NEW;bug_status=ASSIGNED;bug_status=REOPENED;classification=Client%20Software;classification=Components",
           "sg_moderate" : "keywords=sec-moderate;keywords_type=allwords;bug_status=UNCONFIRMED;bug_status=NEW;bug_status=ASSIGNED;bug_status=REOPENED;classification=Client%20Software;classification=Components",
           "sg_low" : "keywords=sec-low;keywords_type=allwords;bug_status=UNCONFIRMED;bug_status=NEW;bug_status=ASSIGNED;bug_status=REOPENED;classification=Client%20Software;classification=Components",
           }

now = time.localtime()
timestamp_file = time.strftime('%Y%m%d%H%M', now)
timestamp_db = time.strftime('%Y-%m-%d %H:%M', now)

# Store the results for further processing (e.g. how many bugs per
# Product/Component?) but first save the number of results for the
# high-level stats.
for key, url in tocheck.items():
    print "Fetching", key
    # will retry Bugzilla queries if they fail
    attempt = 1
    count = None
    while count is None:
        if attempt > 1:
            print "Retrying %s - attempt %d" % (key, attempt)
        json = fetchBugzillaPage(url)
        # save a copy of the bugzilla query
        filename = timestamp_file+"_"+key+".json"
        fp = open(JSONLOCATION+"/"+filename, "w")
        fp.write(json)
        fp.close()
        # log the number of hits each query returned
        results = simplejson.loads(json)
        count = len(results["bugs"])
        attempt += 1
    sql = "INSERT INTO secbugs_Stats(category, count, date) VALUES('%s', %s, '%s');" % \
          (key, count, timestamp_db)
    c.execute(sql)
    logger.debug("sql: %s", sql)
