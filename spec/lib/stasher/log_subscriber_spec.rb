require 'spec_helper'

describe Stasher::LogSubscriber do
  let(:logger) { MockLogger.new }
  let(:timestamp) { Time.new(2014,01,01,00,00,00,0) }

  before :each do
    Stasher.logger = logger
    allow(Stasher).to receive(:source).and_return("source")
    allow(Time).to receive(:now).and_return(timestamp)
  end

  subject(:subscriber) { Stasher::LogSubscriber.new }

  describe '#start_processing' do
    let(:payload) { FactoryGirl.create(:actioncontroller_payload) }

    let(:event) {
      ActiveSupport::Notifications::Event.new(
        'process_action.action_controller', Time.now, Time.now, 2, payload
      )
    }

    let(:json) {
      '{"@source":"source","tags":["request"],"@fields":{"method":"GET","ip":"127.0.0.1","params":{"foo":"bar"},' +
      '"path":"/home","format":"application/json","controller":"home","action":"index"},"@timestamp":' + timestamp.to_json + ', "@version":"1"}' + "\n"
    }

    it 'calls all extractors and outputs the json' do
      expect(subscriber).to receive(:extract_request).with(payload).and_return({:request => true})
      expect(subscriber).to receive(:extract_current_scope).with(no_args).and_return({:custom => true})
      subscriber.start_processing(event)
    end

    it "logs the event" do
      subscriber.start_processing(event)

      expect(JSON.parse(logger.messages.first)).to eq(JSON.parse(json))
    end
  end

  describe '#sql' do
    let(:event) {
      ActiveSupport::Notifications::Event.new(
        'sql.active_record', Time.now, Time.now, 2, payload
      )
    }

    context "for SCHEMA events" do
      let(:payload) { FactoryGirl.create(:activerecord_sql_payload, name: 'SCHEMA') }

      it "does not log anything" do
        subscriber.sql(event)

        expect(logger.messages).to be_empty
      end
    end

    context "for unnamed events" do
      let(:payload) { FactoryGirl.create(:activerecord_sql_payload, name: '') }

      it "does not log anything" do
        subscriber.sql(event)

        expect(logger.messages).to be_empty
      end
    end

    context "for session events" do
      let(:payload) { FactoryGirl.create(:activerecord_sql_payload, name: 'ActiveRecord::SessionStore') }

      it "does not log anything" do
        subscriber.sql(event)

        expect(logger.messages).to be_empty
      end
    end

    context "for any other events" do
      let(:payload) { FactoryGirl.create(:activerecord_sql_payload) }

      let(:json) {
        '{"@source":"source","tags":["sql"],"@fields":{"name":"User Load","sql":"' +
        payload[:sql] + '","duration":0.0},"@timestamp":' + timestamp.to_json + ', "@version":"1"}' + "\n"
      }

      it 'calls all extractors and outputs the json' do
        expect(subscriber).to receive(:extract_sql).with(payload).and_return({:sql => true})
        expect(subscriber).to receive(:extract_current_scope).with(no_args).and_return({:custom => true})
        subscriber.sql(event)
      end

      it "logs the event" do
        subscriber.sql(event)

        expect(JSON.parse(logger.messages.first)).to eq(JSON.parse(json))
      end
    end
  end

  describe '#process_action' do
    let(:payload) { FactoryGirl.create(:actioncontroller_payload) }

    let(:event) {
      ActiveSupport::Notifications::Event.new(
        'process_action.action_controller', Time.now, Time.now, 2, payload
      )
    }

    let(:json) {
      '{"@source":"source","tags":["response"],"@fields":{"method":"GET","ip":"127.0.0.1","params":{"foo":"bar"},' +
      '"path":"/home","format":"application/json","controller":"home","action":"index","status":200,' +
      '"duration":0.0,"view":0.01,"db":0.02},"@timestamp":' + timestamp.to_json + ', "@version":"1"}' + "\n"
    }

    it 'calls all extractors and outputs the json' do
      expect(subscriber).to receive(:extract_request).with(payload).and_return({:request => true})
      expect(subscriber).to receive(:extract_status).with(payload).and_return({:status => true})
      expect(subscriber).to receive(:runtimes).with(event).and_return({:runtimes => true})
      expect(subscriber).to receive(:extract_exception).with(payload).and_return({:exception => true})
      expect(subscriber).to receive(:extract_current_scope).with(no_args).and_return({:custom => true})
      subscriber.process_action(event)
    end

    it "logs the event" do
      subscriber.process_action(event)

      expect(JSON.parse(logger.messages.first)).to eq(JSON.parse(json))
    end

    context "when the payload includes an exception" do
      before :each do
        payload[:exception] = [ 'Exception', 'message' ]
        allow(subscriber).to receive(:extract_exception).and_return({})
      end

      it "adds the 'exception' tag" do
        subscriber.process_action(event)

        expect(logger.messages.first).to match %r|"tags":\["response","exception"\]|
      end
    end

    it "clears the scoped parameters" do
      expect(Stasher::CurrentScope).to receive(:clear!)

      subscriber.process_action(event)
    end

    context "with a redirect" do
      before do
        Stasher::CurrentScope.fields[:location] = "http://www.example.com"
      end

      it "adds the location to the log line" do
        subscriber.process_action(event)
        expect(logger.messages.first).to match %r|"@fields":{.*?"location":"http://www\.example\.com".*?}|
      end
    end
  end

  describe '#log_event' do
    it "sets the type as a @tag" do
      subscriber.send :log_event, 'tag', {}

      expect(logger.messages.first).to match %r|"tags":\["tag"\]|
    end

    it "renders the data in the @fields" do
      subscriber.send :log_event, 'tag', { "foo" => "bar", :baz => 'bot' }

      expect(logger.messages.first).to match %r|"@fields":{"foo":"bar","baz":"bot"}|
    end

    it "sets the @source" do
      subscriber.send :log_event, 'tag', {}

      expect(logger.messages.first).to match %r|"@source":"source"|
    end

    context "with a block" do
      it "calls the block with the new event" do
        yielded = []
        subscriber.send :log_event, 'tag', {} do |args|
          yielded << args
        end

        expect(yielded.size).to eq(1)
        expect(yielded.first).to be_a(LogStash::Event)
      end

      it "logs the modified event" do
        subscriber.send :log_event, 'tag', {} do |event|
          event.tags << "extra"
        end

        expect(logger.messages.first).to match %r|"tags":\["tag","extra"\]|
      end
    end
  end

  describe '#redirect_to' do
    let(:event) {
      ActiveSupport::Notifications::Event.new(
        'redirect_to.action_controller', Time.now, Time.now, 1, :location => 'http://example.com', :status => 302
      )
    }

    it "stores the payload location in the current scope" do
      subscriber.redirect_to(event)

      expect(Stasher::CurrentScope.fields[:location]).to eq("http://example.com")
    end
  end
end