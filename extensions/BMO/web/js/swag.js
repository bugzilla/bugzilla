/**
 * Swag Request Form Functions
 * Form Interal Swag Request Form
 * dtran
 * 7/6/09
 **/


function evalToNumber(numberString) {
    if(numberString=='') return 0;
    return parseInt(numberString);
}

function evalToNumberString(numberString) {
    if(numberString=='') return '0';
    return numberString;
}
//item_array should be an array of DOM element ids
function getTotal(item_array) {
    var total = 0;
    for(var i in item_array) {
        total += evalToNumber(document.getElementById(item_array[i]).value);
    }
    return total;
}

function calculateTotalSwag() {   
    document.getElementById('Totalswag').value = 
        getTotal( new Array('Lanyards',
            'Stickers',
            'Bracelets',
            'Tattoos',
            'Buttons',
            'Posters'));
    
}


function calculateTotalMensShirts() {   
    document.getElementById('mens_total').value = 
    getTotal( new Array('mens_s',
            'mens_m',
            'mens_l',
            'mens_xl',
            'mens_xxl',
            'mens_xxxl'));
    
}


function calculateTotalWomensShirts() {   
    document.getElementById('womens_total').value = 
    getTotal( new Array('womens_s',
            'womens_m',
            'womens_l',
            'womens_xl',
            'womens_xxl',
            'womens_xxxl'));
    
}
