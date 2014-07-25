require 'logger'

module Stasher
  class Logger < ::Logger
    def initialize(device = nil)
      super(device)
    end

    def add(severity, message = nil, progname = nil, &block)
      severity ||= UNKNOWN
      if severity < @level
        return true
      end

      progname ||= @progname
      if message.nil?
        if block_given?
          message = yield
        else
          message = progname
          progname = @progname
        end
      end

      severity = format_severity(severity)

      if message.is_a? String
        message = format_message(severity, Time.now, progname, message).chomp
      end

      Stasher.log severity, message

      true
    end

    private


  end
end