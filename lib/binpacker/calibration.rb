# frozen_string_literal: true

require "json"
require "open3"
require "time"
require "tempfile"

module Binpacker
  # Runs tests serially to generate an initial Timing file.
  class Calibration
    def initialize(config)
      @config = config
      @timing = Timing.new(config.timing_file)
    end

    # Runs each Test serially and appends its measured Weight to the Timing file.
    # With incremental: true, Tests that already have a measured Weight are skipped.
    def run(tests, incremental: false)
      targets = incremental ? unmeasured(tests) : tests
      results = []

      targets.each do |test|
        elapsed = run_single(test)
        results << { file: test.file, name: test.name, time: elapsed }
      end

      @timing.append_all(results)
      results
    end

    private

    def unmeasured(tests)
      measured = @timing.load_raw
      tests.reject { |test| measured.key?([@timing.normalize_path(test.file), test.name]) }
    end

    def run_single(test)
      outfile = Tempfile.new("binpacker-cal")
      outfile.close

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      case @config.test_runner
      when "rspec"
        cmd = [
          "rspec", test.file,
          "--example", test.name,
          "--format", "json", "--out", outfile.path
        ]
      when "minitest"
        cmd = ["ruby", "-Ilib:test", test.file, "--name", "/^#{Regexp.escape(test.name)}$/"]
      else
        raise ConfigError, "unsupported runner for calibration: #{@config.test_runner}"
      end

      system(*cmd, exception: false)

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      elapsed
    ensure
      outfile&.unlink if outfile
    end
  end
end
