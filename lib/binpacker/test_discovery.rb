# frozen_string_literal: true

module Binpacker
  Test = Struct.new(:file, :name, keyword_init: true) do
    # Composite key used as timing lookup and identity.
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

    # Returns Array<Test>. Concrete strategies subclass this.
    def enumerate
      raise NotImplementedError
    end

    private

    def glob_files
      Dir.glob(@pattern).reject { |f|
        @exclude.any? { |ex| File.fnmatch?(ex, f) }
      }
    end
  end

  class RSpecDiscovery < TestDiscovery
    def enumerate
      glob_files.map { |f| Test.new(file: f, name: f) }
    end
  end

  class MinitestDiscovery < TestDiscovery
    # For Minitest, we can't easily enumerate test names without running them.
    # Instead, treat each file as a single test unit, with the file path as the name.
    def enumerate
      glob_files.map { |f|
        Test.new(file: f, name: f)
      }
    end
  end
end
