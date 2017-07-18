var initial = {}
var comp_desc = {}

$(document).ready(function() {
    bugzilla_ajax(
            {
                url: 'rest/bug_modal/initial_field_values'
            },
            function(data) {
                initial = data
            },
            function() {
                alert("Network issues. Please refresh the page and try again");
            }
        );
    var product_sel = $("#product").selectize({
        valueField: 'name',
        labelField: 'name',
        searchField: 'name',
        options: [],
        preload: true,
        create: false,
        load: function(query, callback) {
            callback(initial.products);
        }
    });
    var component_sel = $("#component").selectize({
        valueField: 'name',
        labelField: 'name',
        searchField: 'name',
        options: [],
    });

    var version_sel = $("#version").selectize({
        valueField: 'name',
        labelField: 'name',
        searchField: 'name',
        options: [],
    });

    var keywords_sel = $("#keywords").selectize({
        delimiter: ', ',
        valueField: 'name',
        labelField: 'name',
        searchField: 'name',
        options: [],
        preload: true,
        create: false,
        load: function(query, callback) {
            callback(initial.keywords);
        }
    });

    product_sel.on("change", function () {
        $('#product-throbber').show();
        $('#component').attr('disabled', true);
        bugzilla_ajax(
                {
                    url: 'rest/bug_modal/product_info?product=' + encodeURIComponent($('#product').val())
                },
                function(data) {
                    $('#product-throbber').hide();
                    $('#component').attr('disabled', false);
                    $('#comp_desc').text('Select a component to read its description.');
                    var selectize = $("#component")[0].selectize;
                    selectize.clear();
                    selectize.clearOptions();
                    selectize.load(function(callback) {
                        callback(data.components)
                    });

                    for (var i in data.components)
                        comp_desc[data.components[i]["name"]] = data.components[i]["description"];

                    selectize = $("#version")[0].selectize;
                    selectize.clear();
                    selectize.clearOptions();
                    selectize.load(function(callback) {
                        callback(data.versions);
                    });
                },
                function() {
                    alert("Network issues. Please refresh the page and try again");
                }
            );     
    });

    component_sel.on("change", function () {
        var selectize = $("#component")[0].selectize;
        $('#comp_desc').text(comp_desc[selectize.getValue()]);
    });

    $('.create-btn')
        .click(function(event) {
            event.preventDefault();
            if (document.newbugform.checkValidity && !document.newbugform.checkValidity())
                return;
            this.form.submit()
        });
    
});
