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
      parse!
    end

    def run
      case @command
      when "calibrate"
        cmd_calibrate
      when "run"
        cmd_run
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
      end

      # Extract passthrough arguments after "--"
      if (split_idx = @args.index("--"))
        @passthrough = @args[(split_idx + 1)..] || []
        @args = @args[0...split_idx]
      end

      remaining = parser.parse(@args)
      @command = remaining.shift
    end

    def cmd_calibrate
      config = Config.new(profile: @profile)
      discovery = TestRunner.for(config.test_runner)
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
      orchestrator = Orchestrator.new(config, passthrough: @passthrough)

      puts "binpacker starting (#{config.worker_count} workers, profile: #{config.profile})"
      result = orchestrator.run

      if result[:passed]
        puts "All #{result[:total]} examples passed across #{config.worker_count} workers."
        exit 0
      else
        failed = result[:total] - result[:passed_count]
        puts "#{failed}/#{result[:total]} examples failed."
        exit 1
      end
    end

    def print_help
      puts <<~HELP
        binpacker #{Binpacker::VERSION}

        Commands:
          run          Execute tests across worker processes
          calibrate    Run tests serially to generate timing data

        Options:
          --profile NAME   Select profile from binpacker.yml
          --help           Show this message

        Examples:
          binpacker run --profile ci
          binpacker run -- --tag ~slow
          binpacker calibrate
      HELP
    end
  end
end
