# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Binpacker::Config do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  let(:config_path) { Pathname(File.join(@dir, "binpacker.yml")) }

  def write_config(yaml)
    config_path.write(yaml)
  end

  describe "profile resolution" do
    around do |example|
      with_env("CI" => nil, "GITHUB_ACTIONS" => nil, "GITLAB_CI" => nil, "JENKINS_HOME" => nil) { example.run }
    end
    it "defaults to 'default' when no env or CI" do
      write_config(<<~YAML)
        profiles:
          default:
            test_runner: rspec
            test_pattern: spec/**/*_spec.rb
      YAML
      config = described_class.new(config_path: config_path)
      expect(config.profile).to eq("default")
    end

    it "uses BINPACKER_PROFILE env var" do
      write_config(<<~YAML)
        profiles:
          default:
            test_runner: rspec
          ci:
            test_runner: rspec
            workers: 8
      YAML
      with_env("BINPACKER_PROFILE" => "ci") do
        config = described_class.new(config_path: config_path)
        expect(config.profile).to eq("ci")
      end
    end
  end

  describe "profile inheritance" do
    it "merges parent keys" do
      write_config(<<~YAML)
        profiles:
          default:
            test_runner: rspec
            workers: auto
          ci:
            extends: default
            workers: 8
      YAML
      config = described_class.new(profile: "ci", config_path: config_path)
      expect(config.test_runner).to eq("rspec")
      expect(config.worker_count).to eq(8)
    end

    it "merges nested scheduler hash shallowly" do
      write_config(<<~YAML)
        profiles:
          default:
            scheduler:
              algorithm: lpt
              steal_enabled: false
          ci:
            extends: default
            scheduler:
              steal_enabled: true
      YAML
      config = described_class.new(profile: "ci", config_path: config_path)
      expect(config.scheduler["steal_enabled"]).to be true
    end
  end

  describe "defaults" do
    around do |example|
      with_env("CI" => nil, "GITHUB_ACTIONS" => nil, "GITLAB_CI" => nil, "JENKINS_HOME" => nil) { example.run }
    end
    it "uses built-in defaults when no config exists" do
      config = described_class.new(config_path: config_path)
      expect(config.test_runner).to eq("rspec")
      expect(config.scheduler["algorithm"]).to eq("lpt")
    end

    it "returns CPU count for workers: auto" do
      config = described_class.new(config_path: config_path)
      expect(config.worker_count).to be_a(Integer)
      expect(config.worker_count).to be > 0
    end
  end

  describe "validation" do
    it "raises on unknown profile" do
      write_config("profiles:\n  default:\n    test_runner: rspec\n")
      expect {
        described_class.new(profile: "nonexistent", config_path: config_path)
      }.to raise_error(Binpacker::ConfigError)
    end
  end

  private

  def with_env(overrides)
    old = {}
    overrides.each { |k, v| old[k] = ENV[k]; ENV[k] = v }
    yield
  ensure
    overrides.each { |k, _| ENV[k] = old[k] }
  end
end
