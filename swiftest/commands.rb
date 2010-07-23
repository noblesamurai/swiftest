# Copyright 2010 Arlen Cuss
#  
# Swiftest is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#  
# Swiftest is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#  
# You should have received a copy of the GNU General Public License
# along with Swiftest.  If not, see <http://www.gnu.org/licenses/>.

require File.join(File.dirname(__FILE__), 'jsescape')

module SwiftestCommands
  #   Compiles a path of function calls made in the context
  # of an instance of this class.
  #   All calls return the same path object so chains work.
  # This is the main usage, and making multiple calls inside
  # the one block will probably just mix them together.
  #
  # Example:
  #
  # (o = FakeEvalPath.new).instance_eval {
  # 	joe(1, 2).frank
  # }
  # o.path  # => [[:joe, [1, 2]], [:frank, []]]
  class FakeEvalPath
	def initialize; @path = []; end

	def method_missing(sym, *args)
	  @path << [sym, args]
	  self
	end

	attr_reader :path
  end

  #   Mixed into real objects and StateObjects, this module
  # causes the object to proxy any missing methods to JavaScript
  # using state-fncall.
  #   When kicked off by a StateFnCaller, the
  # state is false, and the other end just resolves from `top'.
  #   When kicked off by a proxified object (i.e. the output of
  # this very own thing), the state will be the state number
  # returned by the last statefncall.  This allows the JavaScript
  # side to find the actual same object that was saved last time.
  # (without which, anything involving semi-complex objects whose
  # state changes would fail)
  module StateFnCall
	def method_missing sym, *args
	  # Send our request (function/object name, arguments) and state 
	  # from last time.
	  $swiftest_calls ||= Hash.new(0)
	  $swiftest_calls[sym] += 1
	  
	  result, state = @swiftest.send_command("state-fncall", @statefncall, sym, *args)

	  # Basic types don't need proxying, since they're not going to
	  # hide anything useful in JavaScript that needs re-referencing.
	  unless [Numeric, String, TrueClass, FalseClass, NilClass].any? {|c| c === result}
		class << result
		  include StateFnCall
		end

		# Copy the swiftest object along, as well as the state for
		# this object.
		result.swiftest = @swiftest
		result.statefncall = state
	  end

	  # Return the new object, possibly proxified with state preserved.
	  result
	end

	attr_accessor :statefncall
	attr_accessor :swiftest
  end

  # A valueless object used to kick off JavaScript proxying
  # with a function call or object traversal.
  class StateFnCaller
	def initialize(swiftest)
	  @swiftest = swiftest
	  @statefncall = false
	end

	include StateFnCall
  end

  #   Represents a JavaScript complex object of any value 
  # (including anonymous objects).  It returns a plain integer
  # for its escape, which causes a backreference to be used
  # when sent as a top-level argument.
  #   Always ends up having StateFnCall mixed in.
  class StateObject
	def initialize(type)
	  @type = type
	end

	def inspect
	  "#<#{self.class.name} of type #@type>"
	end

	def [](prop)
	  self.send prop
	end

	def javascript_escape
	  @statefncall
	end

	attr_reader :type
  end

  #   When called with a block, just evaluates the path the
  # block would create, and gets the client to execute it all
  # at once.
  #   Without, it returns a new StateFnCaller, which acts as
  # a viral JavaScript proxy, returning objects (or proxy objects
  # for more complex ones) when calls or traversals are made.
  def fncall(&block)
	if block
	  # args ignored here, note.
	 
	  path_ctor = FakeEvalPath.new.instance_eval &block
	  send_command "fncall", path_ctor.path
	else
	  StateFnCaller.new self
	end
  end

  # So you can do swiftest.top.window.... etc.
  alias top fncall

  def manual_pass?
	recv_bool
  end
end

# vim: set sw=2:
