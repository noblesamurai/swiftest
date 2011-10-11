# Copyright 2010 Noble Samurai
#  
# Swiftest is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#  
# Swiftest is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
# GNU General Public License for more details.
#  
# You should have received a copy of the GNU General Public License
# along with Swiftest.	If not, see <http://www.gnu.org/licenses/>.

# A screen which gains various methods once described.
# (created by describe_screen)	The process of *how* it gains
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

    # Just defines a function on the resulting object.	Uses
    # +define_function+, hence the resulting method unfortunately
    # can't take blocks.
    def define sym, &code
      @metaklass.send :define_method, sym, &code
    end

    #	I had disagreements with naming all the parameters and block
    # params 'sym' and 'nsym' (and so on) here, so I've tried to make
    # them more explanatory.
    #	+link_item_class+ creates a new method constructor method 
    # (right?).  It goes by the given name, and when called, adds a
    # property on the resulting screen (by some given name +field_name+)
    # which points to a new single instance of the class +klass+.
    #
    # Example:
    #	  link_item_class :text_field, TextField
    #
    # We can now use the method "text_field" when describing a screen:
    #	  text_field :username, "input#username"
    #
    #	Now a property (method) is defined on that screen called
    # 'username', which is a new TextField with the given selector.
    #
    #	Unfortunately, due to the constructor function being created
    # needing to be able to take blocks, we cannot use +define_function+,
    # and instead need to do an ugly eval.
    #	As a result, much of the logic of how this works has been moved
    # into +link_item_class_constructor+.
    def self.link_item_class(constructor_name, klass)
      class_eval <<-EOE
	if klass.ancestors.include? FlexibleArray
	  def #{constructor_name}(field_name, selector, &helper)
		link_item_class_constructor(#{klass}, #{constructor_name.to_s.inspect}, field_name, selector, true, &helper)
	  end
	else
	  def #{constructor_name}(field_name, selector, &helper)
		link_item_class_constructor(#{klass}, #{constructor_name.to_s.inspect}, field_name, selector, &helper)
	  end

	  def #{constructor_name}_array(field_name, selector, &helper)
		link_item_class_constructor(#{klass}, #{constructor_name.to_s.inspect}, field_name, selector, true, &helper)
	  end
	end
      EOE
    end

    #	Helper class for +link_item_class+ - the +helper+ param is
    # evaluated in the context of this, allowing subobjects (as per
    # +ScreenDescriptor+), and a disambiguator.
    class LinkItemHelperDescriptor < ScreenDescriptor
      def disambiguate &disambiguator
	@screen.disambiguator = disambiguator
      end

      def switch_to(where, &how)
	@screen.switch_to[where] = how
      end

      def visible_when(&w)
	@screen.visible_call = w
      end
    end

    # Exposes a hash as an array whose bounds can be set fairly
    # arbitrarily, undefined elements being setup by a given
    # initializer.  Passes through +method_missing+ calls to
    # to 'nil' item version, using the same initializer.
    class FlexibleArray
      def initialize(hash, initializer)
	@hash, @initializer = hash, initializer
	@klass_description = "#{initializer.call(nil).klass_description} array"
      end

      attr_reader :klass_description

      def method_missing sym, *args
	if @nil_item.nil?
	  @nil_item = @initializer.call(nil)
	  @nil_item.base_call = @base_call if @base_call

	  # For the sake of lists with possibly zero items,
	  # allow the locate call to return nil.
	  @nil_item.allow_nil = true
	end
	@nil_item.send sym, *args
      end

      def [](index)
	index = self.length + index if index < 0

	return @hash[index] if @hash.include? index
	@hash[index] = @initializer.call(index)
	@hash[index].base_call = @base_call if @base_call
	@hash[index]
      end

      def []=(index, value)
	index = self.length + index if index < 0

	@hash[index] = value
      end

      def each
	0.upto(self.length - 1) do |index|
	  yield self[index]
	end
      end

      attr_accessor :base_call

      include Enumerable
    end

    #	This method is called every time the constructor created by
    # +link_item_class+ is called.
    #	It receives the class of the field type to be created, the name
    # of the field to make, and the jQuery selector which points to
    # the object in the AIR app which this field corresponds to.
    #	Optionally, a block can be supplied which will be evaluated in
    # the context of a +LinkItemHelperDescriptor+, itself being a
    # +ScreenDescriptor+.  This may specify subobjects, or a disambiguator.
    def link_item_class_constructor klass, ctor_name, field_name, selector, array=false, &helper
      if not array
	target = klass.new(@screen, selector)
	LinkItemHelperDescriptor.new(target).instance_eval(&helper) if helper
      elsif klass.ancestors.include? FlexibleArray
	target = klass.new({}, Proc.new {|sel=selector, index|
	  target = JQueryAccessibleField.new(@screen, sel, index)
	  LinkItemHelperDescriptor.new(target).instance_eval(&helper) if helper
	  target
	})
      else
	target = FlexibleArray.new({}, Proc.new {|index|
	  target = klass.new(@screen, selector, index)
	  LinkItemHelperDescriptor.new(target).instance_eval(&helper) if helper
	  target
	})
      end

      cta = @screen.type_arrays[ctor_name.to_sym]
      cta << target
      @screen.type_arrays[ctor_name.to_sym] = cta

      @screen.instance_variable_set "@#{field_name}", target
      @metaklass.send :define_method, field_name do 
	instance_variable_get("@#{field_name}")
      end

      @screen.instance_variable_get("@#{field_name}")
    end

    # Looks like a hash while letting users get and set
    # attributes of a JQueryAccessibleField.
    class JQueryAttrs
      def initialize(obtainer)
	@obtainer = obtainer
      end

      def [](attr)
	attr = @obtainer.call.attr(attr)
	attr.is_a?(String) ? attr.force_encoding('utf-8') : attr
      end

      def []=(attr, val)
	@obtainer.call.attr(attr, val)
      end
    end

    #	Base class for any field accessible by jQuery.	Stores
    # the screen, selector and disambiguator.  Field types being
    # used with +link_item_class+ should inherit this class,
    # define the getters/setters, and use obtain_function to provide
    # the non-implementation versions.
    class JQueryAccessibleField < SwiftestScreen
      @klass_description = "generic field"

      def initialize(screen, selector, index=nil, &disambiguator)
	@screen, @selector, @index, @disambiguator = screen, selector, index, disambiguator
	@switch_to, @base_call, @allow_nil = {}, nil, false

	@visible_call = nil
	super(nil)
      end

      def [](index)
	raise "I wasn't declared as an array!"
      end

      def jquery_object; obtain; end
      def dom_node(index=0); obtain.get(index); end

      def length; obtain.length; end
      def found?; obtain.length > 0; end
      def visible?
	begin
	  @visible_call ? @screen.instance_eval(&@visible_call) : obtain.is(":visible")
	rescue ElementNotFoundError
	  false
	end
      end

      def blur; obtain.blur; end
      def enabled?; !disabled?; end
      def enabled=(val); disabled = !val; end
      def disabled?; attrs["disabled"]; end
      def disabled=(val); attrs["disabled"] = val; end
      def text; obtain.text.force_encoding('utf-8'); end
      def html; obtain.html.force_encoding('utf-8'); end
      def html=(new_val); obtain.html(new_val).change; end
      def click(shift=false)
	if shift
	  e = top.jQuery.Event("click")
	  e.shiftKey = shift
	  obtain.trigger(e)
	else
	  obtain.click
	end
      end
      def mousedown
	obtain.mousedown
      end
      def focus; obtain.focus; end
      def parent; obtain.parent; end
      def closest(*args); obtain.closest(*args); end
      def change; obtain.change; end
      def trigger(*args); obtain.trigger(*args); end
      def find(*args); obtain.find(*args); end
      def siblings(*args); obtain.siblings(*args); end
      def absolute_position
	    off = obtain.offset
	    [off.left, off.top]
      end
      def height; obtain.height; end
      def width; obtain.width; end
      def tag; dom_node.tagName.downcase; end
      def has_class?(val); obtain.hasClass(val); end

      def keydown(which, shift=false)
	e = top.jQuery.Event("keydown")
	e.which = which
	e.shiftKey = shift

	keytarget.trigger(e)
      end

      # The active element in the same HTMLDocument as this element.
      def activeElement
	top.jQuery(dom_node.ownerDocument.activeElement)
      end

      def attrs; @attrs ||= JQueryAttrs.new(method(:obtain)); end
      def top; @screen.top; end

      def each; yield self; end

      def self.recurse_find_node_with_text(text, n)
	# TODO: generalise me (with a stop condition or something; recurse_find_node).
	# But where does it belong?
	return nil if n.childNodes.length.zero?

	s = n.firstChild
	st = s.nodeValue

	while st.nil? or st.index(text).nil?
	  r = recurse_find_node_with_text(text, s)
	  return r if r
	  break unless s.nextSibling
	  s = s.nextSibling
	  st = s.nodeValue
	end

	s if st and st.index(text)
      end

      attr_accessor :base_call
      attr_accessor :allow_nil
      attr_accessor :index
      attr_accessor :disambiguator

      attr_accessor :switch_to

      attr_accessor :visible_call

      attr_reader :selector

      def obtain
	loc = @screen.locate(@selector,
			     @base_call && @screen.instance_eval(&@base_call),
			     @allow_nil,
			     &@disambiguator)
	return loc unless @index

	loc.eq(@index)
      end

      protected
      def element_locate(selector, base=nil)
	if base
	  # Resets back to +base+ - not using our current 'state' (i.e.
	  # the location isn't at all relative to this JQAF)
	  base.jQuery(selector)
	else
	  obtain.find(selector)
	end
      end

      def keytarget
	obtain
      end
    end

    class Dialog < JQueryAccessibleField
      @klass_description = "dialog"
    end

    class Subscreen < JQueryAccessibleField; @klass_description = "subscreen"; end
    
    class TextField < JQueryAccessibleField
      @klass_description = "text field"

      def value; obtain.val.force_encoding('utf-8'); end 
      def value=(new_val); obtain.val(new_val).change; end
    end

    class CheckBox < JQueryAccessibleField
      @klass_description = "check box"

      def checked?; obtain.attr('checked'); end
      def checked=(new_val)
	obtain.attr('checked', new_val).change if checked? ^ new_val
      end
    end

    class RadioButton < CheckBox
      @klass_description = "radio button"
    end

    class Button < JQueryAccessibleField
      @klass_description = "button"
    end

    class SelectBox < JQueryAccessibleField
      @klass_description = "select box"

      def value; obtain.val.force_encoding('utf-8'); end
      def value=(new_val); obtain.val(new_val).change; end

      def value_text
	obtain.find("option[value=\"#{obtain.val}\"]").eq(0).text.force_encoding('utf-8')
      end

      def choose(val)
	opt = obtain.find("option:contains(#{val})")
	self.value = opt.val
	opt.attr('selected', 'selected')
      end
    end

    class TextArea < JQueryAccessibleField
      @klass_description = "text area"

      def value; obtain.val.force_encoding('utf-8'); end
      def value=(new_val); obtain.val(new_val).change; end
    end

    class HTMLArea < JQueryAccessibleField
      @klass_description = "rich-text editor"

      def value; obtain.text.force_encoding('utf-8'); end
      def value=(new_val); obtain.text(new_val).change; end

      def focus
	super
	node = obtain.find("p").get(0)
	node = obtain.get(0) if !node

	range = node.ownerDocument.createRange
	range.setStart(node, 0)
	range.setEnd(node, 0)

	sel = top.window.getSelection
	sel.removeAllRanges
	sel.addRange(range)
      end

      def get_text_node_containing(text)
	node = obtain.find(":contains(#{text.inspect})").get(0)
	node = obtain.parent.find(":contains(#{text.inspect})").get(0) if node.nil?
	JQueryAccessibleField.recurse_find_node_with_text(text, node) unless node.nil?
      end

      def select_text(text, seltype=:full)
	focus

	node = get_text_node_containing(text)
	raise "Text #{text.inspect} not found" if node.nil?

	node_text = node.nodeValue

	range = node.ownerDocument.createRange

	case seltype
	when :full
	  range.setStart(node, node_text.index(text))
	  range.setEnd(node, node_text.index(text) + text.length)
	when :start
	  range.setStart(node, node_text.index(text))
	  range.setEnd(node, node_text.index(text))
	when :end
	  #if node_text.index(text) + text.length == node_text.length
	    #range.setStartAfter(node)
	    #range.setEndAfter(node)
	  #else
	    range.setStart(node, node_text.index(text) + text.length)
	    range.setEnd(node, node_text.index(text) + text.length)
	  #end
	end

	sel = top.window.getSelection
	sel.removeAllRanges
	sel.addRange(range)

	obtain.click
      end

      def cursor_before(text)
	select_text text, :start
      end

      def cursor_after(text)
	select_text text, :end
      end

      def selected_text
	# TODO: verify the selection is within this node
	dom_node.ownerDocument.getSelection.toString
      end

      def select_p_containing(text)
	node = obtain.find("p:contains(#{text.inspect})").get(0)#.firstChild
	#node_text = node.nodeValue

	# raise "Text #{text.inspect} not found in node contents #{node_text.inspect}" if node_text.index(text).nil?

	range = node.ownerDocument.createRange
	range.selectNodeContents node
	#range.setStartBefore(node.firstChild)
	#range.setEndAfter(node.lastChild)

	sel = top.window.getSelection
	sel.removeAllRanges
	sel.addRange(range)
      end

      def delete_selected_text
	this = dom_node
	sel = this.ownerDocument.getSelection

	r = sel.getRangeAt(0).commonAncestorContainer
	r = r.parentNode while r.parentNode and not r.isEqualNode(this)
	raise "Selection not within this container" if not r.parentNode

	sel.deleteFromDocument
      end

      def select_all_text
	focus

	node = dom_node

	range = node.ownerDocument.createRange
	range.setStartBefore node
	range.setEndAfter node

	sel = top.window.getSelection
	sel.removeAllRanges
	sel.addRange range
      end
    end

    link_item_class :item, JQueryAccessibleField
    link_item_class :dialog, Dialog
    link_item_class :subscreen, Subscreen

    link_item_class :text_field, TextField
    link_item_class :check_box, CheckBox
    link_item_class :button, Button
    link_item_class :radio_button, RadioButton
    link_item_class :select_box, SelectBox
    link_item_class :text_area, TextArea
    link_item_class :html_area, HTMLArea

    def describe description
      @screen.description = description
    end

    def resolve_base base_call, &block
      ResolveBaseDescriptor.new(@screen, base_call).instance_eval &block
    end

    class ResolveBaseDescriptor
      def initialize(screen, base_call)
	@screen, @base_call = screen, base_call
	@real_descriptor = ScreenDescriptor.new(@screen)
      end

      def method_missing sym, *args, &block
	result = @real_descriptor.send(sym, *args, &block)
	result.base_call = @base_call if result.respond_to? :base_call=
	result
      end
    end

    #	Defines a window by the name provided (sym).
    #	Windows' contents are defined just like screens - they're
    # actually subclasses (both the Screen class and Descriptor),
    # so they share all the same features, as well as some extra
    # functionality (indicating how to open them, etc.).
    def window sym, name, &block
      window_screen = SwiftestWindowScreen.new(name)
      WindowDescriptor.new(window_screen).instance_eval &block

      @screen.instance_variable_set "@#{sym}", window_screen
      @metaklass.send :define_method, sym do
	instance_variable_get("@#{sym}")
      end

      SwiftestScreen.add_screen(window_screen)

      @screen.instance_variable_get "@#{sym}"
    end
  end

  # Adds two extra methods for use when describing a window;
  # one which describes how to show the window, and one for
  # describing how to get the document object out of it.
  class WindowDescriptor < ScreenDescriptor
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
  def self.describe_screen(name, &block)
    screen = SwiftestScreen.new(name)
    ScreenDescriptor.new(screen).instance_eval &block

    add_screen(screen)
  end

  def self.screens
    @@screens
  end

  # locate runs this screen's element locator, then uses
  # the given disambiguator (if any) to narrow down which
  # item is returned.
  def locate(selector, base=nil, allow_nil=false, &disambiguator)
    found = element_locate(selector, base)
    len = found.length

    if len == 0 and not allow_nil
      counter = 0
      while counter < 2 and len == 0
	sleep 0.2
	counter += 2
	found = element_locate(selector, base)
	len = found.length
      end

      raise ElementNotFoundError, "Locator found nothing for \"#{selector}\"#{base && ", with base #{base.inspect}"}" if len == 0
    end

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
  # selector.  This is overridable so that, e.g., windows can
  # evaluate that selector within the context of the window 
  # instead.
  def element_locate(selector, base=nil)
    if base
      base.jQuery(selector)
    else
      top.jQuery(selector)
    end
  end

  def inspect
    "<#{self.class.name}: #{@name}>"
  end

  @klass_description = "screen"
  def self.klass_description; @klass_description; end
  def klass_description; self.class.klass_description; end

  # The 'top' accessor may be used internally - e.g. by
  # current_when's delegate.
  #   It's set by SwiftestEnvironment#init_screens.
  attr_accessor :top
  attr_accessor :name, :description, :type_arrays

  protected :initialize

  def initialize(name)
    @name = name
    @type_arrays = Hash.new { Array.new }
  end
end

# Window screens only differ from screens in that their
# element locating mechanism starts from the window's document,
# instead of the very top level.
class SwiftestWindowScreen < SwiftestScreen
  @klass_description = "window"

  # XXX(arlen): this looks like it could be refactored into
  # SwiftestScreen#element_locate - maybe using resolve_base
  def element_locate(selector, base=nil)
    raise "SwiftestWindowScreen#element_locate given non-nil base" unless base.nil?
    top.jQuery(document).find(selector)
  end

  def visible?
    (document ? !top.jQuery(document).find(":visible").length.zero? : false)
  end
end

# vim: set sw=2 ts=8 noet:
