# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Binpacker::ProjectState do
  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { example.run }
    end
  end

  subject(:state) { described_class.new }

  describe "an unconfigured project" do
    it "reports missing config and recommends setup" do
      expect(state.config_present?).to be false
      expect(state.recommendation).to eq("binpacker-setup")
    end
  end

  describe "framework detection" do
    it "detects rspec from a spec glob" do
      FileUtils.mkdir_p("spec")
      File.write("spec/a_spec.rb", "")
      expect(state.framework).to eq("rspec")
    end

    it "detects minitest from a test glob" do
      FileUtils.mkdir_p("test")
      File.write("test/a_test.rb", "")
      expect(state.framework).to eq("minitest")
    end
  end

  describe "a fully configured project" do
    it "recommends improve when config and timing data are present" do
      File.write("binpacker.yml", "profiles:\n  default:\n    timing_file: binpacker.timings\n")
      File.write("binpacker.timings", "")
      expect(state.recommendation).to eq("binpacker-improve")
    end
  end

  describe "#ci_wired?" do
    it "is true when a workflow runs binpacker" do
      FileUtils.mkdir_p(".github/workflows")
      File.write(".github/workflows/ci.yml", "steps:\n  - run: binpacker run --profile ci\n")
      expect(state.ci_wired?).to be true
    end

    it "is false without a binpacker workflow" do
      expect(state.ci_wired?).to be false
    end
  end
end
