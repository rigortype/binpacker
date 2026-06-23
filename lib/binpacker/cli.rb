#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"

module Binpacker
  class CLI
    def self.start(args)
      new(args).run
    end

    def initialize(args)
      @args = args.dup
      @command = nil
      @profile = nil
      @passthrough = []
      @quiet = false
      parse!
    end

    def run
      case @command
      when "calibrate"
        cmd_calibrate
      when "run"
        cmd_run
      when "init"
        cmd_init
      when "--version", "-v"
        puts "binpacker #{Binpacker::VERSION}"
      when "--help", "-h", nil
        print_help
      else
        $stderr.puts "unknown command: #{@command}"
        print_help
        exit 1
      end
    end

    private

    def parse!
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: binpacker <command> [options]"

        opts.on("--profile PROFILE", "Profile name from binpacker.yml") do |v|
          @profile = v
        end

        opts.on("--version", "Show version") do
          @command ||= "--version"
        end

        opts.on("--help", "Show help") do
          @command ||= "--help"
        end

        opts.on("--quiet", "Suppress worker output") do
          @quiet = true
        end
      end

      # Extract passthrough arguments after "--"
      if (split_idx = @args.index("--"))
        @passthrough = @args[(split_idx + 1)..] || []
        @args = @args[0...split_idx]
      end

      remaining = parser.parse(@args)
      @command = remaining.shift
    end

    def cmd_init
      config_path = Pathname.pwd.join("binpacker.yml")
      if config_path.exist?
        puts "binpacker.yml already exists at #{config_path}"
        exit 1
      end

      framework = detect_framework
      pattern = framework == "minitest" ? "test/**/*_test.rb" : "spec/**/*_spec.rb"
      runner = framework

      yaml = <<~YAML
        profiles:
          default:
            test_runner: #{runner}
            workers: auto
            timing_file: binpacker.timings
            test_pattern: "#{pattern}"
            scheduler:
              algorithm: lpt
              steal_enabled: true
          ci:
            extends: default
            workers: 4
      YAML

      config_path.write(yaml)
      puts "Created #{config_path}"
      puts "Detected test framework: #{framework}"
      puts ""
      puts "Next steps:"
      puts "  1. binpacker calibrate   (seed timing data)"
      puts "  2. binpacker run          (run in parallel)"
    end

    def cmd_calibrate
      config = Config.new(profile: @profile)
      discovery_klass = config.test_runner == "rspec" ? RSpecDiscovery : MinitestDiscovery
      tests = discovery_klass.new(config).enumerate

      puts "Calibrating #{tests.size} tests..."
      cal = Calibration.new(config)
      timings = cal.run(tests)

      total = timings.sum { |t| t[:time] }
      puts "Calibration complete: #{tests.size} tests in #{total.round(2)}s"
      puts "Timing data written to #{config.timing_file}"
    end

    def cmd_run
      config = Config.new(profile: @profile)
      orchestrator = Orchestrator.new(config, passthrough: @passthrough, quiet: @quiet)

      puts "binpacker starting (#{config.worker_count} workers, profile: #{config.profile})"
      result = orchestrator.run
      unit = test_unit_label(config)

      if result[:passed]
        puts "All #{result[:total]} #{pluralize(result[:total], unit)} passed across #{config.worker_count} workers."
        exit 0
      elsif result[:empty_filter]
        puts "No tests matched the Minitest filter."
        exit 1
      else
        failed = result[:total] - result[:passed_count]
        puts "#{failed}/#{result[:total]} #{pluralize(failed, unit)} failed."
        exit 1
      end
    end

    def test_unit_label(config)
      config.test_runner == "rspec" ? "example" : "test"
    end

    def pluralize(count, word)
      count == 1 ? word : "#{word}s"
    end

    def print_help
      puts <<~HELP
        binpacker #{Binpacker::VERSION}

        Commands:
          run          Execute tests across worker processes
          calibrate    Run tests serially to generate timing data
          init         Create binpacker.yml with auto-detected settings

        Options:
          --profile NAME   Select profile from binpacker.yml
          --help           Show this message

        Examples:
          binpacker init
          binpacker run --profile ci
          binpacker run -- --tag ~slow
          binpacker calibrate
      HELP
    end

    def detect_framework
      return "minitest" if Dir.glob("test*/**/*_test.rb").any?
      return "minitest" if Dir.glob("test*/**/test_*.rb").any?
      "rspec"
    end
  end
end
