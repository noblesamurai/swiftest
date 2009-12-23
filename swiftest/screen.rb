class SwiftestScreen
  class ScreenDescriptor
	def initialize(screen)
	  @screen = screen
	  @metaklass = (class << @screen; self; end)
	end

	def current_when &code
	  @metaklass.send :define_method, :current?, &code
	end

	# Creates a method in this class by the name sym
	# which adds a given method name to the screen, using
	# a certain class for its values.
	def self.link_item_class(sym, klass)
	  define_method(sym) do |nsym, jq|
		@metaklass.send :define_method, nsym do 
		  instance_variable_get("@#{nsym}")
		end
		@screen.instance_variable_set "@#{nsym}", klass.new(@screen, jq)
	  end
	end
	
	class TextField
	  def initialize(screen, jq); @screen, @jq = screen, jq; end

	  def value; @screen.top.jQuery(@jq).val; end 
	  def value=(new_val); @screen.top.jQuery(@jq).val(new_val); end
	end

	class Checkbox
	  def initialize(screen, jq); @screen, @jq = screen, jq; end

	  def checked; @screen.top.jQuery(@jq).attr('checked'); end
	  def checked=(new_val); @screen.top.jQuery(@jq).attr('checked', new_val); end
	end

	class Button
	  def initialize(screen, jq); @screen, @jq = screen, jq; end

	  def click; @screen.top.jQuery(@jq).click; end
	end

	link_item_class :text_field, TextField
	link_item_class :checkbox, Checkbox
	link_item_class :button, Button
  end

  def self.describe_screen(description, &block)
	screen = SwiftestScreen.new(description)

	ScreenDescriptor.new(screen).instance_eval &block

	@@screens ||= []
	@@screens << screen

	screen
  end

  def self.screens
	@@screens
  end

  def inspect
	"<#{self.class.name}: #{@description}>"
  end

  attr_accessor :top
  attr_accessor :description

  protected :initialize

  def initialize(description)
	@description = description
  end
end
