# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "Minitest support" do
  around do |example|
    original_load_path = $LOAD_PATH.dup
    Dir.mktmpdir do |dir|
      @dir = dir
      Dir.chdir(dir) { example.run }
    ensure
      $LOAD_PATH.replace(original_load_path)
      remove_minitest_class(:BinpackerMinitestWorkerTest)
      remove_minitest_class(:BinpackerMinitestFilterTest)
      remove_minitest_class(:BinpackerMinitestAfterRunTest)
      clear_minitest_after_run_hooks
    end
  end

  it "runs only the assigned Minitest methods when one file is split across workers" do
    log_path = File.join(@dir, "runs.log")
    write_minitest_file(
      class_name: "BinpackerMinitestWorkerTest",
      log_path: log_path,
      methods: %w[test_add test_sub]
    )

    result = Binpacker::Orchestrator.new(config(workers: 2)).run

    expect(result[:passed]).to be true
    expect(result[:total]).to eq(2)
    expect(File.readlines(log_path, chomp: true).sort).to eq(%w[test_add test_sub])
  end

  it "forwards passthrough arguments to Minitest" do
    log_path = File.join(@dir, "filtered.log")
    write_minitest_file(
      class_name: "BinpackerMinitestFilterTest",
      log_path: log_path,
      methods: %w[test_add test_sub]
    )

    result = Binpacker::Orchestrator.new(
      config(workers: 1),
      passthrough: ["--name", "/test_add$/"]
    ).run

    expect(result[:passed]).to be true
    expect(result[:total]).to eq(1)
    expect(File.readlines(log_path, chomp: true)).to eq(["test_add"])
  end

  it "fails when a Minitest include filter matches no tests" do
    log_path = File.join(@dir, "empty-filter.log")
    write_minitest_file(
      class_name: "BinpackerMinitestFilterTest",
      log_path: log_path,
      methods: %w[test_add test_sub]
    )

    result = Binpacker::Orchestrator.new(
      config(workers: 2),
      passthrough: ["--name", "/does_not_exist/"]
    ).run

    expect(result[:passed]).to be false
    expect(result[:empty_filter]).to be true
    expect(result[:total]).to eq(0)
    expect(File).not_to exist(log_path)
  end

  it "runs Minitest after_run hooks in workers" do
    marker_path = File.join(@dir, "after-run.log")
    FileUtils.mkdir_p("test/unit")
    File.write("test/unit/after_run_test.rb", <<~RUBY)
      require "minitest/autorun"

      Minitest.after_run do
        File.write(#{marker_path.inspect}, "ran")
      end

      class BinpackerMinitestAfterRunTest < Minitest::Test
        def test_ok
          assert true
        end
      end
    RUBY

    result = Binpacker::Orchestrator.new(config(workers: 1)).run

    expect(result[:passed]).to be true
    expect(File.read(marker_path)).to eq("ran")
  end

  def config(workers:)
    double("config").tap do |config|
      allow(config).to receive(:test_runner).and_return("minitest")
      allow(config).to receive(:test_pattern).and_return("test/**/*_test.rb")
      allow(config).to receive(:test_exclude).and_return([])
      allow(config).to receive(:timing_file).and_return("binpacker.timings")
      allow(config).to receive(:worker_count).and_return(workers)
      allow(config).to receive(:scheduler).and_return({ "algorithm" => "lpt" })
    end
  end

  def write_minitest_file(class_name:, log_path:, methods:)
    FileUtils.mkdir_p("test/unit")
    File.write("test/test_helper.rb", <<~RUBY)
      require "minitest/autorun"
    RUBY
    File.write("test/unit/calc_test.rb", <<~RUBY)
      require "test_helper"

      class #{class_name} < Minitest::Test
        LOG_PATH = #{log_path.inspect}

        #{methods.map { |method_name| minitest_method(method_name) }.join("\n\n")}
      end
    RUBY
  end

  def minitest_method(method_name)
    <<~RUBY
      def #{method_name}
        File.open(LOG_PATH, "a") { |file| file.puts #{method_name.inspect} }
        assert true
      end
    RUBY
  end

  def remove_minitest_class(class_name)
    Object.send(:remove_const, class_name) if Object.const_defined?(class_name, false)
    return unless defined?(Minitest::Runnable)

    Minitest::Runnable.runnables.delete_if { |klass| klass.name == class_name.to_s }
  end

  def clear_minitest_after_run_hooks
    return unless defined?(Minitest)
    return unless Minitest.class_variable_defined?(:@@after_run)

    Minitest.class_variable_set(:@@after_run, [])
  end
end
