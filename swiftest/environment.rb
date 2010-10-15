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

require File.join(File.dirname(__FILE__), 'screen')

module SwiftestEnvironment
  wait_for_switch = 20.0

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
	  begin
		Timeout.timeout(wait_for_switch) do
		  sleep 1.0
		  sleep 1.0 while @screen.current? if @screen
		end
		if not screen.current?
		  # Any other screen current?
		  raise "CONCLUSION: NO SCREEN IS CURRENT"
		end
	  rescue Timeout::Error
		raise "failed to switch_screen to #{screen.description} - not current"
	  end
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

