$(function() {
  var flash = window.runtime.flash;
  var trace = window.runtime.trace;

  var insufficientDataError = new Error("Insufficient data in buffer.");

  var socket = new flash.net.Socket();
  var buffer = "", expectBuffer = "";
  var state = 'idle';

  function process() {
	var insufficientData = false;

	trace("buffer is '" + buffer + "'");
	expectBuffer = buffer;
	while (!insufficientData) {
	  buffer = expectBuffer;
	  try {
		processors[state]();
	  } catch (e) {
		if (e == insufficientDataError) {
		  insufficientData = true;
		  expectBuffer = buffer;
		}
	  }
	}
  }

  var processors = {
	'idle': function() {
	  trace("idle running");
	  var command = expect_str();
	  var argc = expect_int(),
		  args = [];

	  while (argc > 0) {
		args.push(expect_str());
		argc--;
	  }

	  trace("got cmd " + command + " with " + args.length + " args");
	},
  };

  function expect_int() {
	if (expectBuffer.indexOf(",") == -1) throw insufficientDataError;
	var i = parseInt(expectBuffer);
	expectBuffer = expectBuffer.substr(expectBuffer.indexOf(",") + 1);
	return i;
  }

  function expect_str() {
	var len = expect_int();
	if (expectBuffer.length < len) throw insufficientDataError;
	var s = expectBuffer.substr(0, len);
	expectBuffer = expectBuffer.substr(len);
	return s;
  }

  socket.addEventListener(flash.events.ProgressEvent.SOCKET_DATA, function(e) {
	trace("going to process with " + e.bytesLoaded + " bytes");
	process();
  });

  socket.connect("127.0.0.1", SWIFTEST_PORT);
  trace(socket);
});
