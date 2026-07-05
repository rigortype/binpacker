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
      @incremental = false
      @report_path = nil
      @skill_list = false
      @skill_path = false
      @skill_describe = false
      @skill_name = nil
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
      when "skill"
        cmd_skill
      when "describe"
        cmd_describe
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

        opts.on("--incremental", "Calibrate only tests without timing data") do
          @incremental = true
        end

        opts.on("--report PATH", "(run) Write a JSON run report to PATH") do |v|
          @report_path = v
        end

        opts.on("--list", "(skill) List bundled skills") do
          @skill_list = true
        end

        opts.on("--path", "(skill) Print the SKILL.md path for <name>") do
          @skill_path = true
        end

        opts.on("--describe", "(skill) Report project state and next skill") do
          @skill_describe = true
        end
      end

      # Extract passthrough arguments after "--"
      if (split_idx = @args.index("--"))
        @passthrough = @args[(split_idx + 1)..] || []
        @args = @args[0...split_idx]
      end

      remaining = parser.parse(@args)
      @command = remaining.shift
      @skill_name = remaining.shift
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
              algorithm: multifit
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

      cal = Calibration.new(config)

      if @incremental
        puts "Calibrating (incremental) #{tests.size} tests..."
      else
        puts "Calibrating #{tests.size} tests..."
      end

      timings = cal.run(tests, incremental: @incremental)

      total = timings.sum { |t| t[:time] }
      measured = timings.size
      skipped = tests.size - measured
      summary = "Calibration complete: #{measured} #{pluralize(measured, 'test')} in #{total.round(2)}s"
      summary += " (#{skipped} skipped, already measured)" if @incremental && skipped.positive?
      puts summary
      puts "Timing data written to #{config.timing_file}"
    end

    def cmd_skill
      return cmd_describe if @skill_describe

      if @skill_path
        path = Skills.path(@skill_name)
        if path
          puts path
        else
          $stderr.puts "unknown skill: #{@skill_name}"
          exit 1
        end
      elsif @skill_name && !@skill_list
        print_skill(@skill_name)
      else
        list_skills
      end
    end

    def cmd_describe
      state = ProjectState.new
      puts "binpacker project state:"
      puts "  config (binpacker.yml): #{state.config_present? ? 'present' : 'missing'}"
      puts "  timing data:            #{state.timing_present? ? 'present' : 'missing'}"
      puts "  test framework:         #{state.framework || 'not detected'}"
      puts "  CI wired for binpacker: #{state.ci_wired? ? 'yes' : 'no'}"
      puts ""
      rec = state.recommendation
      puts "Recommended next skill: #{rec}"
      puts "Run `binpacker skill #{rec}` to load its instructions."
    end

    def list_skills
      skills = Skills.list
      if skills.empty?
        puts "No bundled skills found."
        return
      end
      puts "Bundled skills:"
      skills.each { |s| puts "  #{s[:name]}" }
      puts ""
      puts "Print a skill's instructions with `binpacker skill <name>`."
    end

    def print_skill(name)
      unless Skills.exist?(name)
        $stderr.puts "unknown skill: #{name}"
        $stderr.puts "Run `binpacker skill` to list bundled skills."
        exit 1
      end

      puts "# Skill: #{name}"
      puts "# Source: #{Skills.path(name)}"
      puts ""
      puts Skills.body(name)
    end

    def cmd_run
      config = Config.new(profile: @profile)
      report_path = @report_path || config.report_file
      orchestrator = Orchestrator.new(
        config, passthrough: @passthrough, quiet: @quiet, report_path: report_path
      )

      puts "binpacker starting (#{config.worker_count} workers, profile: #{config.profile})"
      result = orchestrator.run
      puts "Run report written to #{report_path}" if report_path
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
          describe     Report project state and recommend the next skill
          skill        List or print bundled agent skills

        Options:
          --profile NAME   Select profile from binpacker.yml
          --incremental    (calibrate) Measure only tests without timing data
          --report PATH    (run) Write a JSON run report to PATH
          --list           (skill) List bundled skills
          --path           (skill) Print the SKILL.md path for <name>
          --describe       (skill) Report project state and next skill
          --help           Show this message

        Examples:
          binpacker init
          binpacker run --profile ci
          binpacker run -- --tag ~slow
          binpacker calibrate --incremental
          binpacker describe
          binpacker skill binpacker-setup
      HELP
    end

    def detect_framework
      return "minitest" if Dir.glob("test*/**/*_test.rb").any?
      return "minitest" if Dir.glob("test*/**/test_*.rb").any?
      "rspec"
    end
  end
end
