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
           "sg_total" : "keywords=sec-critical%20sec-high%20sec-moderate%20sec-low;keywords_type=anywords;bug_status=UNCONFIRMED;bug_status=NEW;bug_status=ASSIGNED;bug_status=REOPENED;classification=Client%20Software;classification=Components",
           "sg_unconfirmed" : "bug_status=UNCONFIRMED;field0-0-0=bug_group;type0-0-1=substring;field0-0-1=status_whiteboard;value0-0-2=sec-;classification=Client%20Software;classification=Components;status_whiteboard_type=notregexp;status_whiteboard=sg%3Aneedinfo;field0-0-2=keywords;value0-0-1=[sg%3A;type0-0-0=equals;value0-0-0=core-security;type0-0-2=substring",
           "sg_needstriage" : "type0-1-0=notsubstring;field0-1-0=keywords;field0-0-0=bug_group;status_whiteboard_type=notregexp;value0-1-0=sec-;status_whiteboard=\[sg%3A;bug_status=UNCONFIRMED;bug_status=NEW;bug_status=ASSIGNED;bug_status=REOPENED;type0-0-0=equals;value0-0-0=core-security",
           "sg_investigate" : "status_whiteboard=[sg%3Ainvestigat;status_whiteboard_type=allwordssubstr;bug_status=UNCONFIRMED;bug_status=NEW;bug_status=ASSIGNED;bug_status=REOPENED",
           "sg_vector" : "keywords=sec-vector;keywords_type=allwords;bug_status=UNCONFIRMED;bug_status=NEW;bug_status=ASSIGNED;bug_status=REOPENED;classification=Client%20Software;classification=Components",
           "sg_needinfo" : "status_whiteboard=[sg%3Aneedinfo;status_whiteboard_type=allwordssubstr;bug_status=UNCONFIRMED;bug_status=NEW;bug_status=ASSIGNED;bug_status=REOPENED",
           "sg_untouched" : "keywords=sec-critical%20sec-high%20sec-moderate%20sec-low;keywords_type=anywords;field0-0-0=days_elapsed;classification=Client%20Software;classification=Components;bug_status=UNCONFIRMED;bug_status=NEW;bug_status=ASSIGNED;bug_status=REOPENED;type0-0-0=greaterthan;value0-0-0=14",
           "sg_opened" : "field0-0-0=bug_group;type0-0-1=substring;field0-0-1=status_whiteboard;value0-0-2=sec-;chfield=[Bug%20creation];chfieldfrom=-1w;field0-0-2=keywords;value0-0-1=[sg%3A;type0-0-0=equals;value0-0-0=core-security;type0-0-2=substring;classification=Client%20Software;classification=Components",
            "sg_closed" : "type0-1-0=notsubstring;field0-1-0=keywords;field0-0-0=bug_group;type0-0-1=substring;field0-0-1=status_whiteboard;classification=Client%20Software;classification=Components;value0-0-2=sec-;chfield=resolution;chfieldfrom=-1w;value0-1-0=sec-review;bug_status=RESOLVED;bug_status=VERIFIED;bug_status=CLOSED;field0-0-2=keywords;value0-0-1=[sg%3A;type0-0-0=equals;value0-0-0=core-security;type0-0-2=substring",
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
