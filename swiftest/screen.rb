# Copyright 2010 Arlen Cuss
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

# A screen which gains various methods once described.
# (created by describe_screen)  The process of *how* it gains
# its methods is described in further detail below.
class SwiftestScreen
  # Raised when no element was found
  class ElementNotFoundError < StandardError; end

  # Instances of ScreenDescriptor are the context for evaluation
  # of the block given to describe_screen.  (i.e. this provides
  # the DSL for describing screens)
  class ScreenDescriptor
	def initialize(screen)
	  @screen = screen
	  @metaklass = (class << @screen; self; end)
	end

	# "This screen is current when <some code>."  Maps given
	# block purely to be the function +current?+ on the screen.
	def current_when &code
	  @metaklass.send :define_method, :current?, &code
	end

	#   I had disagreements with naming all the parameters and block
	# params 'sym' and 'nsym' (and so on) here, so I've tried to make
	# them more explanatory.
	#   +link_item_class+ creates a new method constructor method 
	# (right?).  It goes by the given name, and when called, adds a
	# property on the resulting screen (by some given name +field_name+)
	# which points to a new single instance of the class +klass+.
	#
	# Example:
	#     link_item_class :text_field, TextField
	#
	# We can now use the method "text_field" when describing a screen:
	#     text_field :username, "input#username"
	#
	#   Now a property (method) is defined on that screen called
	# 'username', which is a new TextField with the given selector.
	#
	#   Unfortunately, due to the constructor function being created
	# needing to be able to take blocks, we cannot use +define_function+,
	# and instead need to do an ugly eval.
	#   As a result, much of the logic of how this works has been moved
	# into +link_item_class_constructor+.
	def self.link_item_class(constructor_name, klass)
	  [constructor_name, constructor_name.to_s + "_array"].each do |ctor|
		class_eval <<-EOE
		  def #{ctor}(field_name, selector, &helper)
			link_item_class_constructor(#{klass}, field_name, selector, &helper)
		  end
		EOE
	  end
	end

	#   Helper class for +link_item_class+ - the +helper+ param is
	# evaluated in the context of this, allowing subobjects (as per
	# +ScreenDescriptor+), and a disambiguator.
	class LinkItemHelperDescriptor < ScreenDescriptor
	  def disambiguate &disambiguator
		@screen.disambiguator = disambiguator
	  end
	end

	#   This method is called every time the constructor created by
	# +link_item_class+ is called.
	#   It receives the class of the field type to be created, the name
	# of the field to make, and the jQuery selector which points to
	# the object in the AIR app which this field corresponds to.
	#   Optionally, a block can be supplied which will be evaluated in
	# the context of a +LinkItemHelperDescriptor+, itself being a
	# +ScreenDescriptor+.  This may specify subobjects, or a disambiguator.
	def link_item_class_constructor klass, field_name, selector, &helper
	  target = klass.new(@screen, selector)
	  LinkItemHelperDescriptor.new(target).instance_eval(&helper) if helper

	  @screen.instance_variable_set "@#{field_name}", target
	  @metaklass.send :define_method, field_name do 
		instance_variable_get("@#{field_name}")
	  end
	end

	# Proxy for +JQueryAccessibleField+ which sends the call
	# on to the underlying implementation, specifying the correctly
	# obtained element using its obtainer.
	class IndexProxy
	  def initialize(target, obtainer, index)
		@target, @obtainer, @index = target, obtainer, index
	  end

	  def method_missing(sym, *args, &block)
		# Call the implementation of the requested method, specifying
		# the element to be the one obtained with our index.
		@target.send "impl_#{sym}", @obtainer.call(@index), *args, &block
	  end
	end

	#   Base class for any field accessible by jQuery.  Stores
	# the screen, selector and disambiguator.  Field types being
	# used with +link_item_class+ should inherit this class,
	# define the getters/setters, and use obtain_function to provide
	# the non-implementation versions.
	class JQueryAccessibleField < SwiftestScreen
	  def initialize(screen, selector, &disambiguator)
		@screen, @selector, @disambiguator = screen, selector, disambiguator
	  end

	  def [](index)
		IndexProxy.new(self, method(:obtain), index)
	  end

	  # impl_* methods should use their element, always. If they don't
	  # (i.e. because you're invoking another method on JQAF), you're
	  # doing it wrong, because you should only ever invoke other impl_
	  # methods which *take* element.
	  #   Otherwise you're throwing it away, and that is contrary to
	  # the whole point.
	  #   This (above) is the general method to see if you're going about
	  # something the right way; hence the ugliness with +impl_disabled=+
	  # using send to give +impl_enabled=+ two arguments.

	  def impl_length(element); element.length; end
	  def impl_found?(element); element.length > 0; end

	  def impl_blur(element); element.blur; end
	  def impl_enabled?(element); !element.attr("disabled"); end
	  def impl_enabled=(element, val); element.attr("disabled", !val); end
	  def impl_disabled?(element); !impl_enabled?(element); end
	  def impl_disabled=(element, val); send(:impl_enabled=, element, !val); end
	  def impl_text(element); element.text; end

	  # Creates functions which call their impl_ variants with
	  # a plain obtained element.
	  def self.obtain_function *names
		names.each do |name|
		  define_method(name) do |*args|
			send("impl_#{name}", obtain, *args)
		  end
		end
	  end

	  obtain_function :length, :found?
	  obtain_function :blur, :enabled?, :enabled=, :disabled?, :disabled=, :text

	  attr_accessor :disambiguator

	  protected
	  def element_locate(selector)
		obtain.find(selector)
	  end

	  private
	  def obtain(index=nil)
		loc = @screen.locate(@selector, &@disambiguator)
		return loc unless index

		puts "INDEX time: #{index}"

		length = loc.length
		raise ElementNotFoundError, "index #{index} >= length #{length}" if index >= length
		loc.eq(index)
	  end
	end
	
	class TextField < JQueryAccessibleField
	  def impl_value(element); element.val; end 
	  def impl_value=(element, new_val); element.val(new_val).change; end

	  obtain_function :value, :value=
	end

	class CheckBox < JQueryAccessibleField
	  def impl_checked?(element); element.attr('checked'); end
	  def impl_checked=(element, new_val); element.attr('checked', new_val).change; end

	  obtain_function :checked?, :checked=
	end

	class Button < JQueryAccessibleField
	  def impl_click(element); element.click; end

	  obtain_function :click
	end

	class SelectBox < JQueryAccessibleField
	  # Glorified TextField?
	  def impl_value(element); element.val; end
	  def impl_value=(element, new_val); element.val(new_val).change; end

	  obtain_function :value, :value=
	end

	link_item_class :item, JQueryAccessibleField
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

  # locate runs this screen's element locator, then uses
  # the given disambiguator (if any) to narrow down which
  # item is returned.
  def locate(selector, &disambiguator)
	found = element_locate(selector)

	len = found.length
	raise ElementNotFoundError, "Locator found nothing for \"#{selector}\"" if len == 0

	if disambiguator
	  # Optimised for minimum number of calls into JavaScript.
	  (0...len).each do |i|
		feqi = found.eq(i)
		return feqi if feqi.instance_eval(&disambiguator)
	  end
	  raise ElementNotFoundError, "Disambiguator returned nothing while disambiguating \"#{selector}\""
	end

	found
  end

  # Screens know how to locate objects in themselves given a 
  # selector.  This is overridable so that, e.g., dialogs can
  # evaluate that selector within the context of the dialog 
  # instead.
  def element_locate(selector)
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
# element locating mechanism starts from the dialog's document,
# instead of the very top level.
class SwiftestDialogScreen < SwiftestScreen
  def element_locate(selector)
	top.jQuery(document).find(selector)
  end
end

# vim: set sw=2:
