# Copyright 2010-2011 Noble Samurai
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
  class OtherEndDisappearedError < StandardError; end
  include SwiftestCommands

  SELF_LAUNCH = ENV.include?("SWIFTEST_LAUNCH") && ENV["SWIFTEST_LAUNCH"].downcase.strip == "self"

  @@fileSuffix = ""
  @@storedState = nil

  def self.newOrRecover(*args)
    if @@storedState
      @@lastWasNew = false
      return @@storedState[:swiftest] if @@storedState[:hash] == args.hash

      @@storedState[:swiftest].stop
      @@storedState = nil
    end

    @@lastWasNew = true
    swiftest = new(args.hash, *args)
    @@storedState = {:hash => args.hash, :swiftest => swiftest}
    swiftest
  end

  def self.active
    return nil if @@storedState.nil?
    @@storedState[:swiftest]
  end

  def self.fileSuffix=(suffix)
    @@fileSuffix = suffix
  end

  def self.fileSuffix
    @@fileSuffix
  end

  def self.lastWasNew?
    @@lastWasNew
  end

  def initialize(hash, descriptor_path, initial_content=nil, project_file="", *other_args)
    @hash = hash
    @descriptor_path = descriptor_path
    @profile_file = ""
    @project_file = project_file
    @other_args = other_args

    @relative_dir = initial_content ? initial_content : File.dirname(@descriptor_path)

    @descriptor_xml = File.read(@descriptor_path)

    descriptor = Hpricot.XML(@descriptor_xml)
    @id = (descriptor/"application > id").text
    @content_file = (descriptor/"application > initialWindow > content").inner_html

    clear_expects!

    @sent_packets = 0
    @pending_packets = {}
    @received_packets = {}
    @last_received = 0
    @last_processed = 0
  end

  def clear_expects!
    @expected_alerts = []
    @expected_confirms = []
    @expected_prompts = []
    @expected_navigates = []
    @expected_browseDialogs = []
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
    @server.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, true)
    @port = @server.addr[1]

    @new_content_file = "#@content_file.swiftest#@@fileSuffix.html"

    bannerb64 = Base64.encode64(File.read(File.join(SWIFTEST_BASE, "banner.png"))).gsub("\n", "")
    rbannerb64 = Base64.encode64(File.read(File.join(SWIFTEST_BASE, "rbanner.png"))).gsub("\n", "")

    # We add the script tags to the end of the </head> tag and then place it in position for the new
    # (doctored) content file.	Don't just append it, a <script/> tag outside of the normal place
    # can kill AIR!
    new_content = File.open(File.join(@relative_dir, @content_file), "r").read.gsub(/<\/\s*head\s*>/i, "
	<script type='text/javascript'>
	  var SWIFTEST_PORT = air.NativeApplication.nativeApplication.publisherID;
	</script>
	<script type='text/javascript' src='inject.swiftest.js'></script>
	<style type='text/css'>
	  #{File.read(File.join(SWIFTEST_BASE, "inject.css")).gsub("YBANNERB64", bannerb64).gsub("RBANNERB64", rbannerb64)}
	</style>
      </head>").gsub(/(<\s*body[^>]*>)/i, "\\1\<div id='swiftest-overlay-ff'>
	<div class='swiftest-overlay-text' id='swiftest-overlay-left-container'>
	  <div id='swiftest-overlay-left'>
	    initialising
	  </div>
	  <a class='swiftest-overlay-manual-pass' href='#'>Pass</a>
	  <a class='swiftest-overlay-manual-fail' href='#'>Fail</a>
	</div>
	<div class='swiftest-overlay-text' id='swiftest-overlay-right'>swiftest</div>
      </div>")

    File.open(File.join(@relative_dir, @new_content_file), "w") {|f| f.write(new_content)}

    # Actually drop inject.js in under the right name.
    FileUtils.cp File.join(SWIFTEST_BASE, "inject.js"), File.join(@relative_dir, "inject.swiftest.js")

    # Make a new copy of the descriptor to point to a new initial page.
    @new_descriptor_file = "#@descriptor_path.swiftest#@@fileSuffix.xml"
    File.open(@new_descriptor_file, "w") do |xmlout|
      descriptor = Hpricot.XML(@descriptor_xml)
      (descriptor/"application > initialWindow > content").inner_html = @new_content_file
      xmlout.puts descriptor
    end

    # Open up the modified descriptor with ADL if the user isn't starting it themselves.
    cmd = "adl -pubid #{@port} #{ENV["SWIFTEST_ADL_OPTS"]} #@new_descriptor_file #@relative_dir -- #{ENV["SWIFTEST_ARGS"]} #@project_file #{@other_args.join " "}"
    if !SELF_LAUNCH
      @pid, @stdin, @stdout, @stderr = Open4.popen4(cmd)
      @started = true
      at_exit do stop end

      @stdlog = ''

      if ENV['SWIFTEST_LOGOUT']
	logout = File.open(ENV['SWIFTEST_LOGOUT'] + Time.now.to_i.to_s, "w")
      else
	logout = STDOUT
      end

      # Start a thread to pipe through output from adl
      if !ENV['SWIFTEST_NOLOGTHREAD']
	@reader_thread = Thread.start do
	  begin
	    data_ok = true

	    while data_ok
	      triggered = IO.select([@stdout, @stderr])
	      break unless triggered and triggered[0]
	      triggered[0].each do |io|
		data = io.readline  # rarely not line based, so this should be ok.
		if data
		  if ENV['SWIFTEST_LOGGING'] == 'realtime'
		    logout.puts data
		    logout.flush
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

	  if ENV['SWIFTEST_LOGGING'] == 'post'
	    logout.puts @stdlog 
	    logout.flush 
	  end

	  logout.close if ENV['SWIFTEST_LOGOUT']

	  stop
	end
      end
    end

    # Block for the client
    STDERR.puts "engage with: #{cmd}" if SELF_LAUNCH
    @client = @server.accept
    STDERR.flush
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

    @reader_thread.join if @reader_thread
    cleanup
  end

  def send_command command, *args
    pkt =
      serialise_str(command) +
      serialise_int(args.length)

    args.each do |arg|
      esc = arg.javascript_escape
      
      case esc
      when String
	# Ordinary string serialised JS. Will fit in nicely.
	pkt += serialise_str "s"
	pkt += serialise_str esc
      when Numeric
	# Back reference!
	pkt += serialise_str "b"
	pkt += serialise_int esc
      else
	raise "Unknown type of JS-escaped object #{esc}: #{esc.class}"
      end
    end

    reply = send_packet(pkt)

    consume_bool = lambda {
      b = reply[0] == ?t
      reply = reply[1..-1]
      b
    }

    consume_int = lambda {
      reply = reply.split ",", 2
      i = reply.first.to_i
      reply = reply.last
      i
    }

    consume_str = lambda {
      len = consume_int[]
      s = reply[0...len]
      reply = reply[len..-1]
      s
    }

    begin
      success = consume_bool[]
      confirms_or_alerts = consume_bool[]
    rescue Errno::ECONNRESET => e
      STDERR.puts "connection reset! sending #{command.inspect}, #{args.inspect}"
      exit 250
    end

    raise JavascriptError, consume_str[] unless success

    begin
      js = consume_str[]
      r = eval(js)
    rescue SyntaxError => e
      STDERR.puts "got a syntax error while evaling #{js.inspect}"
      raise
    end

    if confirms_or_alerts
      alerts, confirms, prompts, navigates, browseDialogs = send_command "acp-state"

      while alerts.length > 0
	raise "Unexpected alert #{alerts[0]}" if @expected_alerts.length.zero?
	raise "Unexpected alert #{alerts[0]}" unless @expected_alerts[0].regexp === alerts[0] or
	                                             alerts[0].match(@expected_alerts[0].regexp)
	alerts.shift
	@expected_alerts[0].hit!
	@expected_alerts.shift
      end

      while confirms.length > 0
	raise "Unexpected confirm #{confirms[0]}" if @expected_confirms.length.zero?
	raise "Unexpected confirm #{confirms[0]}" unless @expected_confirms[0].regexp === confirms[0] or
	                                                 confirms[0].match(@expected_confirms[0].regexp)
	confirms.shift
	@expected_confirms[0].hit!
	@expected_confirms.shift
      end

      while prompts.length > 0
	raise "Unexpected prompt #{prompts[0]}" if @expected_prompts.length.zero?
	raise "Expected prompt #{@expected_prompts[0].regexp}, but received #{prompts[0]}" unless @expected_prompts[0].regexp === prompts[0] or
	                                                                                          prompts[0].match(@expected_prompts[0].regexp)
	prompts.shift
	@expected_prompts[0].hit!
	@expected_prompts.shift
      end

      while navigates.length > 0
	raise "Unexpected navigateToUrl #{navigates[0]}" if @expected_navigates.length.zero?
	raise "Expected navigateToUrl #{@expected_navigates[0].regexp}, but received #{navigates[0]}" unless @expected_navigates[0].regexp === navigates[0] or
	                                                                                                     navigates[0].match(@expected_navigates[0].regexp)
	navigates.shift
	@expected_navigates[0].hit!
	@expected_navigates.shift
      end

      while browseDialogs.length > 0
	raise "Unexpected browseDialog #{browseDialogs[0]}" if @expected_browseDialogs.length.zero?
	raise "Expected browseDialog #{@expected_browseDialogs[0].regexp}, but received #{browseDialogs[0]}" unless @expected_browseDialogs[0].regexp === browseDialogs[0] or
	                                                                                                     browseDialogs[0].match(@expected_browseDialogs[0].regexp)
	browseDialogs.shift
	@expected_browseDialogs[0].hit!
	@expected_browseDialogs.shift
      end
    end

    r
  end

  def send_packet pkt
    @sent_packets += 1
    id = @sent_packets

    @pending_packets[id] = pkt

    send_packet_phys id, pkt
    wait_for_packet id
  end

  def send_packet_phys id, pkt
    @client.write(serialise_int(id) + serialise_str(pkt))
    @client.flush
  rescue OtherEndDisappearedError => e
    STDERR.puts "OEDE in send_packet_phys"
    reaccept_resend rescue STDERR.puts "WTFFFFFFFFFFFFF #$!"
  rescue Errno::ECONNRESET
    STDERR.puts "ECONNRESET in send_packet_phys"
    reaccept_resend rescue STDERR.puts "WTFFFFFFFFFFFFF #$!"
  end

  def wait_for_packet id
    while @received_packets[id].nil?
      begin
	receive_packet 
      rescue => e
	STDERR.puts "ERROR in receive_packet: #{e.inspect}"
      end
    end
    @last_processed = id
    @received_packets.delete id
  end

  def receive_packet
    id = recv_int
    if id == 0
      @last_received = recv_int
      @pending_packets.reject! {|no,pkt| no < @last_received}

      STDERR.puts "heartbeat says they last received #@last_received, telling them we last processed #@last_processed (pp:#{@pending_packets.length})"
      STDERR.flush
      @client.write(serialise_int(0) + serialise_int(@last_processed))
      @client.flush
      return
    end

    len = recv_int
    data = @client.read len
    raise OtherEndDisappearedError if data.length != len
    @received_packets[id] = data
  rescue OtherEndDisappearedError => e
    STDERR.puts "OEDE in receive_packet"
    reaccept_resend rescue STDERR.puts "WTFFFFFFFFFFFFF #$!"
  end

  def reaccept_resend
    @client.close rescue false
    STDERR.puts "reaccept_resend START"
    @client = @server.accept
    STDERR.puts "got #{@client.inspect}"
    @pending_packets.each do |id, pkt|
      if id > @last_received
	STDERR.puts "resending packet #{id} = #{pkt}"
	send_packet_phys id, pkt
      else
	STDERR.puts "not resending packet #{id} (they last received #@last_received)"
      end
    end
    STDERR.puts "reaccept_resend FINISH"
  end

  def serialise_int int
    "#{int},"
  end

  def serialise_str str
    serialise_int(str.length) + str
  end

  def recv_int
    buf = ""
    while buf[-1] != ?,
      b = @client.read 1
      raise OtherEndDisappearedError if b == nil
      buf += b
    end
    buf[0..-2].to_i
  rescue Errno::EPIPE
    exit 250
  end

  def cleanup
    File.unlink @new_descriptor_file rescue true
    File.unlink File.join(@relative_dir, @new_content_file) rescue true
    File.unlink File.join(@relative_dir, "inject.swiftest.js") rescue true

    @@storedState = nil if @@storedState[:swiftest] == self

    p $swiftest_calls.to_a.sort_by {|x,y| -y}
  end

  def started?
    @started
  end

  class UniqueExpect
    def initialize regexp
      @regexp = regexp
      @hit = false
    end
    def hit?; @hit; end
    def hit!; @hit = true; end
    attr_accessor :regexp
  end

  def expect_confirm match, ok, soft=false, &b
    ue = UniqueExpect.new(match)
    @expected_confirms << ue
    restore_cr = send_command("set-confirm-reply", ok)
    b.call ->{ue.hit?}

    if @expected_confirms[-1] == ue
      raise "Expected confirm #{match.inspect} didn't occur!" unless soft
      @expected_confirms.pop
    end

    send_command "set-confirm-reply", restore_cr
  end

  def soft_expect_confirm match, ok, &b
    expect_confirm match, ok, true, &b
  end

  def expect_alert match, soft=false, &b
    ue = UniqueExpect.new(match)
    @expected_alerts << ue
    b.call ->{ue.hit?}

    if @expected_alerts[-1] == ue
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

    ue = UniqueExpect.new(match)
    @expected_prompts << ue
    restore_pr = send_command("set-prompt-reply", reply)
    b.call ->{ue.hit?}

    if @expected_prompts[-1] == ue
      raise "Expected prompt #{match.inspect} didn't occur!" unless soft
      @expected_prompts.pop
    end

    send_command "set-prompt-reply", restore_pr
  end

  def soft_expect_prompt match, reply, &b
    expect_prompt match, reply, true, &b
  end

  def expect_browseDialog match, file, soft=false, &b
    ue = UniqueExpect.new(match)
    @expected_browseDialogs << ue
    restore_file = send_command("set-browsedialog-file", file);
    b.call ->{ue.hit?}

    if @expected_browseDialogs[-1] == ue
      raise "Expected browseDialog #{match.inspect} didn't occur!" unless soft
      @expected_browseDialogs.pop
    end

    send_command "set-browsedialog-file", restore_file
  end

  def soft_expect_browseDialog match, file, &b
    expect_browseDialog match, file, true, &b
  end

  def expect_navigate match, soft=false, &b
    ue = UniqueExpect.new(match)
    @expected_navigates << ue
    b.call ->{ue.hit?}

    if @expected_navigates[-1] == ue
      raise "Expected navigateToUrl #{match.inspect} didn't occur!" unless soft
    end
  end

  def soft_expect_navigate match, &b
    expect_navigate match, true, &b
  end

  attr_reader :port
end

# vim: set sw=2 ts=8 noet:
