require 'rubygems'
require 'hpricot'
require 'socket'
require 'open4'

SWIFTEST_BASE = File.dirname(__FILE__)

require File.join(SWIFTEST_BASE, 'swiftest/commands')
require File.join(SWIFTEST_BASE, 'swiftest/tools')
require File.join(SWIFTEST_BASE, 'swiftest/jsescape')

class Swiftest
  class AlreadyStartedError < StandardError; end
  class JavascriptError < StandardError; end
  include SwiftestCommands

  def self.newOrRecover(*args)
	@@storedState ||= {}
	return @@storedState[args.hash] if @@storedState.keys.include? args.hash

	swiftest = new(args.hash, *args)
	@@storedState[args.hash] = swiftest
	swiftest
  end

  def initialize(hash, descriptor_path, initial_content=nil)
	@hash = hash
	@descriptor_path = descriptor_path

	@relative_dir = if initial_content
					  initial_content
					else
					  File.dirname(@descriptor_path)
					end

	@descriptor_xml = File.read(@descriptor_path)

	descriptor = Hpricot.XML(@descriptor_xml)
	@id = (descriptor/"application > id").text
	@content_file = (descriptor/"application > initialWindow > content").inner_html
  end

  # Bootstrap the application.
  def start
	raise AlreadyStartedError if @started

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

	@pid, @stdin, @stdout, @stderr = Open4.popen4("adl #@new_descriptor_file #@relative_dir")
	@started = true
	at_exit do stop end

	@stdlog = ''

	# Start a thread to pipe through output from adl
	@reader_thread = Thread.start do 
	  begin
		data_ok = true

		while data_ok
		  triggered = IO.select([@stdout, @stderr])
		  break unless triggered and triggered[0]
		  triggered[0].each do |io|
			data = io.readline	# rarely not line based, so this should be ok.
			if data
			  @stdlog += data
			else
			  data_ok = false
			end
		  end
		end
	  rescue IOError
		# STDERR.puts "ioerror in reader thread: #$!"
	  end

	  stop
	end

	# Block for the client
	@client = @server.accept
  end

  def stop
	return unless @started

	@started = false
	# When we kill adl, reader_thread will
	# probably try to stop us again here.

	begin
	  Timeout.timeout(3) do
		Process.kill "TERM", @pid rescue false
		Process.wait @pid
	  end
	rescue Timeout::Error
	  # STDERR.puts "process #@pid not dying; killing (not really an error state with AIR)"
	  Process.kill "KILL", @pid rescue false
	  Process.wait @pid
	end

	@reader_thread.join
	cleanup
  end

  def send_command command, *args
	send_str command
	send_int args.length

	args.each do |arg|
	  esc = arg.javascript_escape
	  
	  case esc
	  when String
		# Ordinary string serialised JS. Will fit in nicely.
		send_str "s"
		send_str esc
	  when Numeric
		# Back reference!
		send_str "b"
		send_int esc
	  else
		raise "Unknown type of JS-escaped object #{esc}: #{esc.class}"
	  end
	end
	@client.flush

	success = recv_bool

	raise JavascriptError, recv_str unless success

	eval(recv_str)
  end

  def send_int int
	@client.write int.to_s + ","
  end

  def send_str str
	send_int str.length
	@client.write str
  end

  def recv_bool
	@client.read(1) == "t"
  end

  def recv_int
	buf = ""
	buf += @client.read(1) while buf[-1] != ?,
	buf[0..-2].to_i
  end

  def recv_str
	len = recv_int
	buf = ""
	buf += @client.read(len - buf.length) while buf.length < len

	buf
  end

  def cleanup
	File.unlink @new_descriptor_file rescue true
	File.unlink File.join(@relative_dir, @new_content_file) rescue true
	File.unlink File.join(@relative_dir, "inject.swiftest.js") rescue true

	@@storedState.delete @hash
  end

  def started?
	@started
  end
end

