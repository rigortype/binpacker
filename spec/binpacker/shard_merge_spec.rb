# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Binpacker::ShardMerge do
  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { example.run }
    end
  end

  def write(path, entries)
    timing = Binpacker::Timing.new(path)
    timing.append_all(entries.map { |file, name, time| { file: file, name: name, time: time } })
  end

  def samples(path)
    Binpacker::Timing.new(path).samples
  end

  # The base every shard restored, then each shard's write-back: its own slice re-measured (one sample
  # appended and compacted), everyone else's tests exactly as restored.
  before do
    base = [['spec/a_spec.rb', 'a', 1.0], ['spec/b_spec.rb', 'b', 2.0], ['spec/c_spec.rb', 'c', 3.0]]
    write('base.timings', base)
    write('shard-1.timings', base + [['spec/a_spec.rb', 'a', 1.5]])
    write('shard-2.timings', base + [['spec/b_spec.rb', 'b', 2.5], ['spec/new_spec.rb', 'n', 4.0]])
  end

  it "keeps every shard's re-measured tests and the untouched rest of the base" do
    result = described_class.call(base: 'base.timings', shards: %w[shard-1.timings shard-2.timings],
                                  output: 'merged.timings')

    expect(samples('merged.timings')).to eq(
      %w[spec/a_spec.rb a] => [1.0, 1.5],
      %w[spec/b_spec.rb b] => [2.0, 2.5],
      %w[spec/c_spec.rb c] => [3.0],
      %w[spec/new_spec.rb n] => [4.0]
    )
    expect(result.to_h).to eq(tests: 4, updated: 3, conflicts: 0)
  end

  it 'takes every test as new on a cold start' do
    result = described_class.call(base: nil, shards: %w[shard-2.timings], output: 'merged.timings')

    expect(result.updated).to eq(4)
    expect(samples('merged.timings')).to eq(samples('shard-2.timings'))
  end

  it 'lets the later file win, and counts the conflict, when two shards re-measured one test' do
    write('shard-3.timings', [['spec/a_spec.rb', 'a', 1.0], ['spec/a_spec.rb', 'a', 9.0]])

    result = described_class.call(base: 'base.timings', shards: %w[shard-1.timings shard-3.timings],
                                  output: 'merged.timings')

    expect(samples('merged.timings')[%w[spec/a_spec.rb a]]).to eq([1.0, 9.0])
    expect(result.conflicts).to eq(1)
  end

  it 'may write over its own base' do
    described_class.call(base: 'base.timings', shards: %w[shard-1.timings], output: 'base.timings')

    expect(samples('base.timings')[%w[spec/a_spec.rb a]]).to eq([1.0, 1.5])
  end
end
