# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "minitest"

RSpec.describe Binpacker::TestDiscovery do
  let(:config) do
    double("config").tap do |c|
      allow(c).to receive(:test_pattern).and_return("spec/**/*_spec.rb")
      allow(c).to receive(:test_exclude).and_return([])
    end
  end

  describe Binpacker::RSpecDiscovery do
    around do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        FileUtils.mkdir_p(File.join(dir, "spec/models"))
        FileUtils.touch(File.join(dir, "spec/models/user_spec.rb"))
        FileUtils.touch(File.join(dir, "spec/models/post_spec.rb"))
        Dir.chdir(dir) { example.run }
      end
    end

    it "discovers spec files by pattern" do
      tests = described_class.new(config).enumerate
      expect(tests.size).to eq(2)
    end

    it "returns Test objects with file == name" do
      tests = described_class.new(config).enumerate
      expect(tests.first.file).to match(/_spec\.rb$/)
      expect(tests.first.name).to match(/_spec\.rb$/)
    end
  end

  describe Binpacker::MinitestDiscovery do
    around do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        FileUtils.mkdir_p(File.join(dir, "test/unit"))
        test_file = File.join(dir, "test/unit/calc_test.rb")
        lib_file = File.join(dir, "lib")
        FileUtils.mkdir_p(lib_file)
        File.write(test_file, <<~RUBY)
          require "minitest/autorun"

          class CalcTest < Minitest::Test
            def test_add; assert_equal 5, 2 + 3; end
            def test_sub; assert_equal 1, 3 - 2; end
          end
        RUBY
        $LOAD_PATH.unshift(lib_file)
        Dir.chdir(dir) { example.run }
        $LOAD_PATH.shift
      end
    end

    let(:minitest_config) do
      double("config").tap do |c|
        allow(c).to receive(:test_pattern).and_return("test/**/*_test.rb")
        allow(c).to receive(:test_exclude).and_return([])
      end
    end

    it "discovers test methods via class loading" do
      tests = described_class.new(minitest_config).enumerate
      names = tests.map(&:name)
      expect(names).to include("CalcTest#test_add")
      expect(names).to include("CalcTest#test_sub")
      expect(tests.size).to eq(2)
    end
  end

  describe "#not_implemented" do
    it "raises on base class" do
      expect { described_class.new(config).enumerate }.to raise_error(NotImplementedError)
    end
  end
end
