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

  def fakeeval(&block)
	path_ctor = FakeEvalPath.new.instance_eval &block
	send_command "fakeeval", path_ctor.path
  end
end

