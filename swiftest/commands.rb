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

  def fncall(*args, &block)
	if block
	  # args ignored here, note.
	 
	  path_ctor = FakeEvalPath.new.instance_eval &block
	  send_command "fncall", path_ctor.path
	else
	  # RESUME here
	end
  end

  def jQuery(*args)
	fncall.jQuery(*args)
  end
end

