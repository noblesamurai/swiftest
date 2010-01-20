# A screen which gains various methods once described.
# (created by describe_screen)  The process of *how* it gains
# its methods is described in further detail below.
class SwiftestScreen

  # Instances of ScreenDescriptor are the context for evaluation
  # of the block given to describe_screen.  (i.e. this provides
  # the DSL for describing screens)
  class ScreenDescriptor
	def initialize(screen)
	  @screen = screen
	  @metaklass = (class << @screen; self; end)
	end

	# "This screen is current when <some code>."  Maps given
	# block purely to be the function :current? on the screen.
	def current_when &code
	  @metaklass.send :define_method, :current?, &code
	end

	#   I had disagreements with naming all the parameters and block
	# params 'sym' and 'nsym' (and so on) here, so I've tried to make
	# them more explanatory.
	#   link_item_class creates a new method constructor method 
	# (right?).  It goes by the given name, and when called, adds a
	# property on the resulting screen (by some given name "field_name")
	# which points to a new single instance of the class "klass".
	#
	# Example:
	#     link_item_class :text_field, TextField
	#
	# We can now use the method "text_field" when describing a screen:
	#     text_field :username, "input#username"
	#
	# Now a property (method) is defined on that screen called 'username',
	# which is a new TextField with the given selector.
	def self.link_item_class(constructor_name, klass)
	  define_method(constructor_name) do |field_name, selector|
		@metaklass.send :define_method, field_name do 
		  instance_variable_get("@#{field_name}")
		end
		@screen.instance_variable_set "@#{field_name}", klass.new(@screen, selector)
	  end
	end

	#   Base class for any field accessible by jQuery.  Stores
	# the screen and the selector.  Field types being used with
	# link_item_class should inherit this class and use the same
	# initialize signature.
	#   It provides a locate method for subclasses which just
	# defers to the screen.
	class JQueryAccessibleField
	  def initialize(screen, selector); @screen, @selector = screen, selector; end
	  def found?; locate.length > 0; end

	  class << self
		protected
		# Unfortunately, require_found_for throws away blocks!
		# Ruby 1.8's define_method doesn't allow blocks through.
		# (not even with yield/block_given?)
		def require_found_for *methods
		  methods.each do |fn|
			real_method = instance_method(fn)
			define_method(fn) do |*a|
			  raise "Cannot find element on page" if not found?
			  real_method.bind(self).call *a
			end
		  end
		end
	  end

	  def blur; locate.blur; end
	  def enabled?; !locate.attr("disabled"); end
	  def enabled=(val); locate.attr("disabled", !val); end
	  def disabled?; !enabled?; end
	  def disabled=(val); enabled = !val; end

	  require_found_for :blur, :enabled?, :enabled=, :disabled?, :disabled=

	  protected
	  def locate; @screen.locate(@selector); end
	end
	
	class TextField < JQueryAccessibleField
	  def initialize(*args); super; end

	  def value; locate.val; end 
	  def value=(new_val); locate.val(new_val); locate.change; end

	  require_found_for :value, :value=
	end

	class CheckBox < JQueryAccessibleField
	  def initialize(*args); super; end

	  def checked?; locate.attr('checked'); end
	  def checked=(new_val); locate.attr('checked', new_val); locate.change; end

	  require_found_for :checked?, :checked=
	end

	class Button < JQueryAccessibleField
	  def initialize(*args); super; end

	  def click; locate.click; end

	  require_found_for :click
	end

	class SelectBox < JQueryAccessibleField
	  # Glorified TextField?
	  def initialize(*args); super; end

	  def value; locate.val; end
	  def value=(new_val); locate.val(new_val); locate.change; end

	  require_found_for :value, :value=
	end

	link_item_class :text_field, TextField
	link_item_class :check_box, CheckBox
	link_item_class :button, Button
	link_item_class :select_box, SelectBox

	#   Defines a dialog by the name provided (sym).
	#   Dialogs' contents are defined just like screens - they're
	# actually subclasses (both the Screen class and Descriptor),
	# so they share all the same features, as well as some extra
	# functionality (indicating how to open them, etc.).
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

  # Adds two extra methods for use when describing a dialog;
  # one which describes how to show the dialog, and one for
  # describing how to get the document object out of it.
  class DialogDescriptor < ScreenDescriptor
	def show &block
	  @metaklass.send :define_method, :show, &block
	end

	def document &block
	  @metaklass.send :define_method, :document, &block
	end
  end

  # Adds a given screen to the internal listing of all screens.
  def self.add_screen(screen)
	@@screens ||= []
	@@screens << screen
	screen
  end

  # Starts describing a new screen.  The actual description process
  # is handled by ScreenDescriptor.
  def self.describe_screen(description, &block)
	screen = SwiftestScreen.new(description)
	ScreenDescriptor.new(screen).instance_eval &block

	add_screen(screen)
  end

  def self.screens
	@@screens
  end

  # Screens know how to locate objects in themselves given a 
  # selector.  This is overridable so that, e.g., dialogs can
  # evaluate that selector within the context of the dialog 
  # instead.
  def locate(selector)
	top.jQuery(selector)
  end

  def inspect
	"<#{self.class.name}: #{@description}>"
  end

  # The 'top' accessor may be used internally - e.g. by
  # current_when's delegate.
  #   It's set by SwiftestEnvironment#init_screens.
  attr_accessor :top
  attr_accessor :description

  protected :initialize

  def initialize(description)
	@description = description
  end
end

# Dialog screens only differ from screens in that their
# object locating mechanism starts from the dialog's document,
# instead of the very top level.
class SwiftestDialogScreen < SwiftestScreen
  def locate(selector)
	top.jQuery(document).find(selector)
  end
end

# vim: set sw=2:
