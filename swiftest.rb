require 'rubygems'
require 'hpricot'

require 'swiftest/commands'

class Swiftest
  class AlreadyStartedError < StandardError; end
  include SwiftestCommands

  def initialize(path)
	@descriptor_path = path
	@relative_dir = File.dirname(@descriptor_path)

	@descriptor_xml = File.read(@descriptor_path)

	descriptor = Hpricot.XML(@descriptor_xml)
	@id = (descriptor/"application > id").text
	@content_file = (descriptor/"application > initialWindow > content").inner_html
  end

  # Bootstrap the application.
  def start
	raise AlreadyStartedError if @started
	STDERR.puts "starting Swiftest"
	
	@new_content_file = "#@content_file.swiftest.html"
	# We make a copy of the initial page and drop some JavaScript in at the end.
	FileUtils.cp "#@relative_dir/#@content_file", "#@relative_dir/#@new_content_file"

	File.open("#@relative_dir/#@new_content_file", "a") do |html|
	  html.puts <<-EOS
		<script>
		  alert("Slightly modified!");
		</script>
	  EOS
	end


	# Make a new copy of the descriptor to point to a new initial page.
	@new_descriptor_file = "#@descriptor_path.swiftest.xml"
	File.open(@new_descriptor_file, "w") do |xmlout|
	  descriptor = Hpricot.XML(@descriptor_xml)
	  (descriptor/"application > initialWindow > content").inner_html = @new_content_file
	  xmlout.puts descriptor
	end

	@pipe, @started = IO.popen("adl #@new_descriptor_file 2>&1", "w+"), true
	p @pipe.read
	Process.waitpid(@pipe.pid)
	cleanup
  end

  def cleanup
	STDERR.puts "! not doing cleanup"
	return

	File.unlink @new_descriptor_file rescue true
	File.unlink "#@relative_dir/#@new_content_file" rescue true
  end
end

