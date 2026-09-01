# frozen_string_literal: true

module Binpacker
  # One slice of the suite, for splitting a run across independent machines.
  #
  # Workers divide a suite across the cores of ONE machine and share its wall clock; a shard divides it
  # across machines that have no wall clock in common. So the two compose rather than compete: a CI matrix
  # of N jobs each passing `--shard k/N` runs `worker_count` workers over its own slice, and the suite's
  # wall time becomes roughly the slowest shard rather than the whole.
  #
  # The slice is cut by the SAME weight-balanced partitioner that assigns work to workers, over the same
  # measured timings — shards are just a coarser bin-packing of the same problem, so an equal-count split
  # would balance no better than round-robin. That also makes the cut deterministic: given one timing file,
  # every shard computes the identical N-way partition and takes only its own bin, so no shard needs to
  # know what the others decided, and every test lands in exactly one shard.
  class Shard
    attr_reader :index, :total

    # Parses the `k/n` form used by `--shard` and BINPACKER_SHARD. `k` is 1-based, so a matrix can pass its
    # own 1-based job number straight through.
    #
    # @param spec [String, nil]
    # @return [Shard, nil] nil when `spec` is nil or empty, i.e. an unsharded run.
    def self.parse(spec)
      return nil if spec.nil? || spec.to_s.strip.empty?

      match = %r{\A\s*(\d+)\s*/\s*(\d+)\s*\z}.match(spec.to_s)
      raise ConfigError, "invalid shard #{spec.inspect}: expected the form K/N, e.g. 1/3" unless match

      new(index: Integer(match[1]), total: Integer(match[2]))
    end

    def initialize(index:, total:)
      raise ConfigError, "shard count must be at least 1, got #{total}" if total < 1
      raise ConfigError, "shard index must be between 1 and #{total}, got #{index}" unless (1..total).cover?(index)

      @index = index
      @total = total
      freeze
    end

    def to_s
      "#{index}/#{total}"
    end

    # Whole-suite runs still construct no Shard, so this is only ever true for an explicit `--shard 1/1`.
    def whole_suite?
      total == 1
    end

    # @param tests [Array<Test>] every test discovered, before any slicing
    # @param timings [Hash] predicted weight per test key, as `Timing#load_with_fallback` returns
    # @param scheduler [Scheduler] the same partitioner the run uses for workers
    # @return [Array<Test>] the tests belonging to this shard
    def select(tests:, timings:, scheduler:)
      return tests if whole_suite?

      bins = scheduler.partition(tests: tests, worker_count: total, timings: timings)
      bins[index - 1].remaining
    end
  end
end
