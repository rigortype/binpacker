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

    def load_with_fallback(tests)
      per_file = load_per_file
      tests.each_with_object({}) do |test, hash|
        key = normalize_path(test.file)
        hash[test.key] = per_file.fetch(key) { filesize_weight(test.file) }
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

    def weight_for(file:, name:)
      load_raw.fetch([normalize_path(file), name]) { filesize_weight(file) }
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

    def parse_line(line)
      data = JSON.parse(line.strip)
      Entry.new(file: data['file'], name: data['name'], time: data['time'])
    rescue JSON::ParserError
      nil
    end
  end
end
