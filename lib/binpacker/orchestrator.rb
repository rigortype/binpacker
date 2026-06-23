# frozen_string_literal: true

module Binpacker
  class Orchestrator
    BATCH_SIZE = 10

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

      if @config.scheduler["steal_enabled"]
        run_dynamic(workers, queues, timing)
      else
        run_static(workers, queues, timing)
      end
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

    def run_static(workers, queues, timing)
      workers.zip(queues).each do |worker, queue|
        worker.send_tests(queue.remaining)
      end

      workers.each(&:signal_done)

      all_timings = []
      all_passed = true
      total_examples = 0
      passed_examples = 0

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

      finalize(timing, all_timings, all_passed, total_examples, passed_examples)
    end

    def run_dynamic(workers, queues, timing)
      all_timings = []
      all_passed = true
      total_examples = 0
      passed_examples = 0
      active = []

      workers.zip(queues).each do |worker, queue|
        batch = drain_batch(queue)
        if batch.empty?
          worker.signal_done
          worker.collect_results
          all_timings.concat(worker.timings)
          all_passed &&= worker.success?
          total_examples += worker.example_count
          passed_examples += worker.passed_count
          worker.cleanup
        else
          worker.send_tests(batch)
          worker.batch_done
          active << worker
        end
      end

      until active.empty?
        ready = active.find { |w| w.wait_ready }
        unless ready
          active.reject! { |w| w.status == :crashed || w.status == :error }
          sleep 0.1
          next
        end

        begin
          batch = ready.collect_batch
          all_timings.concat(batch[:timings])
          all_passed &&= batch[:exit_code] == 0
          total_examples += batch[:examples]
          passed_examples += batch[:passed]

          own_queue = queues[ready.id]
          next_batch = drain_batch(own_queue)

          if next_batch.empty?
            donor = queues.reject(&:empty?).max_by(&:size)
            next_batch = drain_batch(donor) if donor
          end

          if next_batch.any?
            ready.send_tests(next_batch)
            ready.batch_done
          else
            ready.signal_done
            active.delete(ready)
          end
        rescue WorkerError => e
          $stderr.puts "worker #{ready.id} error: #{e.message}"
          all_passed = false
          active.delete(ready)
        end
      end

      workers.each(&:cleanup)
      finalize(timing, all_timings, all_passed, total_examples, passed_examples)
    end

    def drain_batch(queue)
      return [] if queue.nil? || queue.empty?
      batch = []
      BATCH_SIZE.times do
        test = queue.pop
        break unless test
        batch << test
      end
      batch
    end

    def finalize(timing, all_timings, all_passed, total_examples, passed_examples)
      timing.append_all(all_timings) unless all_timings.empty?
      {
        passed: all_passed,
        total: total_examples,
        passed_count: passed_examples,
        timings: all_timings
      }
    end
  end
end
