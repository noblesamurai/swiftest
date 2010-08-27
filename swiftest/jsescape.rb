# Copyright 2010 Noble Samurai
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

# This more-or-less converts Ruby data structures into JSON.

class String
  def javascript_escape
	"\"#{self.gsub("\\", "\\\\\\").gsub('"', '\"').gsub("\n", "\\n")}\""
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

