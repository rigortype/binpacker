# frozen_string_literal: true

require "spec_helper"

RSpec.describe Binpacker::WorkerQueue do
  let(:tests) do
    [
      Binpacker::Test.new(file: "a.rb", name: "a"),
      Binpacker::Test.new(file: "b.rb", name: "b"),
      Binpacker::Test.new(file: "c.rb", name: "c")
    ]
  end

  describe "#pop" do
    it "returns tests in FIFO order" do
      q = described_class.new(0, tests)
      expect(q.pop.file).to eq("a.rb")
      expect(q.pop.file).to eq("b.rb")
      expect(q.pop.file).to eq("c.rb")
    end

    it "returns nil when empty" do
      q = described_class.new(0, [])
      expect(q.pop).to be_nil
    end

    it "returns nil after all tests popped" do
      q = described_class.new(0, tests)
      3.times { q.pop }
      expect(q.pop).to be_nil
    end
  end

  describe "#empty?" do
    it "returns true for empty queue" do
      expect(described_class.new(0, []).empty?).to be true
    end

    it "returns false when tests remain" do
      q = described_class.new(0, tests)
      expect(q.empty?).to be false
    end

    it "returns true after all popped" do
      q = described_class.new(0, tests)
      3.times { q.pop }
      expect(q.empty?).to be true
    end
  end

  describe "#size" do
    it "returns initial test count" do
      expect(described_class.new(0, tests).size).to eq(3)
    end

    it "decrements after pop" do
      q = described_class.new(0, tests)
      q.pop
      expect(q.size).to eq(2)
    end
  end

  describe "#remaining" do
    it "returns all tests initially" do
      expect(described_class.new(0, tests).remaining.size).to eq(3)
    end

    it "returns only unpopped tests" do
      q = described_class.new(0, tests)
      q.pop
      expect(q.remaining.map(&:file)).to eq(%w[b.rb c.rb])
    end
  end

  describe "#total_weight" do
    it "sums weights of remaining tests" do
      q = described_class.new(0, tests)
      timings = { ["a.rb", "a"] => 10.0, ["b.rb", "b"] => 20.0, ["c.rb", "c"] => 30.0 }
      expect(q.total_weight(timings)).to eq(60.0)
    end

    it "defaults unknown tests to DEFAULT_WEIGHT" do
      q = described_class.new(0, tests)
      expect(q.total_weight({})).to be_within(0.01).of(3.0)
    end
  end

  describe "#push" do
    it "adds a test to the end" do
      q = described_class.new(0, tests)
      q.push(Binpacker::Test.new(file: "d.rb", name: "d"))
      expect(q.size).to eq(4)
    end
  end
end
