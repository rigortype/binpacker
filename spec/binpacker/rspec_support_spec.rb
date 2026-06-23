# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "RSpec support" do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      Dir.chdir(dir) { example.run }
    end
  end

  it "runs specs without using /dev/stderr as a formatter output path" do
    FileUtils.mkdir_p("spec")
    File.write("spec/math_spec.rb", <<~RUBY)
      RSpec.describe "math" do
        it "adds" do
          expect(1 + 2).to eq(3)
        end
      end
    RUBY

    result = Binpacker::Orchestrator.new(config).run

    expect(result[:passed]).to be true
    expect(result[:total]).to eq(1)
    expect(result[:passed_count]).to eq(1)
  end

  def config
    double("config").tap do |config|
      allow(config).to receive(:test_runner).and_return("rspec")
      allow(config).to receive(:test_pattern).and_return("spec/**/*_spec.rb")
      allow(config).to receive(:test_exclude).and_return([])
      allow(config).to receive(:timing_file).and_return("binpacker.timings")
      allow(config).to receive(:worker_count).and_return(1)
      allow(config).to receive(:scheduler).and_return({ "algorithm" => "lpt", "steal_enabled" => true })
    end
  end
end
