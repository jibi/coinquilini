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

