$("#add").click(function () {
    let i = parseInt($('input').eq(-2).attr('name')) + 1;
    let inputs = $('tr');
    let point = inputs.last().clone(true, true).appendTo('tbody');
    point.find('input, select').val('').attr('name', () => ++i);
});

$(".del").click(function () {
    if ($('tr').length <= 2)
        $(this).parent().children().first().val("");
    else
        $(this).parent().parent().remove();
});

window.onbeforeunload = () => true;

$('input').last().click(() => {
    window.onbeforeunload = null;
});