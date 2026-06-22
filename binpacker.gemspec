# frozen_string_literal: true

require_relative "lib/binpacker/version"

Gem::Specification.new do |spec|
  spec.name    = "binpacker"
  spec.version = Binpacker::VERSION
  spec.authors = ["megurine"]
  spec.summary = "Minimize CI test-suite makespan by solving an identical-machines scheduling problem"
  spec.description = "A test runner wrapper that manages worker processes and distributes tests among them using LPT scheduling with optional work-stealing."
  spec.license = "MPL-2.0"

  spec.required_ruby_version = ">= 3.2"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "exe/*", "LICENSE.txt"]
  spec.bindir = "exe"
  spec.executables = ["binpacker"]
end
