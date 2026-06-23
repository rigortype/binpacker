# frozen_string_literal: true

module Binpacker
  class ProgressDisplay
    CI_INTERVAL = 15 # seconds between CI output lines

    def initialize(worker_count, tty: $stdout.tty?)
      @worker_count = worker_count
      @tty = tty
      @workers = Array.new(worker_count) { { done: 0, total: 0, file: "", elapsed: 0.0 } }
      @start = Time.now
      @last_ci_output = Time.at(Time.now.to_f - CI_INTERVAL)
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

    def finish(worker_stats = [])
      return unless @tty
      redraw
      $stdout.puts
    end

    def summary(worker_stats)
      return if worker_stats.empty?

      total_time = worker_stats.sum { |s| s[:total_time] }
      times = worker_stats.map { |s| s[:total_time] }
      mean = total_time / worker_stats.size
      max_dev = times.map { |t| (t - mean).abs }.max
      dev_pct = mean > 0 ? (max_dev / mean * 100).round(1) : 0

      $stdout.puts
      worker_stats.each_with_index do |s, i|
        t = format_time(s[:total_time])
        $stdout.puts "  Worker #{i}: #{s[:files]} files, #{t} | #{s[:examples]} examples, #{s[:passed]} passed"
      end
      $stdout.puts "  ──"
      $stdout.puts "  Total: #{worker_stats.sum { |s| s[:files] }} files, #{format_time(total_time)} | #{worker_stats.sum { |s| s[:examples] }} examples"
      $stdout.puts "  Balance: max deviation #{format_time(max_dev)} (#{dev_pct}%)"
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
      return "  0.0s" if seconds < 0.001
      m = (seconds / 60).floor
      s = (seconds % 60).round(1)
      m > 0 ? "#{m}m#{s.to_s.rjust(4, '0')}s" : "#{s.to_s.rjust(5)}s"
    end
  end
end
