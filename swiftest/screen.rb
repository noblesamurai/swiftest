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

	class JQueryAccessibleField
	  def initialize(screen, jq); @screen, @jq = screen, jq; end
	  def found?; locate.length > 0; end

	  protected
	  def locate; @screen.locate(@jq); end
	end
	
	class TextField < JQueryAccessibleField
	  def initialize(*args); super; end

	  def value; locate.val; end 
	  def value=(new_val); locate.val(new_val); end
	end

	class Checkbox < JQueryAccessibleField
	  def initialize(*args); super; end

	  def checked; locate.attr('checked'); end
	  def checked=(new_val); locate.attr('checked', new_val); end
	end

	class Button < JQueryAccessibleField
	  def initialize(*args); super; end

	  def click; locate.click; end
	end

	link_item_class :text_field, TextField
	link_item_class :checkbox, Checkbox
	link_item_class :button, Button

	def dialog sym, description, &block
	  dialog_screen = SwiftestDialogScreen.new(description)
	  DialogDescriptor.new(dialog_screen).instance_eval &block

	  @metaklass.send :define_method, sym do
		instance_variable_get("@#{sym}")
	  end
	  @screen.instance_variable_set "@#{sym}", dialog_screen

	  SwiftestScreen.add_screen(dialog_screen)
	end
  end

  class DialogDescriptor < ScreenDescriptor
	def show &block
	  @metaklass.send :define_method, :show, &block
	end

	def document &block
	  @metaklass.send :define_method, :document, &block
	end
  end

  def self.add_screen(screen)
	@@screens ||= []
	@@screens << screen
	screen
  end

  def self.describe_screen(description, &block)
	screen = SwiftestScreen.new(description)
	ScreenDescriptor.new(screen).instance_eval &block

	add_screen(screen)
  end

  def self.screens
	@@screens
  end

  def locate(jq)
	top.jQuery(jq)
  end

  def inspect
	"<#{self.class.name}: #{@description}>"
  end

  # the top accessor may be used internally - e.g. by current_when's delegate.
  # it's set by SwiftestEnvironment#init_screens
  attr_accessor :top
  attr_accessor :description

  protected :initialize

  def initialize(description)
	@description = description
  end
end

class SwiftestDialogScreen < SwiftestScreen
  def locate(jq)
	top.jQuery(document).find(jq)
  end
end

