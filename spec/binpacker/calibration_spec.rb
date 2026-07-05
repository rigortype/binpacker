# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "binpacker/timing"
require "binpacker/calibration"
require "binpacker/test_discovery"

RSpec.describe Binpacker::Calibration do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  let(:timing_path) { File.join(@dir, "binpacker.timings") }

  let(:config) do
    double("config").tap do |c|
      allow(c).to receive(:test_runner).and_return("rspec")
      allow(c).to receive(:timing_file).and_return(timing_path)
    end
  end

  subject(:calibration) { described_class.new(config) }

  let(:test_a) { Binpacker::Test.new(file: "spec/a_spec.rb", name: "A works") }
  let(:test_b) { Binpacker::Test.new(file: "spec/b_spec.rb", name: "B works") }

  before do
    # Avoid actually shelling out to a test runner.
    allow(calibration).to receive(:run_single) { |test| test.file == "spec/a_spec.rb" ? 1.5 : 2.5 }
  end

  describe "#run" do
    it "measures every test and appends the results" do
      results = calibration.run([test_a, test_b])

      expect(results.map { |r| r[:file] }).to contain_exactly("spec/a_spec.rb", "spec/b_spec.rb")
      expect(Binpacker::Timing.new(timing_path).load_raw.size).to eq(2)
    end
  end

  describe "#run with incremental: true" do
    it "skips tests that already have measured timing data" do
      Binpacker::Timing.new(timing_path).append(file: test_a.file, name: test_a.name, time: 9.9)

      results = calibration.run([test_a, test_b], incremental: true)

      expect(results.map { |r| r[:file] }).to contain_exactly("spec/b_spec.rb")
      expect(calibration).to have_received(:run_single).once
    end

    it "measures all tests when the timing file is empty" do
      results = calibration.run([test_a, test_b], incremental: true)

      expect(results.size).to eq(2)
    end

    it "matches measured tests regardless of relative path spelling" do
      Binpacker::Timing.new(timing_path).append(file: "./spec/a_spec.rb", name: test_a.name, time: 9.9)

      results = calibration.run([test_a, test_b], incremental: true)

      expect(results.map { |r| r[:file] }).to contain_exactly("spec/b_spec.rb")
    end
  end
end
