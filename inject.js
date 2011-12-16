/**
 * Copyright 2010-2011 Noble Samurai
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
	var SWIFTEST_PORT = top.window.runtime.com.noblesamurai.Application.swiftestPort;

	var HEARTBEAT_FREQUENCY = 2500,
		HEARTBEAT_RESPONSE_WAIT = 5000,
		HEARTBEAT_FAIL_LIMIT = 10;

	var flash = window.runtime.flash;
	var trace = function(s) {
		window.runtime.trace("Swiftest: " + s);
	};

	trace("initialising ...");

	var socket = new flash.net.DatagramSocket();
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
			break;       // shall not be reached

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
		top.ns.modalDialog = function(message, title, options, callback) {
			top.air.trace("Swiftest: caught modal dialog: " + message);
			top.Swiftest.alerts.push(message);

			if (callback) {
				callback();
			}
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
	*        file.addEventListener(events[i], listeners[i]);
	*    }
	*    file[type].apply(file, fn_args);
	* and use top.browseForSave(file, title, selectEventListener, cancelEventListener);
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

	var last_received = 0;
	function process(bytes) {
		bytes.uncompress(window.runtime.flash.utils.CompressionAlgorithm.DEFLATE);

		bytes.position = 0;

		var pkt_no = bytes.readUnsignedInt();

		if (pkt_no == 0) {
			var lr = bytes.readUnsignedInt();
			last_received = lr;

			var no_replies = 0;
			for (var no in replies) {
				if (no <= last_received) {
					delete replies[no];
				} else {
					send_packet(replies[no]);
					++no_replies;
				}
			}

			heartbeatReceived();
			return;
		}

		try {
			processPacket(pkt_no, bytes);
		} catch (e) {
			trace("error occured while processing packet " + pkt_no + " (" + bytes.readUTFBytes(bytes.bytesAvailable) + "): " + e);
			return;
		}
	}

	function get_back_ref(ref) {
		return state_fncall_db[parseInt(ref)];
	}

	top.Swiftest.get_back_ref = get_back_ref;

	var replies = {};
	var last_processed = 0;
	function processPacket(no, bytes) {
		if (replies[no] !== undefined) {
			send_packet(replies[no]);
			return;
		}

		var command = bytes.readUTF();
		var argc = bytes.readUnsignedInt(),
			args = [];

		while (argc > 0) {
			var arg_type = bytes.readUTFBytes(1);
			switch (arg_type) {
			case "s":
				// Plain JSON arg.
				var result = bytes.readUTF();
				result = $.parseJSON(result);
				break;
				
			case "b":
				// Back reference.
				var result = get_back_ref(bytes.readUnsignedInt());
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

		var reply = new flash.utils.ByteArray();
		reply.writeUnsignedInt(no);
		reply.writeBoolean(success);
		reply.writeBoolean(
			top.Swiftest.alerts.length || top.Swiftest.confirms.length ||
			top.Swiftest.prompts.length || top.Swiftest.navigates.length ||
			top.Swiftest.browseDialogs.length);
		reply.writeUTFBytes(ruby_escape(result));

		replies[no] = reply;
		if (no > last_processed)
			last_processed = no;
		send_packet(reply);
	}

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
		} else if (
				typeof target[fn] == "function"
				&& args.length == 0
				&& ((("" + target[fn]).match(/^\[class .*\]$/) && target[fn].constructor == target[fn].constructor.constructor)
					|| (target[fn].fn && typeof target[fn].fn.jquery == "string"))) {
			// Looks like an ActionScript class, or the jQuery function/object.
			// Given it's being called without args, traverse it instead.

			return target[fn];
		} else {
			if (target[fn] === undefined)
				throw new Error("trying to call " + target + "." + fn + ", which is undefined");
			if (target[fn].apply === undefined)
				throw new Error("target[fn].apply is undefined, yet we have type (" + typeof(target[fn]) + ") and args (" + args.length + ")");

			return target[fn].apply(target, args);
		}
	}

	var commands = {
		'state-fncall': function(state, fn) {
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
		'get-clipboard': function(format) {
			format = format || top.air.ClipboardFormats.TEXT_FORMAT;
			return air.Clipboard.generalClipboard.getData(format) || null;
		},
		'set-clipboard': function(text, format) {
			format = format || top.air.ClipboardFormats.TEXT_FORMAT;
			return air.Clipboard.generalClipboard.setData(format, text);
		},
		'manual': function(index) {
			if (top.Swiftest.last_manual[0] == index) {
				return top.Swiftest.last_manual[1] ? 'pass' : 'fail';
			}
			return null;
		},
	};

	function serialise_bool(b) {
		return (!!b) ? "t" : "f";
	}

	function serialise_str(s) {
		return serialise_int(s.length) + s;
	}

	function serialise_int(i) {
		return "" + i + ",";
	}

	function send_packet(pkt) {
		socket.send(pkt);
	}

	top.Swiftest.last_manual = [-1, true];

	top.Swiftest.manual_pass = function() {
		top.Swiftest.last_manual = [top.Swiftest.last_manual[0] + 1, true];
		$("#swiftest-overlay-ff").removeClass("manual");
	};
	top.Swiftest.manual_fail = function() {
		top.Swiftest.last_manual = [top.Swiftest.last_manual[0] + 1, false];
		$("#swiftest-overlay-ff").removeClass("manual");
	};

	$(".swiftest-overlay-manual-pass").click(top.Swiftest.manual_pass);
	$(".swiftest-overlay-manual-fail").click(top.Swiftest.manual_fail);

	socket.addEventListener(flash.events.IOErrorEvent.IO_ERROR, function(e) {
		trace("IO error!");
	});

	socket.addEventListener(flash.events.SecurityErrorEvent.SECURITY_ERROR, function(e) {
		trace("security error!");
	});

	socket.addEventListener(flash.events.DatagramSocketDataEvent.DATA, function(event) {
		process(event.data);
	});

	var heartbeatFailTimeout = null;
	var heartbeatFailCount = 0;
	var heartbeatTimeout = null;

	function heartbeat() {
		var bytes = new flash.utils.ByteArray();
		bytes.writeUnsignedInt(0);
		bytes.writeUnsignedInt(last_processed);

		socket.send(bytes);

		clearTimeout(heartbeatTimeout);
		clearTimeout(heartbeatFailTimeout);
		heartbeatTimeout = null;
		heartbeatFailTimeout = setTimeout(heartbeatFail, HEARTBEAT_RESPONSE_WAIT);
	}

	function scheduleHeartbeat() {
		clearTimeout(heartbeatFailTimeout);
		clearTimeout(heartbeatTimeout);
		heartbeatFailTimeout = null;
		heartbeatTimeout = setTimeout(heartbeat, HEARTBEAT_FREQUENCY);
	}

	function heartbeatFail() {
		trace("heartbeat failed!! (fail #" + (++heartbeatFailCount) + ")");
		if (heartbeatFailCount >= HEARTBEAT_FAIL_LIMIT) {
			trace("fail count over limit (" + HEARTBEAT_FAIL_LIMIT + "): good bye");
			top.air.NativeApplication.nativeApplication.exit();
		}

		scheduleHeartbeat();
	}

	function heartbeatReceived() {
		heartbeatFailCount = 0;

		scheduleHeartbeat();
	}

	trace("trying to reach out to 127.0.0.1:" + SWIFTEST_PORT);
	socket.bind(0, "127.0.0.1");
	socket.connect("127.0.0.1", parseInt(SWIFTEST_PORT));

	heartbeat();
	socket.receive();
};

$(top.Swiftest);
