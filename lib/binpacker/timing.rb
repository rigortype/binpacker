# frozen_string_literal: true

require "json"

module Binpacker
  class Timing
    Entry = Struct.new(:file, :name, :time, keyword_init: true)

    DEFAULT_WEIGHT = 1.0

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
      return {} unless @path.exist?

      @path.each_line(encoding: "UTF-8")
        .map { |line| parse_line(line) }
        .compact
        .group_by { |e| [normalize_path(e.file), e.name] }
        .transform_values { |entries| entries.last.time }
    end

    def load_per_file
      return {} unless @path.exist?

      @path.each_line(encoding: "UTF-8")
        .map { |line| parse_line(line) }
        .compact
        .group_by { |e| normalize_path(e.file) }
        .transform_values { |entries| entries.sum(&:time) }
    end

    def normalize_path(path)
      Pathname(path).cleanpath.to_s.sub(/\A\.\//, "")
    end

    # True when a measured Weight already exists for this Test.
    def measured?(file:, name:)
      load_raw.key?([normalize_path(file), name])
    end

    def weight_for(file:, name:)
      measured = load_raw
      measured.fetch([file, name]) { filesize_weight(file) }
    end

    def append(file:, name:, time:)
      @path.dirname.mkpath unless @path.dirname.directory?
      @path.open("a", encoding: "UTF-8") { |io| io.puts JSON.generate({ file: file, name: name, time: time }) }
    end

    def append_all(entries)
      return if entries.empty?
      @path.dirname.mkpath unless @path.dirname.directory?
      @path.open("a", encoding: "UTF-8") do |io|
        entries.each { |e| io.puts JSON.generate({ file: e[:file], name: e[:name], time: e[:time] }) }
      end
    end

    private

    def filesize_weight(file)
      path = Pathname(file)
      path.exist? ? [path.size / 1024.0, DEFAULT_WEIGHT].max : DEFAULT_WEIGHT
    end

    def parse_line(line)
      data = JSON.parse(line.strip)
      Entry.new(file: data["file"], name: data["name"], time: data["time"])
    rescue JSON::ParserError
      nil
    end
  end
end
