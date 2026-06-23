# frozen_string_literal: true

require "yaml"
require "etc"

module Binpacker
  class Config
    attr_reader :profile

    DEFAULTS = {
      "test_runner" => "rspec",
      "workers" => "auto",
      "test_granularity" => "file",
      "timing_file" => "binpacker.timings",
      "test_pattern" => "spec/**/*_spec.rb",
      "test_exclude" => [],
      "scheduler" => {
        "strategy" => "static",
        "steal_enabled" => false,
        "algorithm" => "lpt"
      }
    }.freeze

    CI_ENV_VARS = %w[CI GITHUB_ACTIONS GITLAB_CI JENKINS_HOME].freeze

    def initialize(profile: nil, config_path: nil)
      @config_path = config_path || find_config
      @raw = load_config
      @profile = resolve_profile(profile)
      @merged = build_profile(@profile)
    end

    def method_missing(name, *)
      key = name.to_s
      if @merged.key?(key)
        @merged[key]
      else
        super
      end
    end

    def respond_to_missing?(name, *)
      @merged.key?(name.to_s) || super
    end

    def scheduler
      @merged["scheduler"]
    end

    def worker_count
      workers = @merged["workers"]
      return Etc.nprocessors if workers == "auto"
      Integer(workers)
    end

    private

    def find_config
      Pathname.pwd.join("binpacker.yml")
    end

    def load_config
      return {} unless @config_path.exist?
      data = YAML.safe_load_file(@config_path.to_s, permitted_classes: [Symbol])
      data || {}
    end

    def resolve_profile(explicit)
      return explicit if explicit
      return ENV["BINPACKER_PROFILE"] if ENV["BINPACKER_PROFILE"]
      return "ci" if ci_environment?
      "default"
    end

    def ci_environment?
      CI_ENV_VARS.any? { |v| ENV.key?(v) }
    end

    def build_profile(name)
      profiles = @raw.fetch("profiles", {})
      return DEFAULTS.dup if profiles.empty? && name == "default"
      entry = profiles[name]
      raise ConfigError, "profile '#{name}' not found in binpacker.yml" unless entry
      parent = entry["extends"]
      base = parent ? build_profile(parent) : DEFAULTS.dup
      deep_merge(base, entry.reject { |k, _| k == "extends" })
    end

    def deep_merge(base, override)
      base.merge(override) { |_key, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          old_val.merge(new_val)
        else
          new_val
        end
      }
    end
  end
end
