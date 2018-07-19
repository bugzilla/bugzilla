/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

$(function() {
    'use strict';

    $(window).click(function(e) {
        // Do not handle non-primary click.
        if (e.button != 0) {
            return;
        }
        // clicking dropdown button opens or closes the dropdown content
        if (!$(e.target).hasClass('dropdown-button')) {
            $('.dropdown-button').each(function() {
                toggleDropDown(e, $(this), $('#' + $(this).attr('aria-controls')), false, true);
            });
        }
    }).keydown(function(e) {
        // Escape key hides the dropdown if visible
        if (e.keyCode == 27) {
            $('.dropdown-button').each(function() {
                var $button = $(this);
                if ($button.siblings('.dropdown-content').is(':visible')) {
                    toggleDropDown(e, $button, $('#' + $button.attr('aria-controls')), false, true);
                    $button.focus();
                }
            });
        }
        // allow arrow up and down keys to choose one of the dropdown items if menu visible
        if (e.keyCode == 38 || e.keyCode == 40) {
            $('.dropdown-content').each(function() {
                var $content = $(this);
                var content_id = $content.attr('id');
                var $controller = content_id ? $('[aria-controls="' + content_id + '"]') : $();
                if ($content.is(':visible')) {
                    e.preventDefault();
                    e.stopPropagation();
                    var $items = $content.find('[role="menuitem"], [role="option"]');
                    // if none active select the first or last
                    var $link = $items.filter('.active');
                    if ($link.length == 0) {
                        var index = e.keyCode == 40 ? 0 : $items.length - 1;
                        $link = $items.eq(index);
                    } else {
                        // otherwise move up or down the list based on arrow key pressed
                        var move = $items.index($link) + (e.keyCode == 40 ? 1 : -1);

                        // remove active state first
                        if ($link.length) {
                            $link.removeClass('active');

                            if ($link.attr('id') === content_id + '-active-item') {
                                $link.removeAttr('id');
                            }
                        }

                        // get the new active element
                        $link = $items.eq(move % $items.length);
                    }

                    $link.addClass('active');

                    if (content_id && !$link.attr('id')) {
                        $link.attr('id', content_id + '-active-item');
                    }

                    if ($link.attr('id')) {
                        $controller.attr('aria-activedescendant', $link.attr('id'));
                    }

                    // move focus when the dropdown's controller is not search box
                    if (!$controller.eq('input')) {
                        $link.focus();
                    }
                }
            });
        }

        // navigate to an active link or click on it
        // note that `trigger('click')` doesn't always work
        if (e.keyCode == 13) {
            var $link = $('.dropdown-content:visible .active');
            if ($link.length) {
                if ($link.attr('href')) {
                    location.href = $link.attr('href');
                } else {
                    $link.trigger('click');
                }
            }
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
            // Do not handle non-primary click.
            if (e.button != 0 || $content.hasClass('hover-display')) {
                return;
            }
            toggleDropDown(e, $button, $content);
        }).keydown(function(e) {
            if (e.keyCode == 13) {
                if ($button.eq('input') && !$button.val()) {
                    // prevent the form being submitted if the search bar is empty
                    e.preventDefault();
                    // navigate to an active link if any
                    var $link = $content.find('.active');
                    if ($link.length) {
                        if ($link.attr('href')) {
                            location.href = $link.attr('href');
                        } else {
                            $link.trigger('click');
                        }
                    }
                }

                // allow enter to toggle menu
                toggleDropDown(e, $button, $content);
            }
        });

        if ($content.hasClass('hover-display')) {
            const $_button = $button.get(0);
            const $_content = $content.get(0);
            let timer;

            const button_handler = event => {
                event.preventDefault();
                event.stopPropagation();
                window.clearTimeout(timer);

                if (event.type === 'mouseleave' && $_content.matches('.hovered')) {
                    return;
                }

                timer = window.setTimeout(() => {
                    toggleDropDown(event, $button, $content, event.type === 'mouseenter', event.type === 'mouseleave');
                }, 250);
            };

            const content_handler = event => {
                event.preventDefault();
                event.stopPropagation();
                window.clearTimeout(timer);

                $_content.classList.toggle('hovered', event.type === 'mouseenter');

                if (event.type === 'mouseleave') {
                    timer = window.setTimeout(() => {
                        toggleDropDown(event, $button, $content, false, true);
                    }, 250);
                }
            };

            // Use raw `addEventListener` as jQuery actually listens `mouseover` and `mouseout`
            $_button.addEventListener('mouseenter', event => button_handler(event));
            $_button.addEventListener('mouseleave', event => button_handler(event));
            $_content.addEventListener('mouseenter', event => content_handler(event));
            $_content.addEventListener('mouseleave', event => content_handler(event));
        }
    });

    function toggleDropDown(e, $button, $content, show_only, hide_only) {
        // hide other expanded dropdown menu if any
        var $expanded = $('.dropdown-button[aria-expanded="true"]');
        if ($expanded.length && !$expanded.is($button)) {
            $('#' + $expanded.attr('aria-controls')).hide();
            $expanded.attr('aria-expanded', false);
        }

        // don't expand the dropdown if there's no item
        var $items = $content.find('[role="menuitem"], [role="option"]');
        if (!$items.length) {
            return;
        }

        // clear all active links
        $content.find('a').removeClass('active');
        var content_id = $content.attr('id');
        if (content_id) {
            $('[aria-controls="' + content_id + '"]').removeAttr('aria-activedescendant');
            $content.find('#' + content_id + '-active-item').removeAttr('id');
        }
        // if not using Escape or clicking outside the dropdown div, then we are hiding
        if ($content.is(':visible') || hide_only) {
            $content.fadeOut('fast');
            $button.attr('aria-expanded', false);
        } else if (!$content.is(':visible') || show_only) {
            $content.fadeIn('fast');
            $button.attr('aria-expanded', true);
        }
    }
});
