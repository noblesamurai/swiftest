# swiftest
##### <span style="color: #333">a platform for automating HTML AIR applications</span> 

## introduction

_swiftest_ is a platform written in Ruby for automating Adobe AIR applications which use HTML and JavaScript for their UI. Its primary use case is in **testing**.

_swiftest_ is **not** a testing framework. One uses _swiftest_ **to provide the connection** to your AIR application, which you then instrument in your tests. We suggest [Cucumber](http://cukes.info) for writing your tests.

In addition to the ability to make arbitrary JavaScript calls without encountering the dread sandbox violation warning, _swiftest_ provides a set of methods and classes which ease in describing and abstracting away the details of the UI of your program, allowing you to automate and test it with ease.

## method

On startup, _swiftest_ doctors a copy of the base file of your AIR app, injecting [the JavaScript which receives commands and executes them](http://github.com/celtic/swiftest/blob/master/inject.js#L159) in the context of your application.

It then waits for the AIR application to connect back to itself, and then automation is ready to go.

You can issue commands directly to the resulting `Swiftest` object using `fncall` (aliased to `top`):

    swiftest.fncall.alert "Hello, world!"

The above translates to calling `top.alert("Hello, world!")` in JavaScript land, something you'd have trouble doing normally in a sandboxed environment (without a lot of passing data back and forth.

A more complex example:
    
    def jQuery(*args); swiftest.fncall.jQuery(*args); end

    jQuery("form").eq(2).find("button#my_button").click

Now we're talking. _swiftest_ is geared towards using jQuery in your AIR app - it presumes you already have it included - but the actual points of contact are well factored, and it should be trivial to add support for another library. (Please do!)

The above code is equivalent to performing `top.$("form").eq(2).find("button#my_button").click()`.

A final example of base-level _swiftest_:

    iframe = jQuery("iframe#my_app").get(0)  # get the DOM object
    jQuery("textarea#my_sub_element", iframe.contentDocument).text("Go home!")

## abstraction

While using direct calls like the above is fine and well, it doesn't provide for much abstraction of the application's details. Robust tests are well factored, and _swiftest_ saves you the effort by providing a system that (hopefully) makes sense for AIR applications.

### environments

An **environment** encapsulates general data and behaviour that apply to the lifetime of your application. This includes what **screen** is current (we'll talk more about those later).

An environment also initialises the application, putting it into a state ready for use (in say, testing), and provides helper functions to the screens.

    module MyEnvironment
      include SwiftestEnvironment

      def environment_initialize
        super

        switch_screen MainMenuScreen
      end
    end

### screens

A **screen** is the main helper in _swiftest_. Using `SwiftestScreen.describe_screen`, you tell _swiftest_ what objects are available on that screen, and where to find them:

    MainMenuScreen = SwiftestScreen.describe_screen("the main menu") do
      text_field :new_project_name, "#new_project input[name='name']"
      button :new_project_create, "#new_project button" {|button| button.text == "Create"}
      
      button :load_project, "#load_project button"

      check_box :show_at_startup, "input#startup-show"
    end

Screens' benefit are derived from the DRY principle - if you're only describing the location of any given element in one place, then later when it changes, your tests are all fixed with a single change - instead of changing every test.

Internally, their elements are selected using jQuery selectors and arbitrary code disambiguators - helpful if a regular selector cannot give you the granularity you need (above, we're finding a button based on its actual textual content, as in `<button>Create</button>`). Here's how we use the code:

    class << self
      include MyEnvironment
    end

    @swiftest = Swiftest.new("my_app.xml")
    @swiftest.start

    environment_initialize

    @screen.show_at_startup.checked = true

    @screen.new_project_name.value = "My Project"
    @screen.new_project_create.click

