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
        init_screens
        switch_screen MainMenuScreen
      end
    end

### screens

A **screen** is the main helper in _swiftest_. Using `SwiftestScreen.describe_screen`, you tell _swiftest_ what objects are available on that screen, where to find them, and how to know if that screen is really the one that's being shown:

    MainMenuScreen = SwiftestScreen.describe_screen("the main menu") do
      text_field :message, "#message input[name='destination']"
      button :show_message, "#message button" {|button| button.text == "Show"}

      check_box :show_at_startup, "input#startup-show"

      current_when do
        top.jQuery("#mainmenu").is(":visible")
      end
    end

Screens' benefits are derived from the DRY principle - if you're only describing the location of any given element in one place, then later when it changes, your tests are all fixed with a single change - instead of changing every test.

Internally, their elements are selected using jQuery selectors and arbitrary code disambiguators - helpful if a regular selector cannot give you the granularity you need (above, we're finding a button based on its actual textual content, as in `<button>Show</button>`). Here's how we use the code to do an RSpec-like test:

    class << self
      include MyEnvironment
    end

    @swiftest = Swiftest.new("my_app.xml")
    @swiftest.start

    environment_initialize

    @screen.show_at_startup.checked = true

    @screen.show_message.click
    @screen.message.value.should == "Just kidding!"

## Cucumber

[Cucumber](http://cukes.info) lets you write plain-English tests for BDD which make sense. Check it out.

    Feature: clicky buttons
      In order to click buttons,
      clicky buttons should be able to
      be clicked
      by people wishing to click buttons.

      Background:
        Given the application is open

      Scenario:
        Given the user sees the main menu
        When the user clicks the show message button
        Then the message text field should contain the value "Just kidding!"

Above is a highly unlikely scenario. Here's how we'd write some Cucumber with _swiftest_ to make it run:

    Given /^the application is open$/ do
      class << self
        include MyEnvironment
      end

      # use newOrRecover to not re-open the application for every scenario
      @swiftest = Swiftest.newOrRecover("my_app.xml")

      if not @swiftest.started?
        @swiftest.start
        environment_initialize
      end
    end

The Background is executed before every scenario - hence, we protect against reopening the AIR application again and again by using `newOrRecover`. Alternatively, you may wish to close and re-open the application for every scenario to ensure no state carries over (keeping in mind that scenarios should always work independently of each other).

    Transform /^the ([A-Za-z ]+) (?:button|text field)$/ do |field_name|
      @screen.send(field_name.downcase.gsub(' ', '_'))
    end

This Transform will help us later on, by translating a matched part of text like "the clicky button" into (hopefully) the actual button called `clicky` on `@screen`.

    Given /^the user sees the main menu$/ do
      switch_screen MainMenuScreen
    end

It's trivial to use a transform for the above rule, too, to make a generic helper to ensure a given screen is being shown.

Note that `switch_screen` cannot actually cause your program to move from one screen to another - it only changes the @screen object, and ensures that the given screen is indeed the one being displayed.  You will probably need special logic to move the program from one state to another if it's unpredictable from where you'll be encountering scenarios.

    When /^the user clicks (the [A-Za-z ]+ button)$/ do |button|
      button.click
    end

Here's where the transform magic takes over. Cucumber tries running capture groups in statements against each of the Transform statements - if one matches, that gets applied to the text before being returned to your block.

In this case, the capture group in "the user clicks ..." matches perfectly the Transform statement before, and hence the value of `button` will be the field on `@screen` which matches.

    Then /^(the [A-Za-z ]+ text field) should contain the value "([^"]+)"$/ do |text_field, value|
      text_field.value.should == value
    end

Hopefully this is self-explanatory. The first capture group again matches the Transform, and we get a real field out of `text_field`, whose value is compared to the plain text capture `value` with an RSpec assert (which comes with Cucumber).

## Contributors

 - [Arlen Cuss](http://github.com/celtic)
 - [You?](http://github.com/celtic/swiftest/fork) (click to fork)

## License

Copyright 2010 Arlen Cuss

Swiftest is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

Swiftest is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with Swiftest.  If not, see http://www.gnu.org/licenses/.

