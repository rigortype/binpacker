# frozen_string_literal: true

module Binpacker
  class Orchestrator
    def initialize(config, passthrough: [])
      @config = config
      @passthrough = passthrough
    end

    def run
      tests = discover

      timing = Timing.new(@config.timing_file)
      timings = timing.load_with_fallback(tests)

      scheduler = Scheduler.for(@config.scheduler["algorithm"])
      queues = scheduler.partition(
        tests: tests,
        worker_count: @config.worker_count,
        timings: timings
      )

      runner_class = TestRunner.for(@config.test_runner)
      workers = queues.map.with_index do |queue, idx|
        Worker.new(idx, runner_class, passthrough: @passthrough).tap(&:start)
      end

      workers.zip(queues).each do |worker, queue|
        worker.send_tests(queue.remaining)
      end

      all_timings = []
      all_passed = true
      total_examples = 0
      passed_examples = 0

      workers.each(&:signal_done)

      workers.each do |worker|
        worker.collect_results
        all_timings.concat(worker.timings)
        all_passed &&= worker.success?
        total_examples += worker.example_count
        passed_examples += worker.passed_count
      rescue WorkerError => e
        $stderr.puts "worker #{worker.id} error: #{e.message}"
        all_passed = false
      ensure
        worker.cleanup
      end

      timing.append_all(all_timings) unless all_timings.empty?

      {
        passed: all_passed,
        total: total_examples,
        passed_count: passed_examples,
        timings: all_timings
      }
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
