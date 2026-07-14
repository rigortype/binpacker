# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **[scheduler]** Work-stealing batches are weight-guided instead of a fixed 10 files: each batch drains half the queue's remaining predicted weight (floored at ~30s of predicted work), so early batches amortize the per-batch test-runner boot while tail batches stay fine-grained for balance. Stealing now picks the donor with the most remaining predicted time rather than the most files.
- **[timing]** The timing file is compacted after each run to the last 3 samples per test, keeping it — and any CI cache built from it — bounded instead of growing by one run per invocation.
- **[timing]** Unmeasured files' fallback weights are scaled from KB into seconds via a coefficient estimated from measured files, so mixed measured/unmeasured suites compare weights in one unit.

### Removed

- **[timing]** `Timing#weight_for`, which had no callers and returned raw KB for unmeasured tests while every other weight is now expressed in seconds. Use `load_with_fallback` for unit-consistent weights or `load_raw` for measured samples.

### Fixed

- **[scheduler]** Per-file weights are now the median of each test's recent samples. Previously the entire append-only history was summed, so a file present in N historical runs weighed ~N× its true cost — long-lived files dominated the partition and newly added ones were starved, producing avoidable worker imbalance (observed at up to ~7% max deviation on a real 4-worker CI suite even with perfect predictions).
- **[progress]** The per-worker summary printed the same worker id twice when two workers finished with identical stats.
- **[scheduler]** The cold-start batch floor no longer misreads 30 seconds as 30 KB. On small codebases the old floor could exceed a worker's whole queue and silently disable dynamic batching and stealing.

## [0.3.0] - 2026-07-05

v0.3.0 turns binpacker into an agent-driven tool. A hosted install guide hands off to gem-shipped `binpacker-setup` and `binpacker-improve` skills, discovered through a new `binpacker skill`/`describe` CLI that inspects a project and recommends the next step. Runs can now emit a machine-readable report of predicted-versus-actual per-worker durations for tuning, and calibration can fill in only the tests that lack timing data. The release also fixes a handful of correctness issues found while validating the flow against real projects: `--version`, file-granularity calibration, and a clear message when a project uses an unsupported framework.

### Added

- **[setup]** Agent-driven install and setup: a hosted `docs/install.md` plus gem-shipped `binpacker-setup` (one-time bootstrap) and `binpacker-improve` (recurring, propose-only tuning) skills.
- **[CLI]** `binpacker describe` (and `binpacker skill`) reports project state — config, timing data, framework, CI wiring — and recommends the next skill to run.
- **[CLI]** `binpacker calibrate --incremental` measures only the tests that have no timing data yet, leaving existing weights untouched.
- **[CLI]** `binpacker run --report PATH` (and the `report_file` config key, default on the `ci` profile) writes a JSON run report of predicted-versus-actual per-worker durations plus the worst per-file drift.

### Changed

- **[progress]** The per-worker summary labels the scheduled unit as `tests` rather than `files`, which is accurate at both file and example granularity.

### Fixed

- **[CLI]** `binpacker --version` now prints the version instead of the help text.
- **[calibration]** File-granularity calibration runs the whole file instead of measuring only test-runner boot time.
- **[discovery]** test-unit projects are detected and reported as unsupported, instead of failing later with an opaque `cannot load such file -- minitest` error.

## [0.2.0] - 2026-06-23

v0.2.0 broadens binpacker beyond RSpec and makes a parallel run far easier to watch. Minitest is now a first-class runner, and a live progress display with a per-worker timing summary reports balance as the run proceeds. Scheduling gains a MULTIFIT algorithm, batch-level work-stealing, and an opt-in example-level granularity that partitions individual examples rather than whole files. A new `binpacker init` command scaffolds configuration, and two correctness fixes keep timing data and progress output reliable in restricted environments.

### Added

- **[runner]** Minitest support with per-example timing, selectable via `test_runner: minitest`.
- **[scheduling]** MULTIFIT partitioning algorithm using binary search, selectable via the scheduler `algorithm` setting.
- **[scheduling]** Batch-level work-stealing where idle workers steal batches from the busiest worker's queue.
- **[scheduling]** Example-level test granularity via `test_granularity: example`, scheduling individual examples discovered with `rspec --dry-run`.
  - The default remains `file`. Workers still run whole files, and examples that land on more than one worker are de-duplicated by the timing data.
- **[CLI]** `binpacker init` command that writes a `binpacker.yml` with auto-detected settings.
- **[CLI]** `--quiet` flag to suppress worker output.
- **[progress]** Live progress display with TTY animation and periodic CI-friendly output.
- **[progress]** Per-worker timing summary printed after each run, reporting load-balance deviation.
  - Shown in both dynamic and static scheduling modes.

### Fixed

- **[worker]** RSpec progress formatter output no longer depends on opening `/dev/stderr`, avoiding `Errno::EPERM` in restricted environments.
- **[orchestrator]** Dynamic scheduling now persists timing records from batches completed through the active work-stealing loop.

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

[Unreleased]: https://github.com/rigortype/binpacker/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/rigortype/binpacker/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/rigortype/binpacker/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rigortype/binpacker/compare/v0.0.3...v0.1.0
[0.0.3]: https://github.com/rigortype/binpacker/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/rigortype/binpacker/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/rigortype/binpacker/releases/tag/v0.0.1
