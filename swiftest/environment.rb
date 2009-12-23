require 'swiftest/screen'

module SwiftestEnvironment
  def init_screens
	SwiftestScreen.screens.each {|screen| screen.top = top}
  end

  def switch_screen(screen)
	if not screen.current?
	  top.alert("failed to switch_screen to #{screen.description} - not current")
	  exit
	end

	@screen = screen
  end
end

