# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Support::Systemexec;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(system exec);
@EXPORT_OK = qw();
sub system($$@) {
  1;
}
sub exec($$@) {
  1;
}
1;
