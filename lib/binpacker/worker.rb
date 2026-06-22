# frozen_string_literal: true

require "json"

module Binpacker
  # Manages a single worker subprocess that executes tests.
  #
  # Communication protocol:
  #   Parent → Worker (stdin):  {"file":"...","name":"..."} per test, {"type":"done"} to end.
  #   Worker → Parent (stdout): {"type":"timing","file":"...","name":"...","time":0.123}
  #                              {"type":"result","exit_code":0,"passed":true}
  #                              {"type":"ready"} — worker started
  class Worker
    attr_reader :id, :status

    def initialize(id, runner_class)
      @id = id
      @runner_class = runner_class
      @status = :created
      @timings = []
      @exit_code = nil
    end

    def start
      worker_script = File.expand_path("../../exe/binpacker-worker", __dir__)

      @stdin_r, @stdin_w = IO.pipe
      @stdout_r, @stdout_w = IO.pipe
      @stderr_r, @stderr_w = IO.pipe

      @pid = Process.spawn(
        RbConfig.ruby, worker_script,
        "--runner", @runner_class.runner_name,
        in: @stdin_r, out: @stdout_w, err: @stderr_w,
        close_others: true
      )

      @stdin_r.close; @stdout_w.close; @stderr_w.close

      @stderr_thread = Thread.new do
        @stderr_r.each_line { |line| $stderr.puts "[worker-#{@id}] #{line}" }
      end

      ready_line = read_line(timeout: 10)
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

    def finish
      @stdin_w.puts JSON.generate({ type: "done" })
      @stdin_w.close

      @status = :running
      @stdout_r.each_line do |line|
        data = JSON.parse(line.strip)
        case data["type"]
        when "timing"
          @timings << { file: data["file"], name: data["name"], time: data["time"] }
        when "result"
          @exit_code = data["exit_code"]
          @passed = data["passed"]
        end
      rescue JSON::ParserError
        # skip unparseable lines
      end

      Process.wait(@pid)
      @status = :finished
    end

    def timings
      @timings
    end

    def success?
      @exit_code == 0
    end

    def cleanup
      [@stdin_w, @stdout_r, @stderr_r].each { |io| io&.close unless io&.closed? }
      @stderr_thread&.kill
    rescue IOError
    end

    private

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
