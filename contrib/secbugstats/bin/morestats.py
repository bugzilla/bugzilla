#!/usr/bin/python
# Process a JSON file yielded by curlbug.py to find out which specific bugs
# are open in each category, what product/component they are open in, and how
# old the various bugs are.
import simplejson, sys, MySQLdb, re
from time import mktime, localtime, strptime
from settings import *

def median(l):
    l.sort()
    if len(l) < 1: return 0
    elif len(l)%2 == 1:
        return l[len(l)/2]
    # even number of elements -> return avg of middle two
    else:
        return float((l[len(l)/2]+l[(len(l)/2)-1])/2)

def average(l):
    l.sort()
    return float(sum(l)/len(l))

try:
    INPUT_FILE = sys.argv[1]
except:
    print "Usage: "+sys.argv[0]+" <input_file>"
    sys.exit()

if "--debug" in sys.argv: DEBUG = True
else: DEBUG = False

# set up database connection
db = MySQLdb.connect(host=DB_HOST, user=DB_USER, passwd=DB_PASS, db=DB_NAME)
db.autocommit(True)
c = db.cursor()

# foreign key to relate these details to the higher-level stat bucket
# enforce filename format, e.g. 200808241200_sg_critical.json
FILE_NAME = INPUT_FILE.split("/")[-1]
p = re.compile("[0-9]{12}[a-z_]+\.json")
if not re.match(p, FILE_NAME):
    print sys.argv[0]+": Unexpected filename format: %s. Exiting." % (FILE_NAME)
    sys.exit()

category = FILE_NAME[13:-5]
date = "%s-%s-%s %s:%s:00" % (FILE_NAME[0:4],FILE_NAME[4:6],FILE_NAME[6:8],
                              FILE_NAME[8:10],FILE_NAME[10:12])

# bail out if we weren't able to determine which stat bucket to associate with
sql = "SELECT sid FROM secbugs_Stats WHERE category='%s' AND date='%s';" % (category,date)
if DEBUG: print sql
c.execute(sql)
row = c.fetchone()
if not row:
    print "%s: unable to determine Stat group for category: %s, date: %s.  Exiting." % \
          (sys.argv[0], category, date)
    sys.exit()
SID = row[0]

# storage for our stat details, we'll key on (product, component)
details = {}

json = open(INPUT_FILE, "rb").read()
buglist = simplejson.loads(json)
for bug in buglist["bugs"]:
    # reset field values
    product = component = bug_id = bug_age = ""
    # gather field values from the JSON object
    product = bug["product"]
    component = bug["component"]
    bug_id = bug["id"]
    # bug age in days
    try:
        bug_age = (mktime(localtime())-mktime(strptime(bug["creation_time"], "%Y-%m-%dT%H:%M:%SZ")))/(60*60*24)
    except Exception, e:
        print "Exception trying to get bug age:", e
        bug_age = 0
    # bail if we don't have other values set
    if not product or not component or not bug_id: continue
    # DEBUG
    if DEBUG:
        print "Processing bug_id: %s, bug_age: %s" % (bug_id, bug_age)
    # create a new list of bugs based on (product, component) and also
    # keep a list of bug ages to generate mean and median age
    if (product, component) not in details.keys():
        details[(product, component)] = [[bug_id], [bug_age]]
    # add to the existing list of bugs and total age of those bugs
    else:
        details[(product, component)][0].append(bug_id)
        details[(product, component)][1].append(bug_age)
    # if DEBUG: print "  bug ages for group: %s" % (details[(product, component)][1])

# store the details we gathered
for pc in details.keys():
    # print pc, len(details[pc]), details[pc]
    # see if we are inserting new details or if we are updating existing details
    sql = "SELECT did FROM secbugs_Details where product='%s' AND component='%s' AND sid=%s AND date='%s';" % (pc[0], pc[1], SID, date)
    c.execute(sql)
    row = c.fetchone()
    # update row
    if row:
        sql = "UPDATE secbugs_Details SET sid=%s, product='%s', component='%s', count=%s, bug_list='%s', date='%s', avg_age_days=%s, med_age_days=%s WHERE did=%s;" % (SID, pc[0], pc[1], len(details[pc][0]), ",".join([str(i) for i in details[pc][0]]), date, int(round(average(details[pc][1]))), int(round(median(details[pc][1]))), row[0])
    # insert new row
    else:
        sql = "INSERT INTO secbugs_Details(sid, product, component, count, bug_list, date, avg_age_days, med_age_days) VALUES(%s, '%s', '%s', %s, '%s', '%s', %s, %s);" % (SID, pc[0], pc[1], len(details[pc][0]), ",".join([str(i) for i in details[pc][0]]), date, int(round(average(details[pc][1]))), int(round(median(details[pc][1]))))
    if DEBUG: print sql
    else: c.execute(sql)
