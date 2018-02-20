#!/bin/bash
# This is the main "driver" script that calls the other collection and
# processing scripts in the correct order.  This is currently run as a
# weekly cron job but could be run at any frequency.  The output of this
# script should be redirected to a log file for debugging.

# scripts location (where does this config file live?)
# local settings
eval "$(python contrib/secbugstats/bin/settings.py)"

mkdir -p $JSON_CUR
mkdir -p $TEAMS_CHART_LOC
mkdir -p $BUGLIFE_CHART_LOC

# Move last week's data files to the archive
mv $JSON_CUR/* $JSON_OLD/

# Fetch the high-level bug data, e.g. num critical, high, moderate, low
echo "[curlbug.py `date +%Y-%m-%d\ %T`]"
$SCRIPTS_DIR/curlbug.py
echo "[end curlbug.py]"

# Process each JSON file that the preceding script produced to find out
# the product, component, bug numbers, bug ages, etc. for each category
echo "[morestats.py `date +%Y-%m-%d\ %T`]"
for i in `ls $JSON_CUR/*sg_{low,moderate,high,critical,needstriage,unconfirmed,opened,closed,total,untouched,investigate,needinfo,vector}.json`;
do
$SCRIPTS_DIR/morestats.py $i;
done
echo "[end morestats.py]"

# Update our Bug tables for bugs which we're currently working on. These
# are the set of bugs that showed up in any of the queries for Critical,
# High, Moderate and Low.  (We don't need to pull details for bugs that
# haven't changed.)
echo "[updatechanged.py `date +%Y-%m-%d\ %T`]"
$SCRIPTS_DIR/updatechanged.py
echo "[end updatechanged.py]"

# Popluate the data feed for the Teams chart
echo "[teamstats.py `date +%Y-%m-%d\ %T`]"
$SCRIPTS_DIR/teamstats.py > $TEAMS_CHART_LOC/stats.txt
echo "[end teamstats.py]"

# Popluate the data feed for the "Bug Lifetimes" chart
echo "[buglife.py `date +%Y-%m-%d\ %T`]"
$SCRIPTS_DIR/buglife.py > $BUGLIFE_CHART_LOC/stats.txt
echo "[end buglife.py]"

# Draw the PNG chart that we embed in the email report
echo "[teamgraph.py `date +%Y-%m-%d\ %T`]"
$SCRIPTS_DIR/teamgraph.py
echo "[end graph.py]"

# # Email the report
echo "[sendstats.py `date +%Y-%m-%d\ %T`]"
$SCRIPTS_DIR/sendstats.py | perl scripts/sendmail.pl
echo "[end sendstats.py]"
