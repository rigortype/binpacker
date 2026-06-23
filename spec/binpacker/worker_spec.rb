# frozen_string_literal: true

require "spec_helper"

RSpec.describe Binpacker::Worker do
  describe "#collect_batch" do
    it "returns timing records read while waiting for a batch result" do
      worker = described_class.new(0, Binpacker::RSpecRunner)
      stdout_r, stdout_w = IO.pipe(encoding: "UTF-8")
      timing = { "type" => "timing", "file" => "spec/a_spec.rb", "name" => "spec/a_spec.rb", "time" => 0.12 }

      worker.instance_variable_set(:@stdout_r, stdout_r)
      stdout_w.puts JSON.generate(timing)
      stdout_w.puts JSON.generate({ type: "batch_result", passed: true, total: 1, passed_count: 1 })

      expect(worker.wait_ready).to be true

      batch = worker.collect_batch
      expect(batch[:timings]).to eq([{ file: "spec/a_spec.rb", name: "spec/a_spec.rb", time: 0.12 }])
    ensure
      stdout_w&.close unless stdout_w&.closed?
      stdout_r&.close unless stdout_r&.closed?
    end
  end
end
