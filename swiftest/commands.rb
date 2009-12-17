
class String
  def javascript_escape
	"\"#{self.gsub('"', '\"')}\""
  end
end

module SwiftestCommands
  def alert(msg)
	self.eval "alert(#{msg.javascript_escape});"
  end

  def eval(js)
	r = send_command "eval", js
	puts "Eval: #{js} - result: #{r.inspect}"
  end
end

