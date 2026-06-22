# frozen_string_literal: true

module Binpacker
  class Scheduler
    # Returns Array<WorkerQueue> one per worker.
    def partition(tests:, worker_count:, timings:)
      raise NotImplementedError
    end

    def self.for(strategy)
      case strategy.to_s
      when "lpt" then LptScheduler.new
      else
        raise SchedulerError, "unknown scheduling algorithm: #{strategy}"
      end
    end
  end

  class LptScheduler < Scheduler
    # Longest Processing Time first.
    # Sort tests by descending weight, assign each to the least-loaded worker.
    def partition(tests:, worker_count:, timings:)
      queues = Array.new(worker_count) { |i| WorkerQueue.new(i) }
      loads = Array.new(worker_count, 0.0)

      # Sort by weight descending; unknown tests get default weight
      sorted = tests.sort_by { |t|
        -timings.fetch(t.key, Timing::DEFAULT_WEIGHT)
      }

      sorted.each do |test|
        min_idx = loads.each_with_index.min_by { |load, _| load }.last
        queues[min_idx].push(test)
        loads[min_idx] += timings.fetch(test.key, Timing::DEFAULT_WEIGHT)
      end

      queues
    end
  end
end
