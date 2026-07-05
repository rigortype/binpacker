# frozen_string_literal: true

module Binpacker
  # Inspects the working directory to report binpacker's setup state and
  # recommend the next skill. Backs `binpacker describe`.
  # See docs/design/agent-workflows.md.
  class ProjectState
    CONFIG_FILE = "binpacker.yml"
    DEFAULT_TIMING_FILE = "binpacker.timings"
    SUPPORTED_FRAMEWORKS = %w[rspec minitest].freeze
    TESTUNIT_HINT = %r{test-unit|test/unit}

    def config_present?
      File.exist?(CONFIG_FILE)
    end

    def timing_present?
      File.exist?(timing_file)
    end

    # "rspec", "minitest", "test-unit", or nil. Minitest and test-unit share
    # the *_test.rb convention, so they are told apart by dependency hints.
    def framework
      return minitest_family if minitest_globs?
      return "rspec" if Dir.glob("spec/**/*_spec.rb").any?
      nil
    end

    # binpacker ships runners for rspec and minitest only. A detected framework
    # outside that set (e.g. test-unit) is unsupported; nil is merely unknown.
    def supported_framework?
      fw = framework
      fw.nil? || SUPPORTED_FRAMEWORKS.include?(fw)
    end

    def ci_wired?
      Dir.glob(".github/workflows/*.{yml,yaml}").any? do |wf|
        File.read(wf).include?("binpacker run")
      end
    end

    # The skill the agent should run next.
    def recommendation
      return "binpacker-setup" unless config_present? && timing_present?
      "binpacker-improve"
    end

    def to_h
      {
        config_present: config_present?,
        timing_present: timing_present?,
        framework: framework,
        ci_wired: ci_wired?,
        recommendation: recommendation
      }
    end

    private

    def minitest_globs?
      Dir.glob("test*/**/*_test.rb").any? || Dir.glob("test*/**/test_*.rb").any?
    end

    def minitest_family
      testunit_hinted? ? "test-unit" : "minitest"
    end

    def testunit_hinted?
      sources = Dir.glob("Gemfile") + Dir.glob("*.gemspec") + Dir.glob("test*/**/*_test.rb").first(5)
      sources.any? { |file| File.read(file).match?(TESTUNIT_HINT) }
    rescue StandardError
      false
    end

    def timing_file
      return DEFAULT_TIMING_FILE unless config_present?
      Config.new.timing_file
    rescue StandardError
      DEFAULT_TIMING_FILE
    end
  end
end
