/*
 * this is a port of perl's Time::Duration module, which has the following
 * license:
 *
 * Copyright 2006, Sean M. Burke C<sburke@cpan.org>, all rights reserved.  This
 * program is free software; you can redistribute it and/or modify it under the
 * same terms as Perl itself.
 *
 * This program is distributed in the hope that it will be useful, but without
 * any warranty; without even the implied warranty of merchantability or
 * fitness for a particular purpose.
 */

$(function() {
    'use strict';

    function separate(seconds) {
        // breakdown of seconds into units, starting with the most significant

        var remainder = seconds;
        var tmp;
        var wheel = [];

        // years
        tmp = Math.floor(remainder / (365 * 24 * 60 * 60));
        wheel.push([ 'year', tmp, 1000000000 ]);
        remainder -= tmp * (365 * 24 * 60 * 60);

        // days
        tmp = Math.floor(remainder / (24 * 60 * 60));
        wheel.push([ 'day', tmp, 365 ]);
        remainder -= tmp * (24 * 60 * 60);

        // hours
        tmp = Math.floor(remainder / (60 * 60));
        wheel.push([ 'hour', tmp, 24 ]);
        remainder -= tmp * (60 * 60);

        // minutes
        tmp = Math.floor(remainder / 60);
        wheel.push([ 'minute', tmp, 60 ]);
        remainder -= tmp * 60;

        // seconds
        wheel.push([ 'second', Math.floor(remainder), 60 ]);
        return wheel;
    }

    function approximate(precision, wheel) {
        // now nudge the wheels into an acceptably (im)precise configuration
        FIX: do {
            // constraints for leaving this block:
            //  1) number of nonzero wheels must be <= precision
            //  2) no wheels can be improperly expressed (like having "60" for mins)

            var nonzero_count = 0;
            var improperly_expressed = -1;

            for (var i = 0; i < wheel.length; i++) {
                var tmp = wheel[i];
                if (tmp[1] == 0) {
                    continue;
                }
                ++nonzero_count;
                if (i == 0) {
                    // the years wheel is never improper or over any limit; skip
                    continue;
                }

                if (nonzero_count > precision) {
                    // this is one nonzero wheel too many

                    // incr previous wheel if we're big enough
                    if (tmp[1] >= (tmp[tmp.length - 1] / 2)) {
                        ++wheel[i - 1][1];
                    }

                    // reset this and subsequent wheels to 0
                    for (var j = i; j < wheel.length; j++) {
                        wheel[j][1] = 0;
                    }

                    // start over
                    continue FIX;

                } else if (tmp[1] >= tmp[tmp.length - 1]) {
                    // it's an improperly expressed wheel (like "60" on the mins wheel)
                    improperly_expressed = i;
                }
            }

            if (improperly_expressed != -1) {
                // only fix the least-significant improperly expressed wheel (at a time)
                ++wheel[improperly_expressed - 1][1];
                wheel[improperly_expressed][1] = 0;

                // start over
                continue FIX;
            }

            // otherwise there's not too many nonzero wheels, and there's no
            //improperly expressed wheels, so fall thru...
        } while(0);

        return wheel;
    }

    function render(wheel) {
        var parts = [];
        wheel.forEach(function(element, index) {
            if (element[1] > 0) {
                parts.push(element[1] + ' ' + element[0]);
                if (element[1] != 1) {
                    parts[parts.length - 1] += 's';
                }
            }
        });

        if (parts.length == 0) {
            return "just now";
        }
        parts[parts.length - 1] += ' ago';
        if (parts.length == 1) {
            return parts[0];
        }
        if (parts.length == 2) {
            return parts[0] + ' and ' + parts[1];
        }
        parts[parts.length - 1] = 'and ' + parts[parts.length - 1];
        return parts.join(', ');
    }

    window.setInterval(function() {
        var now = Math.floor(new Date().getTime() / 1000);
        $('.rel-time').each(function() {
            $(this).text(render(approximate(2, separate(now - $(this).data('time')))));
        });
        $('.rel-time-title').each(function() {
            $(this).attr('title', render(approximate(2, separate(now - $(this).data('time')))));
        });
    }, 60000);
});
