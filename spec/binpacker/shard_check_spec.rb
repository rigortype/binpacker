# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'

RSpec.describe Binpacker::ShardCheck do
  around do |example|
    Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } }
  end

  # A run report carries much more than this; only the `shard` section is read here.
  def write_report(name, index:, total:, discovered:, selected:)
    File.write(name, JSON.generate(
                       schema: Binpacker::Report::SCHEMA,
                       shard: { index: index, total: total, discovered_tests: discovered,
                                selected_tests: selected }
                     ))
    name
  end

  def matrix(selected_per_shard, discovered: 100)
    selected_per_shard.each_with_index.map do |selected, i|
      write_report("shard-#{i + 1}.json", index: i + 1, total: selected_per_shard.size,
                                          discovered: discovered, selected: selected)
    end
  end

  it 'passes when the slices add up to the discovered suite' do
    result = described_class.call(matrix([40, 35, 25]))

    expect(result).to be_ok
    expect(result.summary).to eq('3 shards cover all 100 tests')
  end

  it 'fails when tests fell through the gaps between shards' do
    result = described_class.call(matrix([40, 35, 20]))

    expect(result).not_to be_ok
    expect(result.problems.first).to include('cover 95 of 100 tests', '5 ran no shard')
  end

  it 'names the cause, because the fix is upstream of the reports' do
    result = described_class.call(matrix([40, 35, 20]))

    expect(result.problems.first).to include('make every shard load the same timing file')
  end

  it 'fails when a test ran in more than one shard' do
    result = described_class.call(matrix([40, 35, 30]))

    expect(result.problems.first).to include('cover 105 of 100 tests', '5 ran in more than one shard')
  end

  it 'fails when a matrix job never reported' do
    reports = matrix([40, 35, 25])
    File.delete(reports.last)

    result = described_class.call(reports.first(2))

    expect(result.problems).to include(a_string_including('no report for shard 3 of 3'))
  end

  it 'fails when one shard reported twice' do
    a = write_report('a.json', index: 1, total: 2, discovered: 100, selected: 50)
    b = write_report('b.json', index: 1, total: 2, discovered: 100, selected: 50)

    result = described_class.call([a, b])

    expect(result.problems).to include(a_string_including('shard 1 reported more than once'))
  end

  it 'fails when the reports disagree on the shard count' do
    a = write_report('a.json', index: 1, total: 2, discovered: 100, selected: 50)
    b = write_report('b.json', index: 2, total: 3, discovered: 100, selected: 50)

    result = described_class.call([a, b])

    expect(result.problems).to include(a_string_including('disagree on shard count'))
  end

  # Different discovered counts mean the reports describe different suites (a stale checkout, a different
  # commit), so their sum says nothing about coverage.
  it 'fails when the reports disagree on how big the suite is' do
    a = write_report('a.json', index: 1, total: 2, discovered: 100, selected: 50)
    b = write_report('b.json', index: 2, total: 2, discovered: 90, selected: 50)

    result = described_class.call([a, b])

    expect(result.problems).to include(a_string_including('disagree on discovered test count'))
  end

  it 'rejects a report from an unsharded run rather than reading it as a one-shard matrix' do
    File.write('plain.json', JSON.generate(schema: Binpacker::Report::SCHEMA, worker_count: 4))

    result = described_class.call(['plain.json'])

    expect(result.problems).to include(a_string_including('no `shard` section'))
  end

  it 'reports an unreadable file instead of silently covering nothing' do
    expect(described_class.call(['absent.json']).problems).to include(a_string_including('no such file'))
  end

  it 'reports malformed JSON' do
    File.write('bad.json', '{not json')

    expect(described_class.call(['bad.json']).problems).to include(a_string_including('not valid JSON'))
  end

  it 'fails when given nothing to check' do
    expect(described_class.call([]).problems).to include('no run reports given')
  end
end
