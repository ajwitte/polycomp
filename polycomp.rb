#!/usr/bin/env ruby

require 'timeout'
require 'date'

module PolyComp
  class Sign
    DefaultBaud = 1200
    TTYFlags   = 'raw -parenb cstopb'

    BroadcastAddr = 0
    DefaultLines  = 2
    DefaultWidth  = 16

    HeaderStart = 0.chr
    HeaderEnd   = 3.chr
    EndOfText   = 4.chr

    ACK = 6
    AckTimeout = 10 # seconds

    module SerSt
      Base      = 0b11000000
      Interrupt = 0b00000010
      MorePages = 0b00000100
      AckWanted = 0b00001000
      SchedMode = 0b00010000
    end

    module WeeklyStatus
      Base      = 0b10000000
      Monday    = 0b00000001
      Tuesday   = 0b00000010
      Wednesday = 0b00000100
      Thursday  = 0b00001000
      Friday    = 0b00010000
      Saturday  = 0b00100000
      Sunday    = 0b01000000
    end

    module Tempo
      Base      = 0b11000000
      Timer     = 0b00000000
      AlwaysOn  = 0b00100000
      AlwaysOff = 0b00010000
      def self.duration(n)
        n.to_i & 0xf
      end
    end

    module Function
      Base      = 0b11000000
      Time      = 0b00010000
      Temp      = 0b00100000
      def self.transition(n)
        n.to_i & 0xf
      end
    end

    module PageStatus
      Base      = 0b10000000
      Join12    = 0b00000001
      Join34    = 0b00000010
      Join56    = 0b00000100
      Join78    = 0b00001000
      Center    = 0b00010000
      Foreign   = 0b00100000
      Invert    = 0b01000000
    end

    def self.open(tty, options = {})
      # TODO use a serial port library
      stty_str = ''
      begin
        stty_str = setup_serial(tty, (options[:baud] || DefaultBaud))
        yield Sign.new(File.open(tty, 'w+'), options)
      ensure
        teardown_serial(tty, stty_str)
      end
      nil
    end

    def reset
      @pageno = 1
    end

    def set_clock(time = nil)
      time ||= Time.now
      body = (SerSt::Base | SerSt::AckWanted | SerSt::MorePages).chr
      body += '000'
      body += time.strftime '%H%M%S%d%m0'
      body += (time.wday + 1).to_s
      transmit(body)
    end

    def page(line1, line2 = nil, options = {})
      if line2.kind_of? Hash
        options = line2
        line2 = nil
      end
      
      join = options[:join]
      join = true if join.nil? and line2.nil?

      raise 'Cannot join when two lines are given' if join and line2
      
      transition = options[:transition] || Transitions::Auto
      duration = options[:duration] || 3

      message = ''
      
      if line1 == :time or line1 == :temp
        message += ' ' * @width
      else
        line1_length = line1.gsub(Markup::Matcher, '').length
        if join
          message += line1
          transition = Transitions::Slide if line1_length > @joined_width
        elsif line1_length > @width
          raise "Line 1 is limited to #{@width} characters"
        elsif options[:center] and ! options[:join]
          # FIXME - deal with markup
          message += line1.center(@width, ' ')
        else
          message += line1 + ' ' * (@width - line1_length)
        end
      end
      
      if line2
        unless line2.kind_of? String
          raise 'Time/temperature not allowed on second line'
        end
        message += line2
        line2_length = line2.gsub(Markup::Matcher, '').length
        transition = Transitions::Slide if line2_length > @width
      end
      
      serst = SerSt::Base | SerSt::AckWanted
      serst |= SerSt::MorePages unless options[:last]
      body = serst.chr

      body += ('%03d' % @pageno)
      body += (Tempo::Base | Tempo::duration(duration) | Tempo::AlwaysOn).chr

      function = Function::Base | Function::transition(transition)
      function |= Function::Time if line1 == :time
      function |= Function::Temp if line1 == :temp
      body += function.chr

      status = PageStatus::Base
      status |= PageStatus::Join12 if join
      status |= PageStatus::Center if options[:center]
      status |= PageStatus::Invert if options[:invert]
      body += status.chr

      body += message unless line1 == :time or line1 == :temp

      transmit(body)
      
      @pageno += 1
    end
    
    protected
    
    def transmit(body)
      packet = HeaderStart + @lines.chr + @address.chr + HeaderEnd +
               body + EndOfText
      
      checksum = 0
      packet.each_byte do |byte|
        checksum ^= byte
      end
      packet += checksum.chr

      @conn.print packet
      @conn.flush

      Timeout.timeout(AckTimeout) do
        unless (b = @conn.getc) == ACK
          raise "Did not receive ACK from the PolyComp sign. (got #{b})"
        end
      end
    end
    
    def self.setup_serial(filename, baud)
      old = `stty -F #{filename} -g`.chomp
      `stty -F #{filename} #{baud} #{TTYFlags}`
      sleep 0.5
      return old
    end

    def self.teardown_serial(filename, stty_str)
      `stty -F #{filename} #{stty_str}`.chomp
    end

    def initialize(conn, options = {})
      @conn    = conn
      @width   = options[:width] || DefaultWidth
      @lines   = options[:lines] || DefaultLines
      @address = options[:address] || BroadcastAddr

      @joined_width = options[:joined_width] || (@width / 2)

      reset
      set_clock
    end
    
  end

  module Transitions
    Auto     = 0x0
    Appear   = 0x1
    Wipe     = 0x2
    Open     = 0x3
    Lock     = 0x4
    Rotate   = 0x5
    Right    = 0x6
    Left     = 0x7
    RollUp   = 0x8
    RollDown = 0x9
    PingPong = 0xa
    FillUp   = 0xb
    Paint    = 0xc
    FadeIn   = 0xd
    Jump     = 0xe
    Slide    = 0xf
  end

  module Markup
    Flash   = "\x1cF"
    Bold    = "\x1cE"
    Red     = "\x1cR"
    Green   = "\x1cG"
    Yellow  = "\x1cY"
    Rainbow = "\x1cM"
    Default = "\x1cD"
    Matcher = /\x1c./
  end
end


if $0 == __FILE__
  # Note: All parameters in the hash argument to Sign.open are optional
  PolyComp::Sign.open('/dev/ttyS0',
      :baud => 1200, :width => 16, :lines => 2) do |sign|
    
    # Display 'Hello World' on two lines, using a random transition
    #  and a specific duration
    sign.page 'HELLO', 'WORLD',
              :center => true, :duration => 4

    # Display the current time on two lines
    #  Duration defaults to something reasonable if not specified
    sign.page :time, :center => true
    
    # Use a specific transition
    sign.page 'PING PONG',
              :transition => PolyComp::Transitions::PingPong

    # Using markup to make it fancy (NB: this is not perfectly supported yet)
    sign.page "THIS IS #{PolyComp::Markup::Bold}BOLD#{PolyComp::Markup::Default}",
              "THIS IS #{PolyComp::Markup::Flash}FLASHING"
    
    # This is the last page; by saying so the sign starts displaying the new
    #  pages right away, instead of waiting for a 40-second timeout.
    sign.page 'THE', 'END.', :last => true
  end
end
