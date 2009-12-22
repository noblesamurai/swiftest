require 'swiftest/jsescape'

module SwiftestCommands
  def alert(msg)
	self.safeeval "alert(#{msg.javascript_escape});"
  end

  def safeeval(js)
	send_command "safeeval", js
  end

  class FakeEvalPath
	def initialize; @path = []; end

	def method_missing(sym, *args)
	  @path << [sym, args]
	  self
	end

	attr_reader :path
  end

  module StateFnCall
	def method_missing sym, *args
	  result, state = @swiftest.send_command("state-fncall", @statefncall, sym, args)

	  class << result
		include StateFnCall
	  end
	  result.swiftest = @swiftest
	  result.statefncall = state

	  result
	end

	attr_accessor :statefncall, :swiftest
  end

  class StateFnCaller
	def initialize(swiftest, state=false)
	  @swiftest = swiftest
	  @statefncall = state
	end

	include StateFnCall
  end

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

	attr_reader :type
  end

  def fncall(*args, &block)
	if block
	  # args ignored here, note.
	 
	  path_ctor = FakeEvalPath.new.instance_eval &block
	  send_command "fncall", path_ctor.path
	else
	  StateFnCaller.new self
	end
  end

  # So you can do swiftest.top.window.... etc.
  alias :top :fncall
end

