# frozen_string_literal: true

require 'json'

module Binpacker
  class Timing
    Entry = Struct.new(:file, :name, :time, keyword_init: true)

    DEFAULT_WEIGHT = 1.0

    # Samples retained per test by #compact! and consulted by the
    # median in #load_per_file. Three samples make a single anomalous
    # run (GC pause, noisy CI neighbour) unable to move the weight.
    MAX_SAMPLES_PER_TEST = 3

    def initialize(path)
      @path = Pathname(path)
    end

    # True once any timing samples exist, i.e. the project has been
    # calibrated at least once. Callers use this to tell a measured
    # run (weights in seconds) from a pure cold start (fallbacks only).
    def calibrated?
      !samples_by_test.empty?
    end

    def load_with_fallback(tests)
      per_file = load_per_file
      coefficient = seconds_per_kb(per_file)
      tests.each_with_object({}) do |test, hash|
        key = normalize_path(test.file)
        hash[test.key] = per_file.fetch(key) { fallback_weight(test.file, coefficient) }
      end
    end

    def load_raw
      @load_raw ||= samples_by_test.transform_values(&:last)
    end

    # Predicted weight per file: the median of each test's recent
    # samples, summed per file. The append-only history must NOT be
    # summed wholesale — a file present in N historical runs would
    # weigh ~N times its true cost, so long-lived files dominate and
    # newly added ones are starved, skewing the partition.
    def load_per_file
      samples_by_test.each_with_object({}) do |((file, _name), times), per_file|
        weight = median(times.last(MAX_SAMPLES_PER_TEST))
        per_file[file] = per_file.fetch(file, 0.0) + weight
      end
    end

    # Rewrites the timing file keeping only the most recent
    # MAX_SAMPLES_PER_TEST samples per test, so the append-only
    # history (and any CI cache built from it) stays bounded instead
    # of growing by one run per invocation.
    def compact!
      samples = samples_by_test
      return if samples.empty?

      tmp = Pathname("#{@path}.tmp")
      tmp.open('w', encoding: 'UTF-8') do |io|
        samples.each do |(file, name), times|
          times.last(MAX_SAMPLES_PER_TEST).each do |time|
            io.puts JSON.generate({ file: file, name: name, time: time })
          end
        end
      end
      File.rename(tmp.to_s, @path.to_s)
      invalidate
    end

    def normalize_path(path)
      Pathname(path).cleanpath.to_s.sub(%r{\A\./}, '')
    end

    # True when a measured Weight already exists for this Test.
    def measured?(file:, name:)
      load_raw.key?([normalize_path(file), name])
    end

    def append(file:, name:, time:)
      @path.dirname.mkpath unless @path.dirname.directory?
      @path.open('a', encoding: 'UTF-8') { |io| io.puts JSON.generate({ file: file, name: name, time: time }) }
      invalidate
    end

    def append_all(entries)
      return if entries.empty?

      @path.dirname.mkpath unless @path.dirname.directory?
      @path.open('a', encoding: 'UTF-8') do |io|
        entries.each { |e| io.puts JSON.generate({ file: e[:file], name: e[:name], time: e[:time] }) }
      end
      invalidate
    end

    private

    # [normalized file, name] => [sample, ...] in append (= run) order.
    def samples_by_test
      @samples_by_test ||= begin
        samples = Hash.new { |h, k| h[k] = [] }
        if @path.exist?
          @path.each_line(encoding: 'UTF-8') do |line|
            entry = parse_line(line)
            samples[[normalize_path(entry.file), entry.name]] << entry.time if entry
          end
        end
        samples.default_proc = nil
        samples
      end
    end

    def invalidate
      @samples_by_test = nil
      @load_raw = nil
    end

    def median(values)
      sorted = values.sort
      mid = sorted.size / 2
      sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
    end

    def filesize_weight(file)
      path = Pathname(file)
      path.exist? ? [path.size / 1024.0, DEFAULT_WEIGHT].max : DEFAULT_WEIGHT
    end

    # Seconds-per-KB coefficient used to scale filesize fallbacks onto
    # the same axis as measured Weights. Measured Weights are seconds;
    # the raw filesize fallback is KB, so mixing them (batch floors,
    # donor selection) compares apples to oranges — 30s of predicted
    # work reads as "30 KB of files". We estimate a conversion from
    # the files we DO have timings for: for each measured file that
    # still exists on disk with size > 0, take measured_seconds /
    # size_kb, and use the median of those ratios (robust to a few
    # outlier files that are unusually fast or slow for their size).
    # nil when nothing can be estimated (no measurements, or none of
    # the measured files exist on disk) — callers then keep raw KB.
    def seconds_per_kb(per_file)
      ratios = per_file.filter_map do |file, seconds|
        kb = size_kb(file)
        next if kb.nil? || kb <= 0

        seconds / kb
      end
      ratios.empty? ? nil : median(ratios)
    end

    # Predicted Weight for an unmeasured Test. Without a coefficient we
    # keep the legacy raw-KB behavior (floored at 1.0). With one we
    # scale filesize into seconds: an existing file becomes
    # size_kb * coefficient (floored at 0.01 to avoid degenerate zero
    # weights, but NOT at 1.0 — sub-second predictions are meaningful
    # now that the unit is seconds); a missing/unreadable file falls
    # back to DEFAULT_WEIGHT as a plausible seconds-scale default.
    def fallback_weight(file, coefficient)
      return filesize_weight(file) if coefficient.nil?

      kb = size_kb(file)
      return DEFAULT_WEIGHT if kb.nil?

      [kb * coefficient, 0.01].max
    end

    # File size in KB, or nil when the file does not exist / is unreadable.
    def size_kb(file)
      path = Pathname(file)
      path.exist? ? path.size / 1024.0 : nil
    rescue SystemCallError
      nil
    end

    def parse_line(line)
      data = JSON.parse(line.strip)
      Entry.new(file: data['file'], name: data['name'], time: data['time'])
    rescue JSON::ParserError
      nil
    end
  end
end
