# frozen_string_literal: true

require 'json'

module Binpacker
  # Fan-in audit for a sharded matrix: did the shards, between them, actually run the whole suite?
  #
  # Shards never coordinate. Each cuts the same N-way partition from the timing data it loaded and takes
  # its own bin, which is correct exactly as long as they all loaded the SAME data. In CI that means every
  # shard job restoring the same timing cache — and the failure mode when one does not is the bad one:
  # it partitions differently, some tests land in no shard, and every job still reports success. Nothing
  # inside a single shard can notice, because a shard cannot tell "not mine" from "does not exist".
  #
  # So the check belongs after the matrix, over the run reports it produced. Point it at every shard's
  # report and it fails unless the reports describe one coherent split of one suite.
  class ShardCheck
    Result = Struct.new(:ok, :problems, :summary, keyword_init: true) do
      def ok? = ok
    end

    def self.call(paths) = new(paths).call

    def initialize(paths)
      @paths = Array(paths)
    end

    def call
      return failure(['no run reports given']) if @paths.empty?

      reports, unreadable = load_reports
      return failure(unreadable) unless unreadable.empty?

      shards = reports.filter_map { |path, data| shard_of(path, data) }
      missing = reports.map(&:first) - shards.map { |s| s[:path] }
      return failure(missing.map { |p| "#{p}: no `shard` section — was it run with --shard?" }) unless missing.empty?

      problems = check(shards)
      problems.empty? ? success(shards) : failure(problems)
    end

    private

    def load_reports
      reports = []
      unreadable = []
      @paths.each do |path|
        reports << [path, JSON.parse(File.read(path))]
      rescue Errno::ENOENT
        unreadable << "#{path}: no such file"
      rescue JSON::ParserError => e
        unreadable << "#{path}: not valid JSON (#{e.message})"
      end
      [reports, unreadable]
    end

    def shard_of(path, data)
      section = data['shard']
      return nil unless section.is_a?(Hash)

      {
        path: path,
        index: section['index'],
        total: section['total'],
        discovered: section['discovered_tests'],
        selected: section['selected_tests']
      }
    end

    def check(shards)
      problems = []
      problems.concat(agreement_problems(shards, :total, 'shard count'))
      problems.concat(agreement_problems(shards, :discovered, 'discovered test count'))
      problems.concat(completeness_problems(shards))
      problems.concat(coverage_problems(shards))
      problems
    end

    # Every report must describe the same matrix. Disagreement here means the reports were not produced by
    # one run, and no coverage conclusion drawn from them would mean anything.
    def agreement_problems(shards, field, label)
      values = shards.map { |s| s[field] }.uniq
      return [] if values.size <= 1

      ["shards disagree on #{label}: #{values.sort_by(&:to_s).inspect}"]
    end

    # A matrix that lost a job silently drops that job's slice, which looks exactly like a smaller suite.
    def completeness_problems(shards)
      total = shards.first[:total]
      return [] if total.nil?

      seen = shards.map { |s| s[:index] }
      duplicates = seen.tally.select { |_, n| n > 1 }.keys.sort
      problems = []
      problems << "shard #{duplicates.join(', ')} reported more than once" unless duplicates.empty?

      absent = (1..total).to_a - seen
      problems << "no report for shard #{absent.join(', ')} of #{total}" unless absent.empty?
      problems
    end

    # The check this class exists for: the slices must add up to the suite.
    def coverage_problems(shards)
      discovered = shards.first[:discovered]
      return [] if discovered.nil?

      selected = shards.sum { |s| s[:selected].to_i }
      return [] if selected == discovered

      verb = selected < discovered ? 'ran no shard' : 'ran in more than one shard'
      ["shards cover #{selected} of #{discovered} tests — #{(discovered - selected).abs} #{verb}. " \
       'The shards partitioned different timing data; make every shard load the same timing file.']
    end

    def success(shards)
      Result.new(
        ok: true,
        problems: [],
        summary: "#{shards.size} shards cover all #{shards.first[:discovered]} tests"
      )
    end

    def failure(problems)
      Result.new(ok: false, problems: problems, summary: 'shard coverage check failed')
    end
  end
end
