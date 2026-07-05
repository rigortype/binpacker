# frozen_string_literal: true

require "json"

module Binpacker
  # Builds the machine-readable Run report: predicted versus actual per-Worker
  # durations plus the worst per-Test Drift. See docs/design/run-report-format.md.
  class Report
    SCHEMA = 1
    DRIFT_LIMIT = 10

    def initialize(profile:, algorithm:, predicted_loads:, worker_stats:, all_timings:, timings:)
      @profile = profile
      @algorithm = algorithm
      @predicted_loads = predicted_loads
      @worker_stats = worker_stats
      @all_timings = all_timings
      @timings = timings
    end

    def to_h
      predicted = @predicted_loads
      actual = @worker_stats.map { |s| s[:total_time] }

      {
        schema: SCHEMA,
        profile: @profile,
        algorithm: @algorithm,
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

    def workers
      @worker_stats.map.with_index do |s, i|
        {
          id: i,
          predicted: round(@predicted_loads[i] || 0.0),
          actual: round(s[:total_time]),
          files: s[:files],
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
      file.to_s.sub(%r{\A\./}, "")
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
