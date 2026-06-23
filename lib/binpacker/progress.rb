# frozen_string_literal: true

module Binpacker
  class ProgressDisplay
    CI_INTERVAL = 15 # seconds between CI output lines

    def initialize(worker_count, tty: $stdout.tty?)
      @worker_count = worker_count
      @tty = tty
      @workers = Array.new(worker_count) { { done: 0, total: 0, file: "", elapsed: 0.0 } }
      @start = Time.now
      @last_ci_output = Time.now - CI_INTERVAL
      @lines_written = 0
      @mutex = Mutex.new
    end

    def update(worker_id, done:, total:, file:, elapsed: 0.0)
      @mutex.synchronize do
        w = @workers[worker_id]
        w[:done] = done
        w[:total] = total
        w[:file] = file
        w[:elapsed] = elapsed
      end

      if @tty
        redraw
      else
        periodic_output
      end
    end

    def finish
      return unless @tty
      redraw
      $stdout.puts
    end

    private

    def redraw
      @mutex.synchronize do
        clear_lines
        @workers.each_with_index do |w, i|
          bar = build_bar(w[:done], w[:total])
          status = w[:total] > 0 && w[:done] >= w[:total] ? "done" : w[:file][-50..] || ""
          $stdout.puts format_line(i, bar, w[:done], w[:total], status, w[:elapsed])
        end
        @lines_written = @worker_count
      end
    end

    def clear_lines
      return if @lines_written == 0
      @lines_written.times do
        $stdout.print "\033[A\033[K"
      end
    end

    def build_bar(done, total)
      return "[----------]" if total == 0
      width = 10
      filled = (done.to_f / total * width).round
      "[#{'█' * filled}#{'░' * (width - filled)}]"
    end

    def format_line(idx, bar, done, total, file, elapsed)
      ts = format_time(elapsed)
      "W#{idx} #{bar} #{done.to_s.rjust(3)}/#{total.to_s.ljust(3)} #{file.ljust(50)} #{ts}"
    end

    def periodic_output
      now = Time.now
      return if now - @last_ci_output < CI_INTERVAL
      @last_ci_output = now

      parts = @workers.map.with_index do |w, i|
        if w[:total] > 0 && w[:done] >= w[:total]
          "W#{i}: done"
        else
          "W#{i}: #{w[:done]}/#{w[:total]}"
        end
      end
      elapsed = (now - @start).round(1)
      $stdout.puts "[binpacker #{elapsed}s] #{parts.join(' | ')}"
    end

    def format_time(seconds)
      return "      " if seconds < 0.001
      m = (seconds / 60).floor
      s = (seconds % 60).round(1)
      m > 0 ? "#{m}m#{s.to_s.rjust(4, '0')}s" : "#{s.to_s.rjust(5)}s"
    end
  end
end
