# frozen_string_literal: true

require "json"

module Binpacker
  class Timing
    Entry = Struct.new(:file, :name, :time, keyword_init: true)

    DEFAULT_WEIGHT = 1.0

    def initialize(path)
      @path = Pathname(path)
    end

    # Returns a Hash of (String(file), String(name)) -> Float(time).
    # Last entry per (file, name) wins.
    def load
      return {} unless @path.exist?

      @path.each_line
        .map { |line| parse_line(line) }
        .compact
        .group_by { |e| [e.file, e.name] }
        .transform_values { |entries| entries.last.time }
    end

    # Returns the weight for a given test, or DEFAULT_WEIGHT if unknown.
    def weight_for(file:, name:)
      entries = load
      entries.fetch([file, name], DEFAULT_WEIGHT)
    end

    # Append a single timing entry.
    def append(file:, name:, time:)
      @path.dirname.mkpath unless @path.dirname.directory?
      @path.open("a") do |io|
        io.puts JSON.generate({ file: file, name: name, time: time })
      end
    end

    # Append multiple entries at once.
    def append_all(entries)
      return if entries.empty?
      @path.dirname.mkpath unless @path.dirname.directory?
      @path.open("a") do |io|
        entries.each do |e|
          io.puts JSON.generate({ file: e[:file], name: e[:name], time: e[:time] })
        end
      end
    end

    private

    def parse_line(line)
      data = JSON.parse(line.strip)
      Entry.new(file: data["file"], name: data["name"], time: data["time"])
    rescue JSON::ParserError
      nil
    end
  end
end
