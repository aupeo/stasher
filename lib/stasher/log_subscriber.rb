require 'active_support/core_ext/class/attribute'
require 'active_support/log_subscriber'

module Stasher
  class LogSubscriber < ActiveSupport::LogSubscriber
    def start_processing(ev)
      # Initialize the scope at the start of the request
      payload = ev.payload

      data      = extract_request(payload)
      data.merge! extract_current_scope

      log_event 'request', data
    end

    def process_action(ev)
      payload = ev.payload

      data      = extract_request(payload)
      data.merge! extract_status(payload)
      data.merge! runtimes(ev)
      data.merge! extract_exception(payload)
      data.merge! extract_current_scope

      log_event 'response', data do |event|
        event.tags << 'exception' if payload[:exception]
      end

      # Clear the scope at the end of the request
      Stasher::CurrentScope.clear!
    end

    def sql(ev)
      payload = ev.payload

      return if 'SCHEMA' == payload[:name]
      return if payload[:name].blank?
      return if payload[:name] =~ /ActiveRecord::SessionStore/

      data      = extract_sql(payload)
      data.merge! runtimes(ev)
      data.merge! extract_current_scope

      log_event 'sql', data
    end

    def redirect_to(ev)
      Stasher::CurrentScope.fields[:location] = ev.payload[:location]
    end

    private

    def log_event(type, data)
      event = LogStash::Event.new('@fields' => data, '@source' => Stasher.source)
      event.tag(type)
      yield(event) if block_given?
      Stasher.logger << event.to_json + "\n"
    end

    def extract_sql(payload)
      {
        :name => payload[:name],
        :sql => payload[:sql].squeeze(' '),
      }
    end

    def extract_request(payload)
      {
        :method => payload[:method],
        :ip => payload[:ip],
        :params => extract_parms(payload),
        :path => extract_path(payload),
        :format => extract_format(payload),
        :controller => payload[:params]['controller'],
        :action => payload[:params]['action']
      }
    end

    def extract_parms(payload)
      payload[:params].except(*ActionController::LogSubscriber::INTERNAL_PARAMS) if payload.include?(:params)
    end

    def extract_path(payload)
      payload[:path].split("?").first
    end

    def extract_format(payload)
      if ::ActionPack::VERSION::MAJOR == 3 && ::ActionPack::VERSION::MINOR == 0
        payload[:formats].first
      else
        payload[:format]
      end
    end

    def extract_status(payload)
      if payload[:status]
        { :status => payload[:status].to_i }
      else
        { :status => 0 }
      end
    end

    def runtimes(event)
      {
        :duration => event.duration,
        :view => event.payload[:view_runtime],
        :db => event.payload[:db_runtime]
      }.inject({}) do |runtimes, (name, runtime)|
        runtimes[name] = runtime.to_f.round(2) if runtime
        runtimes
      end
    end

    def extract_current_scope
      CurrentScope.fields
    end

    # Monkey patching to enable exception logging
    def extract_exception(payload)
      if payload[:exception]
        exception, message = payload[:exception]

        Stasher.format_exception(exception, message, $!.backtrace.join("\n"))
      else
        {}
      end
    end
  end
end