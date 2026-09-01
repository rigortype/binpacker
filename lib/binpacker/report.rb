# frozen_string_literal: true

require 'json'

module Binpacker
  # Builds the machine-readable Run report: predicted versus actual per-Worker
  # durations plus the worst per-Test Drift. See docs/design/run-report-format.md.
  class Report
    SCHEMA = 1
    DRIFT_LIMIT = 10

    def initialize(profile:, algorithm:, predicted_loads:, worker_stats:, all_timings:, timings:,
                   shard: nil, discovered: nil, selected: nil)
      @profile = profile
      @algorithm = algorithm
      @predicted_loads = predicted_loads
      @worker_stats = worker_stats
      @all_timings = all_timings
      @timings = timings
      @shard = shard
      @discovered = discovered
      @selected = selected
    end

    def to_h
      predicted = @predicted_loads
      actual = @worker_stats.map { |s| s[:total_time] }

      {
        schema: SCHEMA,
        profile: @profile,
        algorithm: @algorithm,
        shard: shard_section,
        worker_count: @worker_stats.size,
        predicted_makespan: round(predicted.max || 0.0),
        actual_makespan: round(actual.max || 0.0),
        workers: workers,
        balance: {
          predicted_deviation_pct: deviation_pct(predicted),
          actual_deviation_pct: deviation_pct(actual)
        },
        drift: drift
      }
    end

    def write(path)
      File.write(path, JSON.pretty_generate(to_h))
    end

    private

    # The audit trail for a sharded run, and the reason `discovered` is recorded at all.
    #
    # Shards never talk to each other: each computes the same N-way partition and trusts the others to have
    # computed it identically. They do so only while they agree on the timing data the partition is cut
    # from, which in CI means every shard restoring the same timing cache. A shard that restores a
    # different one — a cache miss where its siblings hit — partitions differently, and the failure is
    # silent: tests land in no shard at all and the build stays green.
    #
    # `discovered` is the whole-suite count before slicing, so it agrees across shards that see the same
    # repository. `selected` is this shard's slice. Summing `selected` over a matrix's reports and
    # comparing to the shared `discovered` turns that silent skip into a failure —
    # `binpacker shards-check` does exactly that.
    def shard_section
      return nil unless @shard

      {
        index: @shard.index,
        total: @shard.total,
        discovered_tests: @discovered,
        selected_tests: @selected
      }
    end

    def workers
      @worker_stats.map.with_index do |s, i|
        {
          id: i,
          predicted: round(@predicted_loads[i] || 0.0),
          actual: round(s[:total_time]),
          tests: s[:files],
          examples: s[:examples]
        }
      end
    end

    # Drift is reported per file (the scheduling unit), so predicted and actual
    # are compared at the same granularity even when timings are recorded
    # per example. Both sides are aggregated to normalized file paths.
    def drift
      actual = aggregate_by_file(@all_timings.map { |e| [e[:file], e[:time]] })
      predicted = aggregate_by_file(@timings.map { |(file, _name), weight| [file, weight] })

      (actual.keys | predicted.keys)
        .map { |file| drift_entry(file, predicted[file], actual[file]) }
        .sort_by { |d| -(d[:actual] - d[:predicted]).abs }
        .first(DRIFT_LIMIT)
    end

    def drift_entry(file, predicted, actual)
      {
        file: file,
        predicted: round(predicted || Timing::DEFAULT_WEIGHT),
        actual: round(actual || 0.0)
      }
    end

    def aggregate_by_file(pairs)
      pairs.each_with_object(Hash.new(0.0)) do |(file, time), acc|
        acc[normalize_file(file)] += time
      end
    end

    def normalize_file(file)
      file.to_s.sub(%r{\A\./}, '')
    end

    def deviation_pct(loads)
      return 0.0 if loads.empty?

      mean = loads.sum / loads.size
      return 0.0 unless mean.positive?

      max_dev = loads.map { |t| (t - mean).abs }.max
      round(max_dev / mean * 100)
    end

    def round(value)
      value.to_f.round(3)
    end
  end
end
