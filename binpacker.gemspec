# frozen_string_literal: true

require_relative "lib/binpacker/version"

Gem::Specification.new do |spec|
  spec.name    = "binpacker"
  spec.version = Binpacker::VERSION
  spec.authors = ["megurine"]
  spec.summary = "Reduce CI test-suite makespan via identical-machines scheduling"
  spec.description = "A test runner wrapper that models test distribution as an identical-machines scheduling problem and assigns tests to worker processes using LPT scheduling, with optional work-stealing."
  spec.license = "MPL-2.0"

  spec.required_ruby_version = ">= 3.2"
  spec.homepage = "https://github.com/rigortype/binpacker"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "sig/**/*.rbs", "exe/*", "LICENSE"]
  spec.bindir = "exe"
  spec.executables = ["binpacker"]
end
