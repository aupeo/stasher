require "stasher/version"
require 'stasher/log_subscriber'
require 'stasher/current_scope'
require 'stasher/logger'
require 'active_support/core_ext/module/attribute_accessors'
require 'active_support/core_ext/string/inflections'
require 'active_support/ordered_options'

module Stasher
    # Logger for the logstash logs
    mattr_accessor :logger, :enabled, :source

    def self.remove_existing_log_subscriptions
      ActiveSupport::LogSubscriber.log_subscribers.each do |subscriber|
        case subscriber
          when ActionView::LogSubscriber
            unsubscribe(:action_view, subscriber)
          when ActiveRecord::LogSubscriber
            unsubscribe(:active_record, subscriber)
          when ActionController::LogSubscriber
            unsubscribe(:action_controller, subscriber)
        end
      end
    end

    def self.unsubscribe(component, subscriber)
      events = subscriber.public_methods(false).reject{ |method| method.to_s == 'call' }
      events.each do |event|
        ActiveSupport::Notifications.notifier.listeners_for("#{event}.#{component}").each do |listener|
          if listener.instance_variable_get('@delegate') == subscriber
            ActiveSupport::Notifications.unsubscribe listener
          end
        end
      end
    end

    def self.add_default_fields_to_scope(scope, request)
      scope[:uuid] = request.uuid
    end

    def self.add_custom_fields(&block)
      ActionController::Metal.send(:define_method, :stasher_add_custom_fields_to_scope, &block)
    end

    def self.setup(app)
      app.config.action_dispatch.rack_cache[:verbose] = false if app.config.action_dispatch.rack_cache

      # Compose source
      self.source = "rails://#{hostname}/#{app.class.name.deconstantize.underscore}"

      # Initialize & set up instrumentation
      require 'stasher/rails_ext/action_controller/metal/instrumentation'
      require 'logstash/event'
      self.suppress_app_logs(app) if app.config.stasher.suppress_app_log

      # Redirect Rails' logger if requested
      Rails.logger = Stasher::Logger.new  if app.config.stasher.redirect_logger

      # Subscribe to configured events
      app.config.stasher.attach_to.each do |target|
        Stasher::LogSubscriber.attach_to target
      end

      # Initialize internal logger
      self.logger = app.config.stasher.logger || Logger.new("#{Rails.root}/log/logstash_#{Rails.env}.log")
      level = ::Logger.const_get(app.config.stasher.log_level.to_s.upcase) if app.config.stasher.log_level
      self.logger.send(:level=, level || Logger::WARN)

      self.enabled = true
    end

    def self.suppress_app_logs(app)
      require 'stasher/rails_ext/rack/logger'
      Stasher.remove_existing_log_subscriptions

      # Disable ANSI colorization
      app.config.colorize_logging = false
    end

    def self.format_exception(type_name, message, backtrace)
      {
        :exception => {
          :name => type_name,
          :message => message,
          :backtrace => backtrace
        }
      }
    end

    def self.log(severity, msg)
      if self.logger && self.logger.send("#{severity.to_s.downcase}?")
        data = {
          :severity => severity.upcase
        }
        tags = ['log']

        if msg.is_a? Exception
          data.merge! self.format_exception(msg.class.name, msg.message, msg.backtrace.join("\n"))
          msg = "#{msg.class.name}: #{msg.message}"
          tags << 'exception'
        else
          # Strip ANSI codes from the message
          msg.gsub!(/\u001B\[[0-9;]+m/, '')
        end

        return true if msg.empty?
        data.merge! CurrentScope.fields

        tags << severity.downcase

        event = LogStash::Event.new(
          '@fields' => data,
          '@message' => msg,
          '@source' => Stasher.source)
        tags.each { |t| event.tag(t) }
        self.logger << event.to_json + "\n"
      end
    end

    def self.hostname
      require 'socket'

      Socket.gethostname
    end

    class << self
      %w( fatal error warn info debug unknown ).each do |severity|
        eval <<-EOM, nil, __FILE__, __LINE__ + 1
          def #{severity}(msg)
            self.log(:#{severity}, msg)
          end
        EOM
      end
    end
end

require 'stasher/railtie' if defined?(Rails)