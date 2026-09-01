# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-09-01

v0.5.0 is a sharding release: it extends binpacker's balancing past the boundary of a single machine. Workers divide a suite across the cores of one runner and share its wall clock, so a suite's wall time was floored at whatever one machine could do; `binpacker run --shard K/N` cuts the suite into slices that a CI matrix runs in parallel, and the two compose — each shard still runs its own workers over its own slice. Shards agree on the partition without communicating, because each computes the same weight-balanced cut from the same timing data, and that is also the one thing sharding can get wrong: a shard that reads a different timing file leaves tests in no shard at all while every job still reports success. So a sharded run records an audit trail in its report, and `binpacker shards-check` runs after the matrix and fails unless the reports describe one coherent split of one suite.

### Added

- **[sharding]** `binpacker run --shard K/N` runs one slice of the suite, so a CI matrix can split it across machines.
  - Workers divide a suite across one machine's cores; a shard divides it across machines that share no wall clock, and the two compose — each shard runs its own workers over its own slice. The slice is cut by the same weight-balanced partitioner used for workers, over the same timings, so shards carry equal predicted time rather than equal file counts. `BINPACKER_SHARD` is read too, for matrices that set env more easily than they rewrite a command.
- **[sharding]** `binpacker shards-check <report>...` verifies that a matrix's run reports cover the whole suite.
  - Shards agree on the partition only while they agree on the timing data it is cut from, and a shard that loads a different timing file partitions differently — leaving tests in no shard at all while every job still reports success. No single shard can detect that, because it cannot tell "not mine" from "does not exist". The check runs after the matrix, over each shard's `--report`, and fails unless the reports describe one coherent split of one suite.
- **[run report]** A sharded run's report carries a `shard` section: index, total, the whole-suite discovered count, and this shard's selected count.
  - This is what `shards-check` reads. `discovered_tests` is recorded before slicing, so it agrees across shards that see the same repository and gives the sum of `selected_tests` something to be checked against.

## [0.4.0] - 2026-07-15

v0.4.0 is a scheduling-quality release: it makes binpacker's predicted weights trustworthy, and then spends them better. Weights are now the median of a test's recent runs rather than the sum of its entire history, and every weight — measured or estimated from file size — is expressed in seconds, so they can be compared and added up meaningfully. Work-stealing uses those weights to size each batch and to pick which worker to steal from, which cut maximum worker deviation from 8.6% to about 2% on a real four-worker suite. The release also fixes two bugs that could bite anyone running with stealing enabled: a test that reads stdin would deadlock the entire run, and the final example count was inflated on every extra batch.

### Changed

- **[work-stealing]** Batches are now sized by predicted weight instead of a fixed ten files.
  - Each batch drains half of its queue's remaining predicted weight, floored at about 30 seconds of work. Early batches are large, so the per-batch test-runner boot is amortized; tail batches stay small, where balance is actually decided. Stealing also picks the donor with the most remaining predicted time rather than the most files.
- **[timing]** Weights for tests that have never been measured are now expressed in seconds rather than kilobytes.
  - The fallback is still derived from file size, but it is scaled through a seconds-per-kilobyte coefficient estimated from the tests that do have measurements. A suite mixing measured and brand-new tests now compares all of its weights in one unit.
- **[timing]** The timing file is compacted after each run to the three most recent samples per test.
  - The file — and any CI cache built from it — stays bounded instead of growing by one full run per invocation.

### Removed

- **[timing]** `Timing#weight_for` is gone; use `load_with_fallback` for scheduling weights or `load_raw` for measured samples.
  - It had no callers, and it was the last API returning a raw-kilobyte weight now that every other weight is in seconds.

### Fixed

- **[scheduling]** A test file's weight is now the median of its recent samples instead of the sum of its entire recorded history.
  - Summing meant a file present in N historical runs weighed roughly N times its true cost, so long-lived files dominated the partition while newly added ones were starved. On a real four-worker suite with an 80-run timing cache this alone caused about 7% worker imbalance, even when every individual prediction was accurate.
- **[work-stealing]** Runs with no timing data no longer disable batching and stealing on small suites.
  - The batch floor is a duration, but an uncalibrated run weighs files in kilobytes, so a 30-second floor was read as 30 kilobytes. On a small codebase that exceeded a worker's entire queue, silently collapsing dynamic scheduling into a static one. Uncalibrated runs now derive a size-independent floor instead.
- **[worker]** A test that reads stdin no longer hangs the run when stealing is enabled.
  - Worker stdin is the orchestrator's control pipe, and spawned test processes inherited it. Static scheduling hid this because the pipe closes after the only batch; with stealing the pipe stays open between batches, so the test blocked on it forever and deadlocked the run. Worker stdin now points at `/dev/null`, so such tests see EOF.
- **[progress]** The final example count is no longer inflated when workers run more than one batch.
  - Each batch re-added the worker's cumulative example count to the grand total. Totals are now summed once from the per-worker finals.
- **[progress]** The per-worker summary no longer prints the same worker id twice when two workers finish with identical stats.

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

[Unreleased]: https://github.com/rigortype/binpacker/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/rigortype/binpacker/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/rigortype/binpacker/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/rigortype/binpacker/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/rigortype/binpacker/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rigortype/binpacker/compare/v0.0.3...v0.1.0
[0.0.3]: https://github.com/rigortype/binpacker/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/rigortype/binpacker/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/rigortype/binpacker/releases/tag/v0.0.1
