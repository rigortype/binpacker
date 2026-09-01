# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Binpacker::Shard do
  let(:tests) do
    [
      Binpacker::Test.new(file: 'heavy.rb', name: 'heavy'),
      Binpacker::Test.new(file: 'medium.rb', name: 'medium'),
      Binpacker::Test.new(file: 'light.rb', name: 'light'),
      Binpacker::Test.new(file: 'tiny.rb', name: 'tiny'),
      Binpacker::Test.new(file: 'extra.rb', name: 'extra')
    ]
  end

  let(:timings) do
    {
      ['heavy.rb', 'heavy'] => 100.0,
      ['medium.rb', 'medium'] => 50.0,
      ['extra.rb', 'extra'] => 40.0,
      ['light.rb', 'light'] => 10.0,
      ['tiny.rb', 'tiny'] => 1.0
    }
  end

  let(:scheduler) { Binpacker::LptScheduler.new }

  describe '.parse' do
    it 'reads the K/N form' do
      shard = described_class.parse('2/3')

      expect([shard.index, shard.total]).to eq([2, 3])
    end

    it 'tolerates surrounding and interior whitespace' do
      expect(described_class.parse(' 1 / 4 ').to_s).to eq('1/4')
    end

    it 'returns nil for nil, so an unsharded run needs no special case at the call site' do
      expect(described_class.parse(nil)).to be_nil
    end

    it 'returns nil for an empty string, which is what an unset CI matrix variable expands to' do
      expect(described_class.parse('')).to be_nil
      expect(described_class.parse('   ')).to be_nil
    end

    it 'rejects a malformed spec rather than guessing at it' do
      expect { described_class.parse('2 of 3') }.to raise_error(Binpacker::ConfigError, %r{expected the form K/N})
    end

    it 'rejects a 0 index, since the form is 1-based' do
      expect { described_class.parse('0/3') }.to raise_error(Binpacker::ConfigError, /between 1 and 3/)
    end

    it 'rejects an index past the shard count' do
      expect { described_class.parse('4/3') }.to raise_error(Binpacker::ConfigError, /between 1 and 3/)
    end

    it 'rejects a zero shard count' do
      expect { described_class.parse('1/0') }.to raise_error(Binpacker::ConfigError, /at least 1/)
    end
  end

  describe '#select' do
    def select(spec)
      described_class.parse(spec).select(tests: tests, timings: timings, scheduler: scheduler)
    end

    it 'covers every test exactly once across the shards' do
      selected = (1..3).flat_map { |i| select("#{i}/3") }

      expect(selected).to match_array(tests)
    end

    it 'balances by weight rather than by count' do
      loads = (1..2).map { |i| select("#{i}/2").sum { |t| timings.fetch(t.key) } }

      # 201.0 of weight over two shards; LPT reaches 100/101, and no split can do better than that.
      expect(loads.max - loads.min).to be <= 1.0
    end

    it 'is deterministic, so shards agree on the partition without talking to each other' do
      expect(select('2/3')).to eq(select('2/3'))
    end

    it 'returns every test for a single shard' do
      expect(select('1/1')).to match_array(tests)
    end

    it 'leaves trailing shards empty when there are fewer tests than shards' do
      shards = (1..8).map { |i| select("#{i}/8") }

      expect(shards.sum(&:size)).to eq(tests.size)
      expect(shards.count(&:empty?)).to eq(3)
    end
  end

  describe '#whole_suite?' do
    it 'is true only when there is one shard' do
      expect(described_class.parse('1/1').whole_suite?).to be(true)
      expect(described_class.parse('1/2').whole_suite?).to be(false)
    end
  end
end
