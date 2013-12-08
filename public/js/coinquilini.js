function
show_success_alert(msg, where) {
	var res = '<div id="alertOkPay" class="alert alert-success fade in">' + msg + '</div>';
	where.append(res);

	setTimeout( function() { $("#alertOkPay").alert("close") }, 3000);
}

function
show_fail_alert(msg, where) {
	var res = '<div id="alertFailPay" class="alert alert-danger fade in">' + msg + '</div>';
	where.append(res);

	setTimeout( function() { $("#alertFailPay").alert("close") }, 3000);
}

function
send_payment(form) {

	var list = $(form).find("#selectList option:selected").val();
	var what = $(form).find("#inputWhat").val();
	var sum  = $(form).find("#inputHowMuch").val();

	var request = $.ajax({
		dataType: "json",
		url: "/",
		type: "POST",
		data: {
			list : list,
	    		what : what,
	    		sum  : sum
		}
	});

	request.done(function(data) {
		var res;
		var where = $("#formNewPayment");

		if (data['status'] == 'error') {
			show_fail_alert(data['msg'], where);
		} else {
			show_success_alert(data['msg'], where);

			$(form).find("#inputWhat").val("");
			$(form).find("#inputHowMuch").val("");
		}

	});

	request.fail(function(jq_xhr, test_status) {
		var where = $("#formNewPayment");
		show_fail_alert(text_status, where);
	});

	return false;
}
function
toggleShow(checkbox, what) {
	el = document.getElementById(checkbox.name);
	if (checkbox.checked) {
		el.style.display = 'block';
	} else {
		el.style.display = 'none';
	}
}

function
set_paid(debt_id) {
	var request = $.post("/set_paid", {debt_id: debt_id});

	var request = $.ajax({
		dataType: "json",
		url: "/set_paid",
		type: "POST",
		data: { debt_id : debt_id }
	});

	request.done(function(data) {
		$('#debt_' + debt_id).html('<span style="color: #24de44" class="glyphicon glyphicon-ok"></span>')
	});

	request.fail(function(jq_xhr, test_status) {
		alert("Cannot set paid :(");
	});


	return false;
}

