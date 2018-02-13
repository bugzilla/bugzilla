#!/usr/bin/python
# Create a PNG chart of the historical risk index by team to embed in the
# weekly report
import numpy as NP
import matplotlib, sys, MySQLdb, datetime
matplotlib.use("Agg")
from matplotlib import pyplot as PLT
from matplotlib.patches import Rectangle
from matplotlib.font_manager import FontProperties
from settings import *
import time

# extra debug output
if "--debug" in sys.argv: DEBUG = True
else: DEBUG = False

# set up database connection
try:
    db = MySQLdb.connect(host=DB_HOST, user=DB_USER, passwd=DB_PASS, db=DB_NAME)
    db.autocommit(True)
    c = db.cursor(MySQLdb.cursors.DictCursor)
except:
    print "teamgraph.py: can't connect to database\n"
    sys.exit()

# Keep track of how many bugs of each severity each team has open
teamStats = {}

# Risk scoring rubric: assigns point value to each severity of bug
weights = { "sg_critical": 5,
            "sg_high":     4,
            "sg_moderate": 2,
            "sg_low":      1}

# Gather the risk index for each team at each point in time starting in
# September 2009 (fairly arbitrary choice)
sql = "SELECT DISTINCT date from secbugs_Details WHERE date > '2009-09-01' ORDER BY date;"
c.execute(sql)
rows = c.fetchall()
for row in rows:
    date = row["date"].strftime("%Y-%m-%d")
    for team in TEAMS:
        teamName = team[0]
        # Create the empty list for each team. The list will hold
        # (date, riskScore) tuples
        if teamName not in teamStats.keys():
            teamStats[teamName] = []
        sql2 = "SELECT secbugs_Stats.category, secbugs_Details.date, SUM(secbugs_Details.count) AS total FROM secbugs_Details INNER JOIN secbugs_Stats ON secbugs_Details.sid=secbugs_Stats.sid WHERE secbugs_Details.date LIKE '%s%%' AND secbugs_Stats.category IN ('sg_critical','sg_high','sg_moderate','sg_low') AND (%s) GROUP BY date, category;" % (date, team[1])
        # if DEBUG: print sql2
        # | category    | date                | total |
        # | sg_critical | 2011-08-28 12:00:00 |     3 |
        # | sg_high     | 2011-08-28 12:00:00 |     6 |
        # ...
        c.execute(sql2)
        sevCounts = c.fetchall()
        # Calculate the risk index for this date/team combo
        riskIndex = 0
        for sev in sevCounts:
            riskIndex += weights[sev["category"]] * sev["total"]
        teamStats[teamName].append( (date, riskIndex) )

# Sort list of team stats by most recent risk index
statList = sorted(teamStats.items(), key = lambda k: k[1][-1][1])
# [('Frontend', [('2011-08-07', Decimal('110')), ..., ('2011-08-28', Decimal('102'))]),
#  ('DOM', [('2011-08-07', Decimal('115')), ..., ('2011-08-28', Decimal('127'))])]

# # just create some random data
# fnx = lambda : NP.random.randint(3, 10, 10)
# x = NP.arange(0, 10)
# # [0 1 2 3 4 5 6 7 8 9]
# y1 = fnx()
# # [7 5 7 7 4 3 5 8 7 3]
# y2 = fnx()
# y3 = fnx()

x = [datetime.datetime.strptime(s[0], "%Y-%m-%d") for s in statList[0][1]]
# x = NP.arange(len(statList[0][1]))

series = tuple([[s[1] for s in stat[1]] for stat in
                [team for team in statList]])
# ([0, 4, 4, 4], [6, 6, 6, 6], [22, 22, 17, 12], [13, 17, 17, 17],
# [28, 28, 29, 24], [24, 29, 29, 29], [30, 29, 29, 30], [45, 49, 49,
# 49], [32, 42, 52, 63], [110, 110, 107, 102], [115, 123, 123, 127])


# y_data = NP.row_stack((y1, y2, y3))
# [[7 5 7 7 4 3 5 8 7 3]
#  [6 5 5 5 9 3 8 9 5 8]
#  [3 7 5 4 7 7 3 6 6 4]]
y_data = NP.row_stack(series)

# this call to 'cumsum' (cumulative sum), passing in your y data,
# is necessary to avoid having to manually order the datasets
y_data_stacked = NP.cumsum(y_data, axis=0)
# [[0 4 4 4]
#  [6 10 10 10]
#  [28 32 27 22]
#  [41 49 44 39]
#  [69 77 73 63]
#  [93 106 102 92]
#  [123 135 131 122]
#  [168 184 180 171]
#  [200 226 232 234]
#  [310 336 339 336]
#  [425 459 462 463]]

fig = PLT.figure()
ax1 = fig.add_subplot(111)
# set y-axis to start at 0
PLT.ylim(ymin = 0)

colors = ["#ffe84c", "#7633bd", "#3d853d", "#a23c3c", "#8cacc6",
          "#bd9b33", "#9440ed", "#4da74d", "#cb4b4b", "#afd8f8",
          "#edc240"]

# first one manually? okay...
ax1.fill_between(x, 0, y_data_stacked[0,:], facecolor = colors[0])
# hack for the legend (doesn't work with fill_between)
# http://www.mail-archive.com/matplotlib-users@lists.sourceforge.net/msg10893.html
rects = []
rects.insert(0, Rectangle((0, 0), 1, 1, color = colors[0]))
labels = []
labels.insert(0, statList[0][0])

# fill in the rest
for i in range(1, len(y_data_stacked)):
    ax1.fill_between(x, y_data_stacked[i-1,:], y_data_stacked[i,:],
                     facecolor = colors[i])
    # legend hack: add the Rectangle patch to the plot
    rects.insert(0, Rectangle((0, 0), 1, 1, color = colors[i]))
    labels.insert(0, statList[i][0])

# reduce the number of ticks on the bottom axis to improve readability
fig.autofmt_xdate(bottom = 0.2, rotation = 45, ha = "right")
ax1.set_ylim(ymin = 0)

# reduce width by 10%
box = ax1.get_position()
ax1.set_position([box.x0, box.y0, box.width * 0.9, box.height])
# shrink the font size
fontP = FontProperties()
fontP.set_size("x-small")
ax1.legend(rects, labels, loc='center left', title = "Teams",
           bbox_to_anchor = (1, 0.5), fancybox = True, shadow = False,
           prop = fontP)

# PLT.title("Risk Index: " + x[-1].strftime("%Y-%m-%d"))

# save the image on the filesystem
filename = "teamgraph-%s.png" % time.strftime('%Y%m%d', time.localtime())
fig.savefig("%s/%s" % (JSONLOCATION, filename))
