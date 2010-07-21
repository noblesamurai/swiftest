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

require 'rubygems'
require 'hpricot'
require 'socket'
require 'open4'
require 'base64'

SWIFTEST_BASE = File.dirname(__FILE__)

require File.join(SWIFTEST_BASE, 'swiftest/commands')
require File.join(SWIFTEST_BASE, 'swiftest/tools')
require File.join(SWIFTEST_BASE, 'swiftest/jsescape')

class Swiftest
  class AlreadyStartedError < StandardError; end
  class JavascriptError < StandardError; end
  include SwiftestCommands

  SELF_LAUNCH = ENV.include?("SWIFTEST_LAUNCH") && ENV["SWIFTEST_LAUNCH"].downcase.strip == "self"

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

	@relative_dir = initial_content ?  initial_content : File.dirname(@descriptor_path)

	@descriptor_xml = File.read(@descriptor_path)

	descriptor = Hpricot.XML(@descriptor_xml)
	@id = (descriptor/"application > id").text
	@content_file = (descriptor/"application > initialWindow > content").inner_html

	@expected_alerts, @expected_confirms, @expected_prompts = [], [], []
  end

  # Bootstrap the application.
  def start
	raise AlreadyStartedError if @started

	begin
	  @server = TCPServer.open(0)
	rescue SocketError
	  # Possibly OS X being rubbish.
	  while !@server
		begin
		  @server = TCPServer.open('0.0.0.0', 20000 + rand(10000))
		rescue SocketError
		  STDERR.puts "Failed to open local server again."
		end
	  end
	end
	@port = @server.addr[1]
	
	@new_content_file = "#@content_file.swiftest.html"

	bannerb64 = Base64.encode64(File.read(File.join(SWIFTEST_BASE, "banner.png"))).gsub("\n", "")

	# We add the script tags to the end of the </head> tag and then place it in position for the new
	# (doctored) content file.  Don't just append it, a <script/> tag outside of the normal place
	# can kill AIR!
	new_content = File.open(File.join(@relative_dir, @content_file), "r").read.gsub(/<\/\s*head\s*>/i, "
		<script type='text/javascript'>
		  var SWIFTEST_PORT = #@port;
		</script>
		<script type='text/javascript' src='inject.swiftest.js'></script>
		<style type='text/css'>
		  #swiftest-overlay-ff {
			position: absolute; display: block;

			bottom: 0px; right: 0px;
			left: 0px; height: 20px;

			z-index: 10000000;

			background: url('data:image/png;base64,#{bannerb64}');
		  }
		  #swiftest-overlay-text {
			display: block;

			margin-left: auto; margin-right: auto; margin-top: 4px;
			width: 8em; height: 14px;

			background: rgba(0, 0, 0, 0.8);
			color: #fff;

			text-align: center;
			font-size: 12px;
		  }
		</style>
	  </head>").gsub(/(<\s*body[^>]*>)/i, "\\1<div id='swiftest-overlay-ff'><div id='swiftest-overlay-text'>swiftest</div></div>")

	File.open(File.join(@relative_dir, @new_content_file), "w") {|f| f.write(new_content)}

	# Actually drop inject.js in under the right name.
	FileUtils.cp File.join(SWIFTEST_BASE, "inject.js"), File.join(@relative_dir, "inject.swiftest.js")

	# Make a new copy of the descriptor to point to a new initial page.
	@new_descriptor_file = "#@descriptor_path.swiftest.xml"
	File.open(@new_descriptor_file, "w") do |xmlout|
	  descriptor = Hpricot.XML(@descriptor_xml)
	  (descriptor/"application > initialWindow > content").inner_html = @new_content_file
	  xmlout.puts descriptor
	end

	# Open up the modified descriptor with ADL if the user isn't starting it themselves.
	if !SELF_LAUNCH
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
				if ENV['SWIFTEST_LOGGING'] == 'realtime'
				  puts data
				else
				  @stdlog += data
				end
			  else
				data_ok = false
			  end
			end
		  end
		rescue EOFError
		  # Ignore this, it's nothing.
		rescue IOError
		  STDERR.puts "ioerror in reader thread: #{$!.inspect}"
		  exit
		end

		puts @stdlog if ENV['SWIFTEST_LOGGING'] == 'post'

		stop
	  end
	end

	# Block for the client
	STDERR.puts "engage!" if SELF_LAUNCH
	@client = @server.accept
  	@started = true
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

	begin
	  success = recv_bool
	  confirms_or_alerts = recv_bool
	rescue Errno::ECONNRESET => e
	  STDERR.puts "connection reset! sending #{command.inspect}, #{args.inspect}"
	  exit 250
	end

	raise JavascriptError, recv_str unless success

	r = eval(recv_str)

	if confirms_or_alerts
	  alerts, confirms, prompts = send_command "acp-state"

	  while alerts.length > 0
		raise "Unexpected alert #{alerts[0]}" if @expected_alerts.length.zero?
		raise "Unexpected alert #{alerts[0]}" unless @expected_alerts[0] === alerts[0]
		alerts.shift
		@expected_alerts.shift
	  end

	  while confirms.length > 0
		raise "Unexpected confirm #{confirms[0]}" if @expected_confirms.length.zero?
		raise "Unexpected confirm #{confirms[0]}" unless @expected_confirms[0] === confirms[0]
		confirms.shift
		@expected_confirms.shift
	  end

	  while prompts.length > 0
		raise "Unexpected prompt #{prompts[0]}" if @expected_prompts.length.zero?
		raise "Unexpected prompt #{prompts[0]}" unless @expected_prompts[0] === prompts[0]
		prompts.shift
		@expected_prompts.shift
	  end
	end

	r
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

	p $swiftest_calls
  end

  def started?
	@started
  end

  def expect_confirm match, ok, soft=false, &b
	@expected_confirms << match
	restore_cr = send_command("set-confirm-reply", ok)
	b.call

	if @expected_confirms[-1] == match
	  raise "Expected confirm #{match.inspect} didn't occur!" unless soft
	  @expected_confirms.pop
	end

	send_command "set-confirm-reply", restore_cr
  end

  def soft_expect_confirm match, ok, &b
	expect_confirm match, ok, true, &b
  end

  def expect_alert match, soft=false, &b
	@expected_alerts << match
	b.call

	if @expected_alerts[-1] == match
	  raise "Expected alert #{match.inspect} didn't occur!" unless soft
	  @expected_alerts.pop
	end
  end

  def soft_expect_alert match, &b
	expect_alert match, true, &b
  end

  # Note that 'reply' can be :default or :cancel
  def expect_prompt match, reply, soft=false, &b
	reply = "::DEFAULT::" if reply == :default
	reply = "::CANCEL::" if reply == :cancel

	@expected_prompts << match
	restore_pr = send_command("set-prompt-reply", reply)
	b.call

	if @expected_prompts[-1] == match
	  raise "Expected prompt #{match.inspect} didn't occur!" unless soft
	  @expected_prompts.pop
	end

	send_command "set-prompt-reply", restore_pr
  end

  def soft_expect_prompt match, reply, &b
	expect_prompt match, reply, true, &b
  end
end

# vim: set sw=2:
