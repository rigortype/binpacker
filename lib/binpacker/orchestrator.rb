# frozen_string_literal: true

module Binpacker
  class Orchestrator
    # Dynamic batches halve the queue's remaining predicted weight,
    # floored at a per-run minimum: early batches are large to amortize
    # the per-batch test-runner boot (each batch is a fresh rspec
    # process), tail batches stay small so workers finish together.
    #
    # The floor comes in two regimes (@min_batch_weight, set in #run):
    #   - Calibrated: weights are measured seconds, so the floor is a
    #     fixed MIN_BATCH_WEIGHT (~30s), an order of magnitude above the
    #     ~3s runner boot — boot overhead stays in the noise.
    #   - Cold start: weights are filesize KB, not seconds, so a fixed
    #     30 is meaningless. We instead derive a floor that targets
    #     ~COLD_START_BATCHES_PER_WORKER batches per worker (below).
    MIN_BATCH_WEIGHT = 30.0

    # On a pure cold start predicted weights are filesize KB, not
    # seconds, so the 30s MIN_BATCH_WEIGHT floor has no meaning. Instead
    # we size the floor so the total predicted weight divides into about
    # this many batches per worker — matching the ~5 runner boots per
    # worker that gave the best makespan in the PR #12 simulation.
    COLD_START_BATCHES_PER_WORKER = 5

    def initialize(config, passthrough: [], quiet: false, report_path: nil)
      @config = config
      @passthrough = passthrough
      @quiet = quiet
      @report_path = report_path
    end

    def run
      tests = discover
      timing = Timing.new(@config.timing_file)
      timings = timing.load_with_fallback(tests)
      @timings = timings
      @min_batch_weight = min_batch_weight(timing, timings)

      scheduler = Scheduler.for(@config.scheduler['algorithm'])
      queues = scheduler.partition(
        tests: tests,
        worker_count: @config.worker_count,
        timings: timings
      )

      # Capture predicted per-Worker loads before execution drains the queues.
      @predicted_loads = queues.map { |q| q.total_weight(timings) }

      runner_class = TestRunner.for(@config.test_runner)
      workers = queues.map.with_index do |_queue, idx|
        Worker.new(idx, runner_class, passthrough: @passthrough, quiet: @quiet).tap(&:start)
      end

      if @config.scheduler['steal_enabled']
        run_dynamic(workers, queues, timing, tests)
      else
        run_static(workers, queues, timing, tests)
      end
    end

    private

    def discover
      case @config.test_runner
      when 'rspec'
        RSpecDiscovery.new(@config).enumerate
      when 'minitest'
        MinitestDiscovery.new(@config).enumerate
      else
        raise ConfigError, "unsupported runner: #{@config.test_runner}"
      end
    end

    def run_static(workers, queues, timing, tests)
      queue_totals = queues.map(&:size)
      progress = ProgressDisplay.new(workers.size)

      workers.zip(queues).each do |worker, queue|
        worker.send_tests(queue.remaining)
        progress.update(worker.id, done: 0, total: queue_totals[worker.id], file: queue.remaining.first&.file || '')
      end
      progress.refresh

      workers.each(&:signal_done)

      all_timings = []
      all_passed = true
      total_examples = 0
      passed_examples = 0
      worker_time = Array.new(workers.size, 0.0)
      worker_examples = Array.new(workers.size, 0)
      worker_passed = Array.new(workers.size, 0)

      workers.each do |worker|
        worker.collect_results
        all_timings.concat(worker.timings)
        all_passed &&= worker.success?
        total_examples += worker.example_count
        passed_examples += worker.passed_count
        worker_examples[worker.id] = worker.example_count
        worker_passed[worker.id] = worker.passed_count
        worker_time[worker.id] = worker.timings.sum { |t| t[:time] }
        progress.update(worker.id, done: queue_totals[worker.id], total: queue_totals[worker.id], file: 'done')
        progress.refresh
      rescue WorkerError => e
        warn "worker #{worker.id} error: #{e.message}"
        all_passed = false
      ensure
        worker.cleanup
      end

      progress.finish

      worker_stats = workers.map.with_index do |_w, i|
        {
          files: queue_totals[i],
          total_time: worker_time[i],
          examples: worker_examples[i],
          passed: worker_passed[i]
        }
      end
      progress.summary(worker_stats)
      write_report(worker_stats, all_timings)

      finalize(timing, all_timings, all_passed, total_examples, passed_examples, tests)
    end

    def run_dynamic(workers, queues, timing, tests)
      all_timings = []
      all_passed = true
      total_examples = 0
      passed_examples = 0
      active = []

      queue_totals = queues.map(&:size)
      worker_done = Array.new(workers.size, 0)
      batch_sizes = Array.new(workers.size, 0)
      worker_time = Array.new(workers.size, 0.0)
      worker_examples = Array.new(workers.size, 0)
      worker_passed = Array.new(workers.size, 0)

      progress = ProgressDisplay.new(workers.size)

      workers.zip(queues).each do |worker, queue|
        batch = drain_batch(queue)
        if batch.empty?
          worker.signal_done
          worker.collect_results
          all_timings.concat(worker.timings)
          all_passed &&= worker.success?
          total_examples += worker.example_count
          passed_examples += worker.passed_count
          worker_examples[worker.id] = worker.example_count
          worker_passed[worker.id] = worker.passed_count
          worker.cleanup
          worker_done[worker.id] = queue_totals[worker.id]
          progress.update(worker.id, done: worker_done[worker.id], total: queue_totals[worker.id], file: 'done')
        else
          worker.send_tests(batch)
          worker.batch_done
          active << worker
          batch_sizes[worker.id] = batch.size
          current_file = batch.first&.file || ''
          progress.update(worker.id, done: 0, total: queue_totals[worker.id], file: current_file)
        end
      end

      until active.empty?
        ready = active.find { |w| w.wait_for_batch }
        unless ready
          active.reject! { |w| %i[crashed error].include?(w.status) }
          sleep 0.1
          next
        end

        begin
          all_passed &&= ready.success?
          total_examples += ready.example_count
          passed_examples += ready.passed_count

          worker_done[ready.id] += batch_sizes[ready.id]
          worker_examples[ready.id] = ready.example_count
          worker_passed[ready.id] = ready.passed_count

          own_queue = queues[ready.id]
          next_batch = drain_batch(own_queue)

          if next_batch.empty?
            donor = queues.reject(&:empty?).max_by { |q| q.total_weight(@timings) }
            if donor
              next_batch = drain_batch(donor)
              queue_totals[ready.id] += next_batch.size
              queue_totals[donor.worker_id] -= next_batch.size
            end
          end

          if next_batch.any?
            ready.send_tests(next_batch)
            ready.batch_done
            batch_sizes[ready.id] = next_batch.size
            current_file = next_batch.first&.file || ''
            progress.update(ready.id, done: worker_done[ready.id], total: queue_totals[ready.id], file: current_file)
            progress.refresh
          else
            ready.signal_done
            all_timings.concat(ready.timings)
            active.delete(ready)
            worker_done[ready.id] = queue_totals[ready.id]
            progress.update(ready.id, done: queue_totals[ready.id], total: queue_totals[ready.id], file: 'done')
            progress.refresh
          end
        rescue WorkerError => e
          warn "worker #{ready.id} error: #{e.message}"
          all_passed = false
          active.delete(ready)
        end
      end

      progress.finish

      worker_stats = workers.map.with_index do |w, i|
        tw = w.timings.sum { |t| t[:time] }
        {
          files: queue_totals[i],
          total_time: tw > 0 ? tw : worker_time[i],
          examples: worker_examples[i],
          passed: worker_passed[i]
        }
      end
      progress.summary(worker_stats)
      write_report(worker_stats, all_timings)

      workers.each(&:cleanup)
      finalize(timing, all_timings, all_passed, total_examples, passed_examples, tests)
    end

    def write_report(worker_stats, all_timings)
      return unless @report_path

      Report.new(
        profile: @config.profile,
        algorithm: @config.scheduler['algorithm'],
        predicted_loads: @predicted_loads,
        worker_stats: worker_stats,
        all_timings: all_timings,
        timings: @timings
      ).write(@report_path)
    end

    # Per-run batch-weight floor. Calibrated runs use the fixed
    # seconds-scale MIN_BATCH_WEIGHT. On a cold start weights are KB, so
    # that floor is meaningless; derive one that splits the total
    # predicted weight into ~COLD_START_BATCHES_PER_WORKER batches per
    # worker, falling back to MIN_BATCH_WEIGHT when there is nothing to
    # divide (zero total weight or zero workers).
    def min_batch_weight(timing, timings)
      return MIN_BATCH_WEIGHT if timing.calibrated?

      total = timings.values.sum
      workers = @config.worker_count
      return MIN_BATCH_WEIGHT if total.zero? || workers.zero?

      total / (workers * COLD_START_BATCHES_PER_WORKER)
    end

    def drain_batch(queue)
      return [] if queue.nil? || queue.empty?

      target = [queue.total_weight(@timings) / 2.0, @min_batch_weight].max
      batch = []
      weight = 0.0
      while (batch.empty? || weight < target) && (test = queue.pop)
        batch << test
        weight += @timings.fetch(test.key, Timing::DEFAULT_WEIGHT)
      end
      batch
    end

    def finalize(timing, all_timings, all_passed, total_examples, passed_examples, tests)
      unless all_timings.empty?
        timing.append_all(all_timings)
        timing.compact!
      end
      empty_filter = minitest_empty_filter?(tests, total_examples)
      all_passed = false if empty_filter

      {
        passed: all_passed,
        total: total_examples,
        passed_count: passed_examples,
        timings: all_timings,
        empty_filter: empty_filter
      }
    end

    def minitest_empty_filter?(tests, total_examples)
      return false unless @config.test_runner == 'minitest'
      return false unless tests.any?
      return false unless total_examples.zero?

      minitest_include_filter?
    end

    def minitest_include_filter?
      @passthrough.any? do |arg|
        %w[--name --include -n -i].include?(arg) ||
          arg.start_with?('--name=', '--include=') ||
          (arg.start_with?('-n', '-i') && arg.length > 2)
      end
    end
  end
end
