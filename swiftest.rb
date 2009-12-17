require 'rubygems'
require 'hpricot'
require 'socket'

require 'swiftest/commands'

SWIFTEST_BASE = File.dirname(__FILE__)

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

	@server = TCPServer.open(0)
	@port = @server.addr[1]
	
	@new_content_file = "#@content_file.swiftest.html"
	# We make a copy of the initial page and drop some JavaScript in at the end.
	FileUtils.cp File.join(@relative_dir, @content_file), File.join(@relative_dir, @new_content_file)

	File.open(File.join(@relative_dir, @new_content_file), "a") do |html|
	  html.puts <<-EOS
		<script type="text/javascript">
		  var SWIFTEST_PORT = #@port;
		</script>
		<script type="text/javascript" src="inject.swiftest.js"></script>
	  EOS
	end

	# Actually drop inject.js in under the right name.
	FileUtils.cp File.join(SWIFTEST_BASE, "inject.js"), File.join(@relative_dir, "inject.swiftest.js")

	# Make a new copy of the descriptor to point to a new initial page.
	@new_descriptor_file = "#@descriptor_path.swiftest.xml"
	File.open(@new_descriptor_file, "w") do |xmlout|
	  descriptor = Hpricot.XML(@descriptor_xml)
	  (descriptor/"application > initialWindow > content").inner_html = @new_content_file
	  xmlout.puts descriptor
	end

	# Open up the modified descriptor with ADL.
	@pipe, @started = IO.popen("adl #@new_descriptor_file 2>&1", "r+"), true

	# Start a thread to pipe through output from adl
	@reader_thread = Thread.start do 
	  while true
		data = @pipe.read(1024)
		break unless data
		puts data
	  end
	  Process.waitpid(@pipe.pid)
	  STDERR.puts "need to kill this ship!"
	  cleanup
	end

	# Block for the client
	puts "waiting for connection from application"
	@client = @server.accept
	puts "accepted #{@client.inspect}"
  end

  def stop
	@reader_thread.join
  end

  def send_command command, *args
	STDERR.puts "#{command}(#{args.map{|a|a.inspect}.join(",")})"

	send_str command
	send_int args.length
	args.each {|arg| send_str arg.to_s}
	@client.flush
  end

  def send_int int
	@client.write int.to_s + ","
  end

  def send_str str
	send_int str.length
	@client.write str
  end

  def cleanup
	STDERR.puts "! not doing cleanup"
	return

	File.unlink @new_descriptor_file rescue true
	File.unlink File.join(@relative_dir, @new_content_file) rescue true
	File.unlink File.join(@relative_dir, "inject.swiftest.js") rescue true
  end
end

