require 'swiftest/screen'

module SwiftestEnvironment
  # To be called after all SwiftestScreen (and derived) instances
  # are set up.  Each instance is given a reference to 'top' (which
  # this environment knows about)
  def init_screens
	SwiftestScreen.screens.each {|screen| screen.top = top}
  end

  # Switches to the given screen (i.e. just sets @screen to it),
  # asserting that it's current.
  def switch_screen(screen)
	if not screen.current?
	  top.alert("failed to switch_screen to #{screen.description} - not current")
	  exit
	end

	@screen = screen
  end

  # Convenience pass-through to the Swiftest object.
  def top(*args, &block)
	@swiftest.top(*args, &block)
  end

  # Convenience jQuery method (=> @swiftest.top.jQuery)
  def jQuery(*args, &block)
	top.jQuery(*args, &block)
  end
end

