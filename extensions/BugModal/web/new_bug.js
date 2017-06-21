$(document).ready(function() {
    bugzilla_ajax(
            {
                url: 'rest/bug_modal/products'
            },
            function(data) {
                $('#product').empty()
                $('#product').append($('<option>', { value: 'Select Product', text: 'Select Product' }));
                // populate select menus
                $.each(data.products, function(key, value) {
                    $('#product').append($('<option>', { value: value.name, text: value.name }));
                });
            },
            function() {}
        );

    $('#component').empty()
    $('#component').append($('<option>', { value: 'Select Component', text: 'Select Component' }));

    $('#product')
    .change(function(event) {
        $('#product-throbber').show();
        $('#component').attr('disabled', true);
        $("#product option[value='Select Product']").remove();
        bugzilla_ajax(
            {
                url: 'rest/bug_modal/components?product=' + encodeURIComponent($('#product').val())
            },
            function(data) {
                $('#product-throbber').hide();
                $('#component').attr('disabled', false);
                $('#component').empty();
                $('#component').append($('<option>', { value: 'Select Component', text: 'Select Component' }));
                $('#comp_desc').text('Select a component to read its description.');
                $.each(data.components, function(key, value) {  
                    $('#component').append('<option value=' + value.name + ' desc=' + value.description.split(' ').join('_') + '>' + value.name + '</option>');
                });
            },
            function() {}
        );
    });
    $('#component')
    .change(function(event) {
        $("#component option[value='Select Product']").remove();
        $('#comp_desc').text($('#component').find(":selected").attr('desc').split('_').join(' '));
    });
    
});
