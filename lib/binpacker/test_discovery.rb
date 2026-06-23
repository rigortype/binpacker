# frozen_string_literal: true

module Binpacker
  Test = Struct.new(:file, :name, keyword_init: true) do
    def key
      [file, name]
    end
  end

  class TestDiscovery
    def initialize(config)
      @config = config
      @pattern = config.test_pattern
      @exclude = config.test_exclude
    end

    def enumerate
      raise NotImplementedError
    end

    private

    def glob_files
      Dir.glob(@pattern).reject { |f|
        @exclude.any? { |ex| File.fnmatch?(ex, f) }
      }
    end

    def add_project_load_paths
      %w[lib test].each do |path|
        expanded = File.expand_path(path)
        $LOAD_PATH.unshift(expanded) if Dir.exist?(expanded) && !$LOAD_PATH.include?(expanded)
      end
    end
  end

  class RSpecDiscovery < TestDiscovery
    def enumerate
      if @config.respond_to?(:test_granularity) && @config.test_granularity == "example"
        enumerate_examples
      else
        glob_files.map { |f| Test.new(file: f, name: f) }
      end
    end

    private

    def enumerate_examples
      files = glob_files
      return [] if files.empty?

      examples = run_dry_run(files)
      examples.map { |ex|
        Test.new(
          file: ex["file_path"],
          name: ex["full_description"] || ex["description"]
        )
      }
    end

    def run_dry_run(files)
      cmd = ["rspec", "--dry-run", "--format", "json", *files, { err: File::NULL }]
      out = IO.popen(cmd) { |io| io.read }
      JSON.parse(out)["examples"] || []
    rescue JSON::ParserError
      raise DiscoveryError, "failed to parse rspec --dry-run output"
    end
  end

  class MinitestDiscovery < TestDiscovery
    def enumerate
      require "minitest"
      add_project_load_paths
      def Minitest.autorun; end
      Minitest.seed = 42

      tests = []
      glob_files.each do |file|
        begin
          klasses_before = Minitest::Runnable.runnables.dup
          load File.expand_path(file)

          (Minitest::Runnable.runnables - klasses_before).each do |klass|
            klass.runnable_methods.each do |method_name|
              tests << Test.new(file: file, name: "#{klass}##{method_name}")
            end
          end
        rescue => e
          $stderr.puts "minitest discovery: failed to load #{file}: #{e.message}"
        end
      end
      tests
    end
  end
end
