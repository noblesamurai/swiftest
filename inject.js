/* 
 * Copyright 2010 Noble Samurai
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

  var state_fncall_db = [];

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
		  state_fncall_db.push(o[key])
		  if (o[key] && typeof o[key] == 'object' && o[key].title) {
			top.air.trace(o[key].title + ": " + state_fncall_db.length);
		  }
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

  if (top.ns && top.ns.modalDialog) {
    top.ns.modalDialog = function(message, title) {
      top.air.trace("Swiftest: caught modal dialog: " + message);
      top.Swiftest.alerts.push(message);
    }
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

  top.Swiftest.navigates = [];
  top.air.navigateToURL = function(urlrequest) {
	top.air.trace("Swiftest: caught navigateToURL to " + urlrequest.url);
	top.Swiftest.navigates.push(urlrequest.url);
  }

  /* JT: This is fairly specific, but the only way I can override File.browseFor(...)
   * To use it, copy the reference below, replace the Swiftest-specific code with:
   *    // Add listeners for what was provided
   *    var events = [ air.Event.SELECT, air.Event.CANCEL ];
   *    for (var i in listeners) {
   *      file.addEventListener(events[i], listeners[i]);
   *    }
   *    file[type].apply(file, fn_args);
   *  and use top.browseForSave(file, title, selectEventListener, cancelEventListener);
   */
  top.Swiftest.browseDialogFile = "";
  top.Swiftest.browseDialogs = [];
  var browseTypes = [ "browseForDirectory", "browseForOpen", "browseForSave" ];
  for (var i in browseTypes) {
    var _type = browseTypes[i];
    if (top[_type]) {
      top[_type] = function(type) {
        return function() {
		  top.air.trace("Swiftest: Caught File." + type);
		  // Make it easier to work with arguments
		  var args = Array.prototype.slice.call(arguments);
		  var file = args.shift();
		  // Anything up until type function is an argument
		  var fn_args = [];
		  var listeners = [];
		  while (args.length > 0) {
			  if (typeof args[0] == 'function') break;
			  fn_args.push(args.shift());
		  }
		  while (args.length > 0) {
			  listeners.push(args.shift());
		  }

		  var listener, event, name;

		  if (top.Swiftest.browseDialogFile != null) {
			top.air.trace("Swiftest: Causing SELECT event with file " + top.Swiftest.browseDialogFile);
			listener = listeners[0];
			file.url = 'file:///' + top.Swiftest.browseDialogFile;
			event = { target: new top.air.File(file.url) };
			name = 'select';
		  } else {
			top.air.trace("Swiftest: Causing CANCEL event");
			listener = listeners[1];
			name = 'cancel';
		  } 

		  // No listener for this event
		  if (!listener) {
			top.air.trace("Swiftest: No listener for event " + name);
			return;
		  }

		  top.air.trace("Pushing browseDialog");
		  // JT: Todo, make this push an object specifying type of dialog, not just title
		  top.Swiftest.browseDialogs.push(fn_args[0]);
		  top.air.trace("Calling listener " + listener);
		  listener(event);
        }
	  }(_type);
	}
  };

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

  top.Swiftest.get_back_ref = get_back_ref;

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
		result = "" + e + " (" + e.sourceURL + ":" + e.line + "(" + e.sourceId + "))";
	  }

	  send_bool(success);
	  send_bool(top.Swiftest.alerts.length > 0 || top.Swiftest.confirms.length > 0 || top.Swiftest.prompts.length > 0 || top.Swiftest.navigates.length > 0 || top.Swiftest.browseDialogs.length > 0);
	  send_str(ruby_escape(result));
	  flush();
	},
  };

  function path_call(target, path_el) {
	var fn = path_el[0], args = path_el[1];

	// If we were given no arguments and the target 'function'
	// appears not to be a function at all, just use it like an
	// object.
	
	if (fn[fn.length - 1] == "=") {
	  // Assignment.
	  fn = fn.substr(0, fn.length - 1);
	  target[fn] = args[0];
	  return target[fn];
	} else if ((typeof target[fn] != "function" || target[fn].apply === undefined) && args.length == 0) {
	  return target[fn];
	} else if (typeof target[fn] == "function" && args.length == 0
		&& (
		  (("" + target[fn]).match(/^\[class .*\]$/)
			&& target[fn].constructor == target[fn].constructor.constructor)
		  || (target[fn].fn && typeof target[fn].fn.jquery == "string"))) {
		  
	  // Looks like an ActionScript class, or the jQuery function/object.
	  // Given it's being called without args, traverse it instead.

	  return target[fn];
	} else {
	  if (target[fn] === undefined) {
		throw new Error("trying to call " + target + "." + fn + ", which is undefined");
	  }
	  if (target[fn].apply === undefined) {
		throw new Error("target[fn].apply is undefined, yet we have type (" + typeof(target[fn]) + ") and args (" + args.length + ")");
	  }

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
	  top.air.trace("STATE: " + state);
	  top.air.trace("STATE: " + get_back_ref(state));
	  // We get a variable number of arguments after state and fn -
	  // pull out of `arguments` and drop the first two.
	  var args = Array.prototype.slice.call(arguments, 2);

	  var current = (state === false) ? top : get_back_ref(state);
	  current = path_call(current, [fn, args]);

	  state_fncall_db.push(current);
	  return [current, state_fncall_db.length - 1];
	},
	'state-getprop': function(state, prop) {
	  var current = (state === false) ? top : get_back_ref(state);
	  current = current[prop];

	  state_fncall_db.push(current);
	  return [current, state_fncall_db.length - 1];
	},
	'acp-state': function() {
	  var rval = [top.Swiftest.alerts, top.Swiftest.confirms, top.Swiftest.prompts, top.Swiftest.navigates, top.Swiftest.browseDialogs];
	  top.Swiftest.alerts = [];
	  top.Swiftest.confirms = [];
	  top.Swiftest.prompts = [];
	  top.Swiftest.navigates = [];
	  top.Swiftest.browseDialogs = [];
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
	'set-browsedialog-file' : function(file) {
	  var oldFile = top.Swiftest.browseDialogFile;
	  top.air.trace('set-browsedialog-file: ' + file);
	  top.Swiftest.browseDialogFile = file;
      return oldFile;
	},
	'noop': function() {
	  return 42;
	},
	'get-clipboard' : function(format) {
		format = format || top.air.ClipboardFormats.TEXT_FORMAT;
		return air.Clipboard.generalClipboard.getData(format) || null;
	},
	'set-clipboard': function(text, format) {
		format = format || top.air.ClipboardFormats.TEXT_FORMAT;
		return air.Clipboard.generalClipboard.setData(format, text);
	}
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
	var bytearr = new flash.utils.ByteArray();
	bytearr.writeUTFBytes(str);

	send_int(bytearr.length);
	socket.writeBytes(bytearr);
  }

  function flush() {
	socket.flush();
  }

  top.Swiftest.manual_pass = function() {
	send_bool(true);
  };
  top.Swiftest.manual_fail = function() {
	send_bool(false);
  };

  $(".swiftest-overlay-manual-pass").click(top.Swiftest.manual_pass);
  $(".swiftest-overlay-manual-fail").click(top.Swiftest.manual_fail);

  socket.addEventListener(flash.events.ProgressEvent.SOCKET_DATA, function(e) {
	buffer += socket.readUTFBytes(socket.bytesAvailable);
	process();
  });

  socket.connect("127.0.0.1", SWIFTEST_PORT);
};

$(top.Swiftest);

// vim: set sw=2:
