# Mozilla Security Bug Stats - Collection and Reporting

## Summary

A collection of scripts and CGIs that collects information on Mozilla Security
Bugs, creates web-based charts of the data, and generates a weekly summary
report that is emailed to interested parties.

## Details

A good starting place to read this code is the gather.sh shell script.  This
script is the driver for the remaining collection and processing scripts which
populate the reports and charts.  

- Collection scripts are run once per week as a cron job
- API results
- logging
- Flash charts
- Flot charts


## Required Packages:

* python
* python-mysqldb
* python-matplotlib
