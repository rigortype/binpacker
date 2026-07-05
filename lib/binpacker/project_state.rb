# frozen_string_literal: true

module Binpacker
  # Inspects the working directory to report binpacker's setup state and
  # recommend the next skill. Backs `binpacker describe`.
  # See docs/design/agent-workflows.md.
  class ProjectState
    CONFIG_FILE = "binpacker.yml"
    DEFAULT_TIMING_FILE = "binpacker.timings"

    def config_present?
      File.exist?(CONFIG_FILE)
    end

    def timing_present?
      File.exist?(timing_file)
    end

    def framework
      return "minitest" if Dir.glob("test*/**/*_test.rb").any?
      return "minitest" if Dir.glob("test*/**/test_*.rb").any?
      return "rspec" if Dir.glob("spec/**/*_spec.rb").any?
      nil
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

    def timing_file
      return DEFAULT_TIMING_FILE unless config_present?
      Config.new.timing_file
    rescue StandardError
      DEFAULT_TIMING_FILE
    end
  end
end
