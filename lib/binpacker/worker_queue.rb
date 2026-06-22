# frozen_string_literal: true

module Binpacker
  class WorkerQueue
    include Enumerable

    attr_reader :worker_id

    def initialize(worker_id, tests = [])
      @worker_id = worker_id
      @tests = tests.dup
      @index = 0
    end

    def pop
      return nil if empty?
      test = @tests[@index]
      @index += 1
      test
    end

    def peek
      return nil if empty?
      @tests[@index]
    end

    def empty?
      @index >= @tests.size
    end

    def size
      @tests.size - @index
    end

    def remaining
      @tests[@index..] || []
    end

    def total_weight(timings)
      remaining.sum { |t| timings.fetch(t.key, Timing::DEFAULT_WEIGHT) }
    end

    def push(test)
      @tests << test
    end

    def each(&block)
      @tests[@index..].each(&block)
    end
  end
end
