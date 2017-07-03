var comp_desc = {}

function load_products(query, callback) {
    bugzilla_ajax(
            {
                url: 'rest/bug_modal/products'
            },
            function(data) {
                callback(data.products);
            },
            function() {
                callback();
            }
        );
}

$(document).ready(function() {
    var product_sel = $("#product").selectize({
        valueField: 'name',
        labelField: 'name',
        searchField: 'name',
        options: [],
        preload: true,
        create: false,
        load: load_products
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

    product_sel.on("change", function () {
        $('#product-throbber').show();
        $('#component').attr('disabled', true);
        bugzilla_ajax(
                {
                    url: 'rest/bug_modal/product_info?product=' + encodeURIComponent($('#product').val())
                },
                function(data) {
                    product_info = data;
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
