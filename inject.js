$(function() {
  var flash = window.runtime.flash;
  var trace = window.runtime.trace;

  var insufficientDataError = new Error("Insufficient data in buffer.");

  var socket = new flash.net.Socket();
  var buffer = "", expectBuffer = "";
  var state = 'idle';

  function ruby_escape(o) {
	if (o === true) return "true";
	if (o === false) return "false";
	if (o === null || o === undefined) return "nil";
	if (typeof(o) == "string") return '"' + o.replace(/"/g, "\\\"").replace(/\\/g, "\\\\") + '"';
	if (typeof o == "number") return "" + o;
	if (o && typeof(o) == "object") {
	  if (typeof o.length == 'number' && !(o.propertyIsEnumerable('length')) && typeof o.splice == 'function') {
		// Looks suspiciously like an array. Treat it as one.
		var ret = "[", first = true;
		for (var key in o) {
		  if (first) first = false; else ret += ", ";
		  ret += ruby_escape(o[key])
		}
		ret += "]";
		return ret;
	  } else {
		// Ordinary object!
		var ret = "{", first = true;
		for (var key in o) {
		  if (first) first = false; else ret += ", ";
		  ret += ruby_escape(key) + " => " + ruby_escape(o[key]);
		}
		ret += "}";
		return ret;
	  }
	}
	throw new Error("Who knows what type " + o + " is? We can't serialise it.");
  }

  function process() {
	var insufficientData = false;

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
	  var command = expect_str();
	  var argc = expect_int(),
		  args = [];

	  while (argc > 0) {
		args.push($.parseJSON(expect_str()));
		argc--;
	  }

	  try {
		var result = commands[command].apply(this, args);
	  } catch (e) {
		trace("got an error instead; " + e);
	  }

	  send_str(ruby_escape(result));
	  flush();
	},
  };

  var commands = {
	/*'eval': function(cmd) {
	  return eval(cmd);
	},*/
	'safeeval': function(cmd) {
	  return window.safeeval(cmd);
	},
	'fakeeval': function(path) {
	  // Make the initial function call.
	  var initial = path.shift();
	  var current =	top[initial[0]].apply(this, initial[1]);

	  for (var i in path) {
		var fn = path[i][0], args = path[i][1];

		// If we were given no arguments and the target 'function'
		// appears not to be a function at all, just use it like an
		// object.
		if (typeof current[fn] != "function" && args.length == 0) {
		  current = current[fn];
		} else {
		  // Otherwise, we'll call the function with given arguments.
		  current = current[fn].apply(current, args);
		}
	  }

	  return current;
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

  function send_int(i) {
	socket.writeUTFBytes("" + i + ",");
  }

  function send_str(str) {
	send_int(str.length);
	socket.writeUTFBytes(str);
  }

  function flush() {
	socket.flush();
  }

  socket.addEventListener(flash.events.ProgressEvent.SOCKET_DATA, function(e) {
	buffer += socket.readUTFBytes(socket.bytesAvailable);
	process();
  });

  socket.connect("127.0.0.1", SWIFTEST_PORT);
});
