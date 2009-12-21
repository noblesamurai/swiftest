# This more-or-less converts Ruby data structures into JSON.

class String
  def javascript_escape
	"\"#{self.gsub('"', '\"').gsub("\\", "\\\\")}\""
  end
end

class Array
  def javascript_escape
	"[#{self.map {|el| el.javascript_escape}.join(", ")}]"
  end
end

class Hash
  def javascript_escape
	"{#{self.map {|k, v| "#{k.javascript_escape}: #{v.javascript_escape}"}.join(", ")}}"
  end
end

class Symbol
  def javascript_escape
	self.to_s.javascript_escape
  end
end

class Numeric; def javascript_escape; self.to_s; end; end
class TrueClass; def javascript_escape; self.to_s; end; end
class FalseClass; def javascript_escape; self.to_s; end; end
class NilClass; def javascript_escape; "null"; end; end

