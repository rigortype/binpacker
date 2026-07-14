# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'binpacker/timing'
require 'binpacker/test_discovery'

RSpec.describe Binpacker::Timing do
  subject(:timing) { described_class.new(path) }

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  let(:path) { File.join(@dir, 'binpacker.timings') }

  describe 'UTF-8 handling' do
    let(:unicode_file) { 'spec/テスト_spec.rb' }
    let(:unicode_name) { 'テスト 正常系 ユーザー登録' }
    let(:elapsed) { 1.23 }

    describe '#append and #load_raw' do
      it 'roundtrips a UTF-8 test name' do
        timing.append(file: unicode_file, name: unicode_name, time: elapsed)

        raw = timing.load_raw
        expect(raw).to have_key([unicode_file, unicode_name])
      end

      it 'preserves the elapsed time for a UTF-8 entry' do
        timing.append(file: unicode_file, name: unicode_name, time: elapsed)

        raw = timing.load_raw
        expect(raw[[unicode_file, unicode_name]]).to be_within(0.001).of(elapsed)
      end

      it 'writes the file in UTF-8 encoding' do
        timing.append(file: unicode_file, name: unicode_name, time: elapsed)

        content = File.read(path, encoding: 'UTF-8')
        expect(content.encoding).to eq(Encoding::UTF_8)
        expect(content).to include('テスト_spec.rb')
        expect(content).to include('テスト 正常系 ユーザー登録')
      end

      it 'returns strings with UTF-8 encoding' do
        timing.append(file: unicode_file, name: unicode_name, time: elapsed)

        raw = timing.load_raw
        key = raw.keys.first
        expect(key[0].encoding).to eq(Encoding::UTF_8)
        expect(key[1].encoding).to eq(Encoding::UTF_8)
      end
    end

    describe '#append_all and #load_per_file' do
      let(:entries) do
        [
          { file: unicode_file, name: "#{unicode_name} 1", time: 0.5 },
          { file: unicode_file, name: "#{unicode_name} 2", time: 1.0 }
        ]
      end

      it 'roundtrips multiple UTF-8 entries' do
        timing.append_all(entries)

        per_file = timing.load_per_file
        normalized = timing.normalize_path(unicode_file)
        expect(per_file).to have_key(normalized)
      end

      it 'sums times for UTF-8 entries in the same file' do
        timing.append_all(entries)

        per_file = timing.load_per_file
        normalized = timing.normalize_path(unicode_file)
        expect(per_file[normalized]).to be_within(0.001).of(1.5)
      end
    end

    describe '#load_with_fallback' do
      it 'matches UTF-8 test file paths against timing data' do
        timing.append(file: unicode_file, name: unicode_name, time: elapsed)

        test = Binpacker::Test.new(file: unicode_file, name: unicode_name)
        weights = timing.load_with_fallback([test])
        expect(weights[test.key]).to be_within(0.001).of(elapsed)
      end
    end
  end

  describe 'history-aware per-file weights' do
    it 'weighs a file by its recent samples, not the whole append-only history' do
      5.times { |i| timing.append(file: 'spec/a_spec.rb', name: 'a 1', time: 1.0 + i * 0.1) }

      per_file = timing.load_per_file
      # median of the last 3 samples (1.2, 1.3, 1.4), not the 6.0 sum of all 5
      expect(per_file['spec/a_spec.rb']).to be_within(0.001).of(1.3)
    end

    it 'keeps one anomalous sample from moving the weight' do
      [1.0, 50.0, 1.2].each { |t| timing.append(file: 'spec/a_spec.rb', name: 'a 1', time: t) }

      expect(timing.load_per_file['spec/a_spec.rb']).to be_within(0.001).of(1.2)
    end

    it 'sums per-example medians within a file' do
      timing.append(file: 'spec/a_spec.rb', name: 'a 1', time: 1.0)
      timing.append(file: 'spec/a_spec.rb', name: 'a 2', time: 2.0)

      expect(timing.load_per_file['spec/a_spec.rb']).to be_within(0.001).of(3.0)
    end

    it 'does not starve a newly added file relative to a long-lived one' do
      10.times { timing.append(file: 'spec/old_spec.rb', name: 'old 1', time: 1.0) }
      timing.append(file: 'spec/new_spec.rb', name: 'new 1', time: 1.0)

      per_file = timing.load_per_file
      expect(per_file['spec/old_spec.rb']).to be_within(0.001).of(per_file['spec/new_spec.rb'])
    end
  end

  describe '#compact!' do
    it 'bounds the file to MAX_SAMPLES_PER_TEST lines per test' do
      10.times { |i| timing.append(file: 'spec/a_spec.rb', name: 'a 1', time: 1.0 + i) }

      timing.compact!

      expect(File.readlines(path).size).to eq(described_class::MAX_SAMPLES_PER_TEST)
    end

    it 'preserves the most recent samples and weights' do
      10.times { |i| timing.append(file: 'spec/a_spec.rb', name: 'a 1', time: 1.0 + i) }
      before = timing.load_per_file

      timing.compact!

      expect(timing.load_per_file).to eq(before)
      expect(timing.load_raw[['spec/a_spec.rb', 'a 1']]).to be_within(0.001).of(10.0)
    end

    it 'is a no-op when no timing file exists' do
      expect { timing.compact! }.not_to raise_error
      expect(File.exist?(path)).to be false
    end
  end

  describe 'cache invalidation' do
    it 'sees entries appended after an earlier read' do
      timing.append(file: 'spec/a_spec.rb', name: 'a 1', time: 1.0)
      timing.load_raw

      timing.append(file: 'spec/b_spec.rb', name: 'b 1', time: 2.0)

      expect(timing.measured?(file: 'spec/b_spec.rb', name: 'b 1')).to be true
    end
  end
end
