# frozen_string_literal: true

module Binpacker
  class TestRunner
    def self.runner_name
      raise NotImplementedError
    end

    def self.for(name)
      case name.to_s
      when "rspec" then RSpecRunner
      when "minitest" then MinitestRunner
      else raise ConfigError, "unknown test runner: #{name}"
      end
    end
  end

  class RSpecRunner < TestRunner
    def self.runner_name
      "rspec"
    end

    # Returns the RSpec binary invocation for dry-run discovery
    def self.discovery_command(files)
      ["rspec", "--dry-run", "--format", "json", *files]
    end
  end

  class MinitestRunner < TestRunner
    def self.runner_name
      "minitest"
    end
  end
end
