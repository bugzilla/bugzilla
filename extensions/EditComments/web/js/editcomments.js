/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

$(function() {
    $('.edit-comment-btn')
        .click(function(event) {
            event.preventDefault();
            var that = $(this);
            var id = that.data('id');
            var no = that.data('no');

            // cancel editing
            if (that.data('editing')) {
                that.data('editing', false).text('Edit');
                $('#edit_comment_textarea_' + id).remove();
                $('#ct-' + no).show();
                return;
            }
            that.text('Unedit');

            // replace comment <pre> with loading message
            $('#ct-' + no)
                .hide()
                .after(
                    $('<pre/>')
                        .attr('id', 'edit-comment-loading-' + id)
                        .addClass('edit-comment-loading')
                        .text('Loading...')
                );

            // load original comment text
            bugzilla_ajax(
                {
                    url: 'rest/editcomments/comment/' + id,
                    hideError: true
                },
                function(data) {
                    // create editing textarea
                    $('#edit-comment-loading-' + id).remove();
                    that.data('editing', true);
                    $('#ct-' + no)
                        .after(
                            $('<textarea/>')
                                .attr('name', 'edit_comment_textarea_' + id)
                                .attr('id', 'edit_comment_textarea_' + id)
                                .addClass('edit-comment-textarea')
                                .val(data.comments[id])
                        );
                },
                function(message) {
                    // unedit and show message
                    that.data('editing', false).text('Edit');
                    $('#edit-comment-loading-' + id).remove();
                    $('#ct-' + no).show();
                    alert(message);
                }
            );
        });
});
