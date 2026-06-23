# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **[worker]** Dynamic scheduling now persists timing records from the first batch a worker completes.

## [0.1.0] - 2026-06-23

v0.1.0 fixes a critical correctness bug where worker processes ran serially instead of in parallel, and adds the README with setup instructions and a roadmap.

### Added

- **[docs]** README with setup instructions, `binpacker.yml` example, and roadmap.

### Fixed

- **[orchestrator]** Workers now run in parallel. Previously `Orchestrator#run` called `worker.finish` (which sent the "done" signal and then blocked waiting for results) sequentially per worker, collapsing N-way parallelism into a serial chain. Split into `signal_done` (send "done" to all workers first) and `collect_results` (collect results after all workers are running).

## [0.0.3] - 2026-06-23

v0.0.3 fixes a bug where RSpec's progress output was written to a file named `2` in the working directory instead of stderr.

### Fixed

- **[worker]** RSpec progress formatter now correctly writes to stderr via `/dev/stderr` instead of creating a spurious file named `2` in the working directory.

## [0.0.2] - 2026-06-23

v0.0.2 fixes incorrect handling of UTF-8 test names and file paths throughout the timing file and worker IPC pipeline, ensuring binpacker works correctly on projects with non-ASCII test descriptions or file names.

### Fixed

- **[timing]** Timing file reads and writes now use UTF-8 encoding, preventing `Encoding::CompatibilityError` on test names or file paths containing non-ASCII characters.
- **[worker]** Worker process pipes now use UTF-8 encoding, preserving non-ASCII test names through the IPC channel and the RSpec JSON output reader.

## [0.0.1] - 2026-06-23

First public release. Minimizes CI test-suite makespan by solving an
identical-machines scheduling problem with LPT scheduling and optional
work-stealing.

### Added

- **[CLI]** `binpacker` command wraps an arbitrary test runner, spawning N worker
  processes and distributing tests among them.
  - Passes through all arguments after `--` to the test runner.
  - Forwards worker stdout/stderr to the parent and propagates the exit code.
  - Handles SIGINT gracefully, forwarding it to all workers.
- **[scheduling]** LPT (Longest Processing Time) scheduler assigns tests to
  workers using timing data; falls back to filesize when no timing exists.
  - Self-correcting: timing data is updated after each run so the next
    schedule improves automatically.
- **[work-stealing]** Idle workers pull remaining tests from a shared queue
  when their own queue is exhausted.
- **[calibration]** `binpacker calibrate` runs tests serially to seed the
  timing file before the first parallel run.

[Unreleased]: https://github.com/rigortype/binpacker/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/rigortype/binpacker/compare/v0.0.3...v0.1.0
[0.0.3]: https://github.com/rigortype/binpacker/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/rigortype/binpacker/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/rigortype/binpacker/releases/tag/v0.0.1
