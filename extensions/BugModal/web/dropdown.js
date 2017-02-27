/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

$(function() {
    'use strict';

    $(window).click(function(e) {
        // clicking dropdown button opens or closes the dropdown content
        if (!$(e.target).hasClass('dropdown-button')) {
            $('.dropdown-button').each(function() {
                toggleDropDown(e, $(this), $('#' + $(this).attr('aria-controls')), 1);
            });
        }
    }).keydown(function(e) {
        // Escape key hides the dropdown if visible
        if (e.keyCode == 27) {
            $('.dropdown-button').each(function() {
                var $button = $(this);
                if ($button.siblings('.dropdown-content').is(':visible')) {
                    toggleDropDown(e, $button, $('#' + $button.attr('aria-controls')), 1);
                    $button.focus();
                }
            });
        }
        // allow arrow up and down keys to choose one of the dropdown items if menu visible
        if (e.keyCode == 38 || e.keyCode == 40) {
            $('.dropdown-content').each(function() {
                var $content = $(this);
                if ($content.is(':visible')) {
                    e.preventDefault();
                    e.stopPropagation();
                    var $li = $content.find('li');
                    // if none focused select the first or last
                    var $any_focused = $content.find('a:focus');
                    if ($any_focused.length == 0) {
                        var index = e.keyCode == 40 ? 0 : $li.length - 1;
                        var $link = $li.eq(index).find('a');
                        $link.addClass('active').focus();
                        return;
                    }
                    // otherwise move up or down the list based on arrow key pressed
                    var inc  = e.keyCode == 40 ? 1 : -1;
                    var move = $content.find('a:focus').parent('li').index() + inc;
                    var $link = $li.eq(move % $li.length).find('a');
                    $content.find('a').removeClass('active');
                    $link.addClass('active').focus();
                }
            });
        }

        // enter clicks on a link
        if (e.keyCode == 13) {
            $('.dropdown-content:visible a.active').trigger('click');
        }
    });

    $('.dropdown-content a').hover(
        function(){ $(this).addClass('active')  },
        function(){ $(this).removeClass('active')  }
    );

    $('.dropdown').each(function() {
        var $div     = $(this);
        var $button  = $div.find('.dropdown-button');
        var $content = $div.find('.dropdown-content');
        $button.click(function(e) {
            toggleDropDown(e, $button, $content);
        }).keydown(function(e) {
            // allow enter to toggle menu
            if (e.keyCode == 13) {
                toggleDropDown(e, $button, $content);
            }
        });
    });

    function toggleDropDown(e, $button, $content, hide_only) {
        // clear all active links
        $content.find('a').removeClass('active');
        if ($content.is(':visible')) {
            $content.hide();
            $button.attr('aria-expanded', false);
        }
        // if not using Escape or clicking outside the dropdown div, then we are hiding
        else if (!hide_only) {
            $content.show();
            $button.attr('aria-expanded', true);
        }
    }
});
