# Configuration options for secbugstats tools
# This file needs to live next to all the other collection/processing scripts.
# There are also configuration settings in settings.cfg which I didn't combine
# here because Bash and Python read configs differently.

import urllib, sys, pipes, os.path
try:
    import simplejson as json
except ImportError as error:
    if __name__ == '__main__':
        msg = """
            echo 'error in %s:'
            echo '%s' >&2
            exit 1
        """
        print msg % (__file__, pipes.quote(str(error)))
        sys.exit(1)


# scripts location (where does this config file live?)
SCRIPTS_DIR  = os.path.dirname(os.path.abspath(__file__))
BUGZILLA_DIR = os.path.realpath(SCRIPTS_DIR + "/../../..")
DATA_DIR     = BUGZILLA_DIR + "/data"

def read_localconfig():
    lc_cmd  = "%s/scripts/localconfig-as-json" % (BUGZILLA_DIR)
    lc_json = os.popen(pipes.quote(lc_cmd)).read()
    return json.loads( lc_json )

localconfig = read_localconfig()

URLBASE = localconfig['urlbase']
if URLBASE.endswith('/'):
    URLBASE = URLBASE[0:-1]

# database settings
DB_HOST = localconfig['db_host']
DB_USER = localconfig['db_user']
DB_PASS = localconfig['db_pass']
DB_NAME = localconfig['db_name']

# LDAP settings
LDAP_USER = ""
LDAP_PASS = ""

# Email settings
# email address to send the report from
EMAIL_FROM = "secbugstats-noreply@mozilla.com"
# list of email addresses to send the report to
EMAIL_TO   = ['security-group@mozilla.org']
SMTP_HOST = "smtp.mozilla.org"
SMTP_PORT = 25 # 465

# Bugzilla account settings
BZ_APIKEY = ''
try:
    BZ_APIKEY = os.environ['SECBUGSTATS_APIKEY']
except KeyError:
    pass
BZ_AUTH = urllib.urlencode({'api_key': BZ_APIKEY, 'restriclogin': "true"})

# where to store the JSON files that curlbug.py downloads
JSONLOCATION = "%s/secbugstats/json/current" % (DATA_DIR)

# where to store the most recent curlbug.py output
JSON_CUR = JSONLOCATION
# where to store the old curlbug.py output
JSON_OLD = "%s/secbugstats/json" % (DATA_DIR)

# teams chart location
TEAMS_CHART_LOC = "%s/secbugstats/teams" % (DATA_DIR)

# bug lifespan chart location
BUGLIFE_CHART_LOC = "%s/secbugstats/buglife" % (DATA_DIR)

# Selection criteria for various teams based on bug product and component
TEAMS = [["Layout",
          "secbugs_Details.product='Core' AND (secbugs_Details.component LIKE 'layout%' OR secbugs_Details.component LIKE 'print%' OR secbugs_Details.component LIKE 'widget%' OR secbugs_Details.component IN ('CSS Parsing and Computation','Style System (CSS)','SVG','Internationalization','MathML'))"],
         ["Media",
         "secbugs_Details.product='Core' AND (secbugs_Details.component LIKE 'WebRTC%' OR secbugs_Details.component LIKE 'Audio/Video%' OR secbugs_Details.component='Web Audio')"],
         ["JavaScript",
          "secbugs_Details.product='Core' AND (secbugs_Details.component LIKE 'javascript%' OR secbugs_Details.component IN ('Nanojit'))"],
         ["DOM",
          "secbugs_Details.product='Core' AND (secbugs_Details.component LIKE 'DOM%' OR secbugs_Details.component LIKE 'xp toolkit%' OR secbugs_Details.component IN ('Document Navigation','Drag and Drop','Editor','Event Handling','HTML: Form Submission','HTML: Parser','RDF','Security','Security: CAPS','Selection','Serializers','Spelling checker','Web Services','XBL','XForms','XML','XPConnect','XSLT','XUL'))"],
         ["GFX",
          "secbugs_Details.product='Core' AND (secbugs_Details.component LIKE 'GFX%' OR secbugs_Details.component LIKE 'canvas%' OR secbugs_Details.component LIKE 'Graphics%' OR secbugs_Details.component IN ('Graphics','Image: Painting','ImageLib'))"],
         ["Frontend",
          "secbugs_Details.product='Firefox' OR secbugs_Details.product='Firefox for Metro' OR secbugs_Details.product='Toolkit' OR (secbugs_Details.product='Core' AND (secbugs_Details.component IN ('Form Manager','History: Global','Identity','Installer: XPInstall Engine','Security: UI','Keyboard: Navigation')))"],
         ["Networking",
          "secbugs_Details.product='Core' AND secbugs_Details.component like 'Networking%'"],
         ["Mail",
          "secbugs_Details.product='MailNews Core' OR secbugs_Details.product='Thunderbird' OR (secbugs_Details.product='Core' AND (secbugs_Details.component like 'Mail%'))"],
         ["Other",
          "secbugs_Details.product='Core' AND (secbugs_Details.component IN ('DMD','File Handling','General','Geolocation','IPC','Java: OJI','jemalloc','js-ctypes','Memory Allocator','mfbt','mozglue','Permission Manager','Preferences: Backend','String','XPCOM','MFBT','Disability Access APIs','Rewriting and Analysis') OR secbugs_Details.component LIKE 'Embedding%' OR secbugs_Details.component LIKE '(HAL)')"],
         ["Crypto",
          "secbugs_Details.product IN ('JSS','NSS','NSPR') OR (secbugs_Details.product='Core' AND secbugs_Details.component IN ('Security: PSM','Security: S/MIME'))"],
         ["Services",
          "secbugs_Details.product IN ('Cloud Services','Mozilla Services')"],
         ["Plugins",
          "secbugs_Details.product IN ('Plugins','External Software Affecting Firefox') OR (secbugs_Details.product='Core' AND secbugs_Details.component='Plug-ins')"],
         ["Boot2Gecko",
          "secbugs_Details.product='Firefox OS' OR secbugs_Details.product='Boot2Gecko'"],
         ["Mobile",
          "secbugs_Details.product IN ('Fennec Graveyard','Firefox for Android','Android Background Services','Firefox for iOS','Focus')"]]

def main():
    this_module = sys.modules[__name__]

    for k in dir(this_module):
        v = getattr(this_module, k)
        if type(v) == str and not k.startswith("__"):
            print "%s=%s" % (k, pipes.quote(v))

if __name__ == '__main__':
    main()
else:
    import logging
    from logging.config import fileConfig
    fileConfig(SCRIPTS_DIR + '/../logging.ini')