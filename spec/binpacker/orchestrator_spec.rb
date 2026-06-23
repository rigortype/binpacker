# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Binpacker::Orchestrator do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      Dir.chdir(dir) { example.run }
    end
  end

  describe "dynamic scheduling" do
    it "persists timing records for batches completed through the active loop" do
      FileUtils.mkdir_p("spec")
      File.write("spec/a_spec.rb", <<~RUBY)
        RSpec.describe "a" do
          it "passes" do
            expect(1 + 1).to eq(2)
          end
        end
      RUBY

      result = described_class.new(config).run

      expect(result[:passed]).to be true
      expect(result[:timings]).not_to be_empty
      expect(result[:timings].map { |t| t[:file] }).to include(a_string_including("a_spec.rb"))

      expect(File.exist?("binpacker.timings")).to be true
      recorded = File.readlines("binpacker.timings").map { |line| JSON.parse(line) }
      expect(recorded.map { |r| r["file"] }).to include(a_string_including("a_spec.rb"))
    end
  end

  def config
    double("config").tap do |config|
      allow(config).to receive(:test_runner).and_return("rspec")
      allow(config).to receive(:test_pattern).and_return("spec/**/*_spec.rb")
      allow(config).to receive(:test_exclude).and_return([])
      allow(config).to receive(:timing_file).and_return("binpacker.timings")
      allow(config).to receive(:worker_count).and_return(1)
      allow(config).to receive(:scheduler).and_return({ "algorithm" => "lpt", "steal_enabled" => true })
    end
  end
end
