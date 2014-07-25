# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'stasher/version'

Gem::Specification.new do |spec|
  spec.name          = "stasher"
  spec.version       = Stasher::VERSION
  spec.authors       = ["Chris Micacchi"]
  spec.email         = ["cdmicacc@gmail.com"]
  spec.description   = %q{Send Rails log messages to logstash}
  spec.summary       = %q{Send Rails log messages to logstash}
  spec.homepage      = "https://github.com/cdmicacc/stasher"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "logstash-event"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rails", "~> 4.1"
end
