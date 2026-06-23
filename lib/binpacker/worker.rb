# frozen_string_literal: true

require "json"

module Binpacker
  class Worker
    attr_reader :id, :status, :example_count, :passed_count

    def initialize(id, runner_class, passthrough: [])
      @id = id
      @runner_class = runner_class
      @passthrough = passthrough
      @status = :created
      @timings = []
      @exit_code = 0
      @example_count = 0
      @passed_count = 0
    end

    def start
      worker_script = File.expand_path("../../exe/binpacker-worker", __dir__)

      @stdin_r, @stdin_w = IO.pipe(encoding: "UTF-8")
      @stdout_r, @stdout_w = IO.pipe(encoding: "UTF-8")
      @stderr_r, @stderr_w = IO.pipe(encoding: "UTF-8")

      @pid = Process.spawn(
        RbConfig.ruby, worker_script,
        "--runner", @runner_class.runner_name,
        "--id", @id.to_s,
        *passthrough_args,
        in: @stdin_r, out: @stdout_w, err: @stderr_w,
        close_others: true
      )

      @stdin_r.close; @stdout_w.close; @stderr_w.close

      @stderr_thread = Thread.new do
        @stderr_r.each_line { |line| $stderr.write line }
      end

      ready_line = read_line(timeout: 30)
      if ready_line
        data = JSON.parse(ready_line.strip)
        @status = :ready if data["type"] == "ready"
      end

      raise WorkerError, "worker #{@id} failed to start" unless @status == :ready
      self
    rescue JSON::ParserError
      @status = :error
      raise WorkerError, "worker #{@id} sent invalid ready signal"
    end

    def send_tests(tests)
      tests.each { |t| @stdin_w.puts JSON.generate({ file: t.file, name: t.name }) }
    end

    def send_test(test)
      @stdin_w.puts JSON.generate({ file: test.file, name: test.name })
    end

    def batch_done
      @stdin_w.puts JSON.generate({ type: "done" })
    end

    def signal_done
      @stdin_w.puts JSON.generate({ type: "done" })
      @stdin_w.close
    end

    def wait_ready
      deadline = Time.now + 300
      while Time.now < deadline
        begin
          line = read_line(timeout: 1)
          return false unless line

          next unless line.strip.start_with?("{")

          data = JSON.parse(line.strip)
          if data["type"] == "ready"
            return true
          elsif data["type"] == "timing"
            @timings << { file: data["file"], name: data["name"], time: data["time"] }
          elsif data["type"] == "batch_result"
            @batch_buffer = data
            return true
          end
        rescue JSON::ParserError
        end
      end
      false
    end

    def collect_batch
      buffered = @batch_buffer
      @batch_buffer = nil
      batch_timings = []
      batch_examples = 0
      batch_passed = 0
      exit_ok = true

      if buffered
        exit_ok = buffered["passed"]
        batch_examples = buffered["total"] || 0
        batch_passed = buffered["passed_count"] || 0
      else
        @stdout_r.each_line do |line|
          data = JSON.parse(line.strip)
          case data["type"]
          when "timing"
            batch_timings << { file: data["file"], name: data["name"], time: data["time"] }
          when "batch_result"
            exit_ok = data["passed"]
            batch_examples = data["total"] || 0
            batch_passed = data["passed_count"] || 0
            break
          when "result"
            @exit_code = data["exit_code"]
            @passed = data["passed"]
            @example_count = data["total"] || 0
            @passed_count = data["passed_count"] || 0
            break
          end
        rescue JSON::ParserError
        end
      end

      @timings.concat(batch_timings)
      @example_count += batch_examples
      @passed_count += batch_passed
      @exit_code = exit_ok ? 0 : 1 unless exit_ok

      { timings: batch_timings, exit_code: @exit_code, examples: batch_examples, passed: batch_passed }
    end

    def collect_results
      @status = :running

      @stdout_r.each_line do |line|
        data = JSON.parse(line.strip)
        case data["type"]
        when "timing"
          @timings << { file: data["file"], name: data["name"], time: data["time"] }
        when "result"
          @exit_code = data["exit_code"]
          @passed = data["passed"]
          @example_count = data["total"] || 0
          @passed_count = data["passed_count"] || 0
          break
        when "batch_result"
          @exit_code = data["passed"] ? 0 : 1
          @passed = data["passed"]
          @example_count = data["total"] || 0
          @passed_count = data["passed_count"] || 0
          break
        when "output"
          $stdout.write data["text"] if data["text"]
        end
      rescue JSON::ParserError
        $stdout.write line
      end

      Process.wait(@pid)
      @status = :finished
    rescue Errno::ECHILD
      @status = :crashed
      @passed = false
    end

    def timings
      @timings
    end

    def success?
      @exit_code == 0
    end

    def cleanup
      kill! if @status == :running || @status == :ready
      [@stdin_w, @stdout_r, @stderr_r].each { |io| io&.close unless io&.closed? }
      @stderr_thread&.kill
    rescue IOError
    end

    private

    def passthrough_args
      return [] if @passthrough.empty?
      @passthrough.flat_map { |arg| ["--rspec-arg", arg] }
    end

    def kill!
      Process.kill("TERM", @pid)
      Process.wait(@pid)
    rescue Errno::ESRCH, Errno::ECHILD
    end

    def read_line(timeout: 1)
      io = [@stdout_r]
      readable = IO.select(io, nil, nil, timeout)
      return nil unless readable
      readable.first.first.gets
    rescue IOError, Errno::EPIPE
      nil
    end
  end
end
