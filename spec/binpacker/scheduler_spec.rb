# frozen_string_literal: true

require "spec_helper"

RSpec.describe Binpacker::LptScheduler do
  let(:tests) do
    [
      Binpacker::Test.new(file: "heavy.rb", name: "heavy"),
      Binpacker::Test.new(file: "light.rb", name: "light"),
      Binpacker::Test.new(file: "medium.rb", name: "medium"),
      Binpacker::Test.new(file: "tiny.rb", name: "tiny"),
      Binpacker::Test.new(file: "extra.rb", name: "extra")
    ]
  end

  let(:timings) do
    {
      ["heavy.rb", "heavy"] => 100.0,
      ["medium.rb", "medium"] => 50.0,
      ["light.rb", "light"] => 10.0,
      ["tiny.rb", "tiny"] => 1.0,
      ["extra.rb", "extra"] => 40.0
    }
  end

  describe "#partition" do
    it "returns correct number of queues" do
      queues = subject.partition(tests: tests, worker_count: 3, timings: timings)
      expect(queues.size).to eq(3)
    end

    it "assigns heavier tests first to balance load" do
      queues = subject.partition(tests: tests, worker_count: 2, timings: timings)
      loads = queues.map { |q| q.total_weight(timings) }
      # heaviest (100) goes to W0, second(50) to W1, third(40) to W1 (load 50), fourth(10) to W0 (load 100) — wait
      # Actually LPT: 100->W0, 50->W1, 40->W1(load 50), 10->W0(load 100), 1->W0(load 110)
      # Result: W0=111, W1=90, diff=21
      diff = (loads.max - loads.min).abs
      expect(diff).to be <= 25.0
    end

    it "handles empty test list" do
      queues = subject.partition(tests: [], worker_count: 3, timings: {})
      expect(queues.map(&:empty?)).to all(be true)
    end

    it "handles single worker" do
      queues = subject.partition(tests: tests, worker_count: 1, timings: timings)
      expect(queues.first.size).to eq(5)
    end

    it "respects worker limit when fewer tests than workers" do
      few_tests = tests.first(2)
      queues = subject.partition(tests: few_tests, worker_count: 5, timings: timings)
      non_empty = queues.reject(&:empty?)
      expect(non_empty.size).to eq(2)
    end
  end
end
