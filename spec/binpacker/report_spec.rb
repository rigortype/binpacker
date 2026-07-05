# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "binpacker/report"
require "binpacker/timing"

RSpec.describe Binpacker::Report do
  let(:worker_stats) do
    [
      { files: 2, total_time: 10.0, examples: 20, passed: 20 },
      { files: 2, total_time: 6.0, examples: 12, passed: 12 }
    ]
  end

  let(:predicted_loads) { [8.0, 8.0] }

  let(:timings) do
    {
      %w[spec/a_spec.rb A] => 5.0,
      %w[spec/b_spec.rb B] => 3.0,
      %w[spec/c_spec.rb C] => 3.0
    }
  end

  let(:all_timings) do
    [
      { file: "spec/a_spec.rb", name: "A", time: 9.0 }, # drift 4.0
      { file: "spec/b_spec.rb", name: "B", time: 3.2 }, # drift 0.2
      { file: "spec/c_spec.rb", name: "C", time: 3.0 }  # drift 0.0
    ]
  end

  subject(:report) do
    described_class.new(
      profile: "ci",
      algorithm: "multifit",
      predicted_loads: predicted_loads,
      worker_stats: worker_stats,
      all_timings: all_timings,
      timings: timings
    )
  end

  describe "#to_h" do
    it "reports metadata and makespans" do
      h = report.to_h

      expect(h[:schema]).to eq(described_class::SCHEMA)
      expect(h[:profile]).to eq("ci")
      expect(h[:algorithm]).to eq("multifit")
      expect(h[:worker_count]).to eq(2)
      expect(h[:predicted_makespan]).to eq(8.0)
      expect(h[:actual_makespan]).to eq(10.0)
    end

    it "emits one entry per worker with predicted and actual" do
      workers = report.to_h[:workers]

      expect(workers.map { |w| w[:id] }).to eq([0, 1])
      expect(workers[0]).to include(predicted: 8.0, actual: 10.0, tests: 2, examples: 20)
    end

    it "computes predicted and actual balance deviation" do
      balance = report.to_h[:balance]

      # predicted is perfectly balanced, actual mean 8.0 with max dev 2.0 -> 25%
      expect(balance[:predicted_deviation_pct]).to eq(0.0)
      expect(balance[:actual_deviation_pct]).to eq(25.0)
    end

    it "ranks per-file drift by absolute predicted-vs-actual gap, largest first" do
      drift = report.to_h[:drift]

      expect(drift.first).to include(file: "spec/a_spec.rb", predicted: 5.0, actual: 9.0)
      expect(drift.map { |d| d[:file] }).to eq(%w[spec/a_spec.rb spec/b_spec.rb spec/c_spec.rb])
      expect(drift.first).not_to have_key(:name)
    end

    it "aggregates per-example actuals to file level before ranking drift" do
      r = described_class.new(
        profile: "ci", algorithm: "multifit", predicted_loads: [1.0],
        worker_stats: [{ files: 1, total_time: 6.0, examples: 3, passed: 3 }],
        all_timings: [
          { file: "./spec/a_spec.rb", name: "ex1", time: 2.0 },
          { file: "./spec/a_spec.rb", name: "ex2", time: 4.0 }
        ],
        timings: { %w[spec/a_spec.rb spec/a_spec.rb] => 1.0 }
      )

      drift = r.to_h[:drift]
      expect(drift.size).to eq(1)
      # "./spec/a_spec.rb" and "spec/a_spec.rb" normalize together; actual sums to 6.0
      expect(drift.first).to include(file: "spec/a_spec.rb", predicted: 1.0, actual: 6.0)
    end

    it "caps drift at DRIFT_LIMIT entries" do
      many = Array.new(25) { |i| { file: "spec/#{i}_spec.rb", name: "T#{i}", time: i.to_f } }
      r = described_class.new(
        profile: "ci", algorithm: "lpt", predicted_loads: [0.0],
        worker_stats: [{ files: 25, total_time: 1.0, examples: 25, passed: 25 }],
        all_timings: many, timings: {}
      )

      expect(r.to_h[:drift].size).to eq(described_class::DRIFT_LIMIT)
    end
  end

  describe "#write" do
    it "writes pretty JSON to the given path" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "report.json")
        report.write(path)

        parsed = JSON.parse(File.read(path))
        expect(parsed["schema"]).to eq(described_class::SCHEMA)
        expect(parsed["workers"].size).to eq(2)
      end
    end
  end
end
