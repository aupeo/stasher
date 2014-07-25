require 'spec_helper'

describe Stasher::Logger do
  subject (:logger) { Stasher::Logger.new }

  before :each do
    logger.level = ::Logger::WARN
  end

  it "logs messages that are at the configured level" do
    allow(logger).to receive(:format_message).and_return('message')
    expect(Stasher).to receive(:log).with('WARN', 'message')

    logger.warn 'message'
  end

  it "logs messages that are above the configured level" do
    allow(logger).to receive(:format_message).and_return('message')
    expect(Stasher).to receive(:log).with('ERROR', 'message')

    logger.error 'message'
  end

  it "does not log messages that are below the configured level" do
    expect(Stasher).not_to receive(:log)

    logger.info 'message'
  end

  it "formats the severity" do
    allow(logger).to receive(:format_message).and_return('message')
    expect(Stasher).to receive(:log).with('WARN', 'message')

    logger.add ::Logger::WARN, "message"
  end

  it "returns true" do
    allow(Stasher).to receive(:log)

    expect(logger.add( ::Logger::WARN, "message" )).to eq(true)
  end

  context "when there is a block given" do
    it "yields to the block" do
      allow(Stasher).to receive(:log)

      expect { |b|
        logger.add ::Logger::WARN, &b
      }.to yield_with_no_args
    end

    it "logs the returned message" do
      allow(logger).to receive(:format_message).and_return('message')
      expect(Stasher).to receive(:log).with('WARN', 'message')

      logger.add ::Logger::WARN do
        "message"
      end
    end
  end

  context "when the message is a string" do
    it "formats the message" do
      allow(logger).to receive(:format_message).with('WARN', an_instance_of(Time), nil, "message").and_return("formatted")
      allow(Stasher).to receive(:log)

      logger.warn 'message'
    end

    it "renders the formatted message" do
      allow(logger).to receive(:format_message).and_return("formatted")
      expect(Stasher).to receive(:log).with('WARN', 'formatted')

      logger.warn 'message'
    end
  end

  context "when the message is an object" do
    let (:message) { Object.new }

    it "does not format the message" do
      expect(logger).not_to receive(:format_message)
      expect(Stasher).to receive(:log)

      logger.warn message
    end

    it "logs the raw message object" do
      expect(Stasher).to receive(:log).with('WARN', message)

      logger.warn message
    end
  end
end