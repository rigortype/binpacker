# frozen_string_literal: true

module Binpacker
  # Folds the timing files a sharded matrix wrote back into one.
  #
  # Every shard starts from the same timing file (it must, to cut the same partition), measures only its own
  # slice, and writes the whole file back: its slice's tests with a fresh sample, everyone else's exactly as
  # restored. A CI cache can keep one of those files, not all of them, so without a merge each run's history
  # gains one shard's measurements and loses the rest — the other slices' weights age until a run happens to
  # put their files in the shard whose file was kept.
  #
  # The merge needs no record of which shard ran what: a test a shard did not run is byte-for-byte what the
  # base held, so per test, the shard whose samples differ from the base is the one that measured it. In a
  # coherent split that is at most one shard. Should two disagree anyway (an overlapping partition — which
  # `shards-check` exists to catch), the later file on the command line wins, and the test is counted in
  # Result#conflicts rather than dropped.
  class ShardMerge
    Result = Struct.new(:tests, :updated, :conflicts, keyword_init: true)

    def self.call(base:, shards:, output:)
      new(base: base, shards: shards, output: output).call
    end

    def initialize(base:, shards:, output:)
      @base = base
      @shards = shards
      @output = output
    end

    def call
      base = @base ? Timing.new(@base).samples : {}
      merged = base.dup
      writers = Hash.new(0)

      @shards.each do |path|
        Timing.new(path).samples.each do |key, times|
          next if base[key] == times

          writers[key] += 1
          merged[key] = times
        end
      end

      Timing.new(@output).write_samples(merged)
      Result.new(tests: merged.size, updated: writers.size, conflicts: writers.count { |_key, n| n > 1 })
    end
  end
end
