
class String
  def javascript_escape
	"\"#{self.gsub('"', '\"')}\""
  end
end

module SwiftestCommands
  def alert(msg)
	eval("alert(" + msg.javascript_escape + ");")
  end

  def eval(js)
	puts "Eval: #{js}"
  end
end

