# frozen_string_literal: true

require_relative "binpacker/version"
require_relative "binpacker/config"
require_relative "binpacker/timing"
require_relative "binpacker/test_discovery"
require_relative "binpacker/worker_queue"
require_relative "binpacker/scheduler"
require_relative "binpacker/worker"
require_relative "binpacker/test_runner"
require_relative "binpacker/calibration"
require_relative "binpacker/orchestrator"

module Binpacker
  Error = Class.new(StandardError)
  ConfigError = Class.new(Error)
  DiscoveryError = Class.new(Error)
  SchedulerError = Class.new(Error)
  WorkerError = Class.new(Error)
end
