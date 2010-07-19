/* 
 * Copyright 2010 Arlen Cuss
 * 
 * Swiftest is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * Swiftest is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with Swiftest.  If not, see <http://www.gnu.org/licenses/>.
 */

top.Swiftest = function() {
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

	switch (typeof(o)) {
	case "string":
	  return '"' + o.replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + '"';

	case "number":
	  return "" + o;

	case "object":
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
		// Instead of actually serialising the entire object,
		// we just return this proxy-ish object instead. Any attempt to access 
		// properties will hit method_missing, which should then
		// actually come back to the JavaScript to find the value.

		// ?: we could list the keys later if we wanted to know that client-side
		return "SwiftestCommands::StateObject.new(:object)";
	  }
	  break;	// shall not be reached
	
	case "function":
	  return "SwiftestCommands::StateObject.new(:function)";

	case "undefined":
	  return "SwiftestCommands::StateObject.new(:type_undefined)";

	default:
	  trace("unknown type " + (typeof o) + " of " + o);
	  throw new Error("Who knows what type " + o + " is? (" + (typeof o) + ") We can't serialise it.");
	}
  }

  top.Swiftest.alerts = [];
  top.alert = function(msg) {
	// HACK: the AIR Introspector determines windows' "realness"
	// based on whether they have an alert function with native code.
	// If it finds no "real" windows open when it initialises, it
	// exits the app(!!). This makes it think we're "real."
	"[native code]";

	top.air.trace("Swiftest: caught alert " + msg);
	top.Swiftest.alerts.push(msg);
  }

  top.Swiftest.confirmReply = true;
  top.Swiftest.confirms = [];
  top.confirm = function(msg) {
	top.air.trace("Swiftest: caught confirm " + msg + ", saying " + top.Swiftest.confirmReply);
	top.Swiftest.confirms.push(msg);
	return top.Swiftest.confirmReply;
  }

  top.Swiftest.promptReply = "::DEFAULT::";
  top.Swiftest.prompts = [];
  top.prompt = function(msg, def) {
	var reply = top.Swiftest.promptReply;

	if (reply == "::DEFAULT::")
	  reply = def;
	else if (reply == "::CANCEL::")
	  reply = null;

	top.air.trace("Swiftest: caught prompt " + msg + " with default " + def + ", saying " + reply);
	top.Swiftest.prompts.push(msg);
	return reply;
  }

  var state_fncall_db = [];
  var redefined_builtins = false;

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
		} else {
		  trace("error occurred while processing state " + state + ": " + e);
		}
	  }
	}
  }

  function get_back_ref(ref) {
	return state_fncall_db[parseInt(ref)];
  }

  var processors = {
	'idle': function() {
	  var command = expect_str();
	  var argc = expect_int(),
		  args = [];

	  while (argc > 0) {
		var arg_type = expect_str();
		switch (arg_type) {
		case "s":
		  // Plain JSON arg.
		  var result = expect_str();
		  result = $.parseJSON(result);
		  break;
		case "b":
		  // Back reference.
		  var result = get_back_ref(expect_int());
		  break;
		default:
		  throw new Error("No idea what type of argument '" + arg_type + "' is!");
		}

		args.push(result);
		argc--;
	  }

	  var success = false;
	  try {
		var result = commands[command].apply(this, args);
		success = true;
	  } catch (e) {
		result = "" + e;
	  }

	  send_bool(success);
	  send_bool(top.Swiftest.alerts.length > 0 || top.Swiftest.confirms.length > 0);
	  send_str(ruby_escape(result));
	  flush();
	},
  };

  function path_call(target, path_el) {
	var fn = path_el[0], args = path_el[1];

	// If we were given no arguments and the target 'function'
	// appears not to be a function at all, just use it like an
	// object.
	
	if (typeof target[fn] != "function" && args.length == 0) {
	  return target[fn];
	} else if (typeof target[fn] == "function" && args.length == 0
		&& ("" + target[fn]).match(/^\[class .*\]$/)
		&& target[fn].constructor == target[fn].constructor.constructor) {
	  // Looks like an ActionScript class.
	  return target[fn];
	} else {
	  return target[fn].apply(target, args);
	}
  }

  var commands = {
	'fncall': function(path) {
	  // Make the initial function call.
	  // This isn't actually used at the moment ...
	  var initial = path.shift();
	  var current =	top[initial[0]].apply(this, initial[1]);

	  for (var i in path) {
		current = path_call(current, path[i]);
	  }

	  return current;
	},
	'state-fncall': function(state, fn) {
	  // We get a variable number of arguments after state and fn -
	  // pull out of `arguments` and drop the first two.
	  var args = Array.prototype.slice.call(arguments, 2);

	  var current = (state === false) ? top : get_back_ref(state);
	  current = path_call(current, [fn, args]);

	  state_fncall_db.push(current);
	  return [current, state_fncall_db.length - 1];
	},
	'acp-state': function() {
	  var rval = [top.Swiftest.alerts, top.Swiftest.confirms, top.Swiftest.prompts];
	  top.Swiftest.alerts = [];
	  top.Swiftest.confirms = [];
	  top.Swiftest.prompts = [];
	  return rval;
	},
	'set-confirm-reply': function(reply) {
	  var oldCr = top.Swiftest.confirmReply;
	  top.Swiftest.confirmReply = (reply + "" == "true");
	  return oldCr;
	},
	'set-prompt-reply': function(reply) {
	  var oldPr = top.Swiftest.promptReply;
	  top.Swiftest.promptReply = reply;
	  return oldPr;
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

  function send_bool(i) {
	socket.writeUTFBytes(i ? "t" : "f");
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
};

$(top.Swiftest);

// vim: set sw=2:
