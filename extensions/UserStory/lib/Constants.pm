# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::UserStory::Constants;

use strict;
use warnings;

use base qw(Exporter);

our @EXPORT = qw( USER_STORY );

use constant USER_STORY => {
    # note - an empty components array means all components
    Loop => {
        group       => 'editbugs',
        components  => [],
    },
    Tracking    => {
        group       => 'editbugs',
        components  => [],
    },
    Firefox => {
        group => 'editbugs',
        components => [
               "Developer Tools",
               "Developer Tools: 3D View",
               "Developer Tools: Canvas Debugger",
               "Developer Tools: Console",
               "Developer Tools: Debugger",
               "Developer Tools: Framework",
               "Developer Tools: Graphic Commandline and Toolbar",
               "Developer Tools: Inspector",
               "Developer Tools: Memory",
               "Developer Tools: Netmonitor",
               "Developer Tools: Object Inspector",
               "Developer Tools: Profiler",
               "Developer Tools: Responsive Mode",
               "Developer Tools: Scratchpad",
               "Developer Tools: Source Editor",
               "Developer Tools: Style Editor",
               "Developer Tools: User Stories",
               "Developer Tools: Web Audio Editor",
               "Developer Tools: WebGL Shader Editor",
               "Developer Tools: WebIDE",
        ],
    },
    'Firefox OS' => {
        group       => 'editbugs',
        components  => [],
    },
    'support.mozilla.org' => {
        group      => 'editbugs',
        components => [],
    }
};

1;
