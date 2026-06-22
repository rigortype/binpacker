# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/rigortype/binpacker/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/rigortype/binpacker/releases/tag/v0.0.1
