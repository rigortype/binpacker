# frozen_string_literal: true

module Binpacker
  # Coordinates the full test run: discover → schedule → spawn workers → collect.
  class Orchestrator
    def initialize(config)
      @config = config
    end

    def run
      # 1. Discover tests
      tests = discover

      # 2. Load timing data
      timing = Timing.new(@config.timing_file)
      timings = timing.load

      # 3. Schedule
      scheduler = Scheduler.for(@config.scheduler["algorithm"])
      queues = scheduler.partition(
        tests: tests,
        worker_count: @config.worker_count,
        timings: timings
      )

      # 4. Spawn workers and distribute
      runner_class = TestRunner.for(@config.test_runner)
      workers = queues.map.with_index do |queue, idx|
        Worker.new(idx, runner_class).tap(&:start)
      end

      # 5. Feed tests to workers
      workers.zip(queues).each do |worker, queue|
        worker.send_tests(queue.remaining)
      end

      # 6. Wait for all workers to finish and collect results
      all_timings = []
      all_passed = true

      workers.each do |worker|
        worker.finish
        all_timings.concat(worker.timings)
        all_passed &&= worker.success?
      rescue WorkerError => e
        $stderr.puts "worker #{worker.id} error: #{e.message}"
        all_passed = false
      ensure
        worker.cleanup
      end

      # 7. Append new timing data
      timing.append_all(all_timings) unless all_timings.empty?

      { passed: all_passed, timings: all_timings }
    end

    private

    def discover
      case @config.test_runner
      when "rspec"
        RSpecDiscovery.new(@config).enumerate
      when "minitest"
        MinitestDiscovery.new(@config).enumerate
      else
        raise ConfigError, "unsupported runner: #{@config.test_runner}"
      end
    end
  end
end
