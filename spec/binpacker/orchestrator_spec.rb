# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe Binpacker::Orchestrator do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      Dir.chdir(dir) { example.run }
    end
  end

  describe 'dynamic scheduling' do
    it 'persists timing records for batches completed through the active loop' do
      FileUtils.mkdir_p('spec')
      File.write('spec/a_spec.rb', <<~RUBY)
        RSpec.describe "a" do
          it "passes" do
            expect(1 + 1).to eq(2)
          end
        end
      RUBY

      result = described_class.new(config).run

      expect(result[:passed]).to be true
      expect(result[:timings]).not_to be_empty
      expect(result[:timings].map { |t| t[:file] }).to include(a_string_including('a_spec.rb'))

      expect(File.exist?('binpacker.timings')).to be true
      recorded = File.readlines('binpacker.timings').map { |line| JSON.parse(line) }
      expect(recorded.map { |r| r['file'] }).to include(a_string_including('a_spec.rb'))
    end
  end

  describe 'run report' do
    it 'writes a JSON report to report_path' do
      FileUtils.mkdir_p('spec')
      File.write('spec/a_spec.rb', <<~RUBY)
        RSpec.describe "a" do
          it "passes" do
            expect(1 + 1).to eq(2)
          end
        end
      RUBY

      described_class.new(config, report_path: 'report.json').run

      expect(File.exist?('report.json')).to be true
      report = JSON.parse(File.read('report.json'))
      expect(report['schema']).to eq(Binpacker::Report::SCHEMA)
      expect(report['algorithm']).to eq('lpt')
      expect(report['workers']).not_to be_empty
    end

    it 'writes no report when report_path is nil' do
      FileUtils.mkdir_p('spec')
      File.write('spec/a_spec.rb', <<~RUBY)
        RSpec.describe "a" do
          it "passes" do
            expect(1 + 1).to eq(2)
          end
        end
      RUBY

      described_class.new(config).run

      expect(Dir.glob('*.json')).to be_empty
    end
  end

  describe '#drain_batch' do
    let(:orchestrator) { described_class.new(config) }

    def queue_with(weights, min_batch_weight: described_class::MIN_BATCH_WEIGHT)
      queue = Binpacker::WorkerQueue.new(0)
      timings = {}
      weights.each_with_index do |w, i|
        test = Binpacker::Test.new(file: "spec/#{i}_spec.rb", name: nil)
        queue.push(test)
        timings[test.key] = w
      end
      orchestrator.instance_variable_set(:@timings, timings)
      orchestrator.instance_variable_set(:@min_batch_weight, min_batch_weight)
      queue
    end

    it 'halves the remaining predicted weight per batch' do
      queue = queue_with(Array.new(10, 20.0)) # 200s total

      batch = orchestrator.send(:drain_batch, queue)

      # target = 200/2 = 100s -> 5 files of 20s
      expect(batch.size).to eq(5)
    end

    it 'keeps draining small tails in MIN_BATCH_WEIGHT chunks' do
      queue = queue_with(Array.new(8, 5.0)) # 40s total

      batch = orchestrator.send(:drain_batch, queue)

      # target = max(40/2, 30) = 30s -> 6 files of 5s
      expect(batch.size).to eq(6)
    end

    it 'always drains at least one test regardless of weight' do
      queue = queue_with([500.0])

      expect(orchestrator.send(:drain_batch, queue).size).to eq(1)
    end

    it 'returns an empty batch for an empty queue' do
      queue = queue_with([])

      expect(orchestrator.send(:drain_batch, queue)).to be_empty
    end

    it 'honors a scale-free cold-start floor instead of MIN_BATCH_WEIGHT' do
      # cold-start floor of 10 (not 30): target = max(40/2, 10) = 20 -> 4 files
      queue = queue_with(Array.new(8, 5.0), min_batch_weight: 10.0)

      expect(orchestrator.send(:drain_batch, queue).size).to eq(4)
    end
  end

  describe '#min_batch_weight' do
    def orchestrator_with(worker_count)
      cfg = config
      allow(cfg).to receive(:worker_count).and_return(worker_count)
      described_class.new(cfg)
    end

    it 'uses the fixed MIN_BATCH_WEIGHT when the project is calibrated' do
      orchestrator = orchestrator_with(4)
      timing = instance_double(Binpacker::Timing, calibrated?: true)

      weight = orchestrator.send(:min_batch_weight, timing, { 'a' => 200.0 })
      expect(weight).to eq(described_class::MIN_BATCH_WEIGHT)
    end

    it 'targets COLD_START_BATCHES_PER_WORKER batches per worker on a cold start' do
      orchestrator = orchestrator_with(4)
      timing = instance_double(Binpacker::Timing, calibrated?: false)
      timings = { 'a' => 120.0, 'b' => 80.0 } # total 200

      # 200 / (4 workers * 5 batches) = 10.0
      weight = orchestrator.send(:min_batch_weight, timing, timings)
      expect(weight).to be_within(0.001).of(10.0)
    end

    it 'falls back to MIN_BATCH_WEIGHT when total predicted weight is zero' do
      orchestrator = orchestrator_with(4)
      timing = instance_double(Binpacker::Timing, calibrated?: false)

      weight = orchestrator.send(:min_batch_weight, timing, { 'a' => 0.0 })
      expect(weight).to eq(described_class::MIN_BATCH_WEIGHT)
    end

    it 'falls back to MIN_BATCH_WEIGHT when there are no workers' do
      orchestrator = orchestrator_with(0)
      timing = instance_double(Binpacker::Timing, calibrated?: false)

      weight = orchestrator.send(:min_batch_weight, timing, { 'a' => 200.0 })
      expect(weight).to eq(described_class::MIN_BATCH_WEIGHT)
    end
  end

  def config
    double('config').tap do |config|
      allow(config).to receive(:test_runner).and_return('rspec')
      allow(config).to receive(:test_pattern).and_return('spec/**/*_spec.rb')
      allow(config).to receive(:test_exclude).and_return([])
      allow(config).to receive(:timing_file).and_return('binpacker.timings')
      allow(config).to receive(:worker_count).and_return(1)
      allow(config).to receive(:profile).and_return('default')
      allow(config).to receive(:scheduler).and_return({ 'algorithm' => 'lpt', 'steal_enabled' => true })
    end
  end
end
