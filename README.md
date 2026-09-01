# binpacker

[![Gem Version](https://badge.fury.io/rb/binpacker.svg?icon=si%3Arubygems)](https://badge.fury.io/rb/binpacker)
[![GitHub License](https://img.shields.io/github/license/rigortype/rigor)](https://github.com/rigortype/rigor/blob/master/LICENSE)

A test runner wrapper that reduces CI makespan by scheduling the [identical-machines scheduling problem]: assign tests to N worker processes so that the maximum worker runtime is minimized. This is closely related to the [bin packing problem]. It ships MultiFit (default) and LPT (Longest Processing Time first) algorithms, with optional work-stealing between workers at runtime.

## Setup

### Agent-driven setup (recommended)

binpacker ships an agent-driven install and setup flow. Paste this to your AI coding agent (Claude Code, Cursor, etc.) and it will install binpacker and walk the setup interactively:

```
Install binpacker in this project by following the instructions at
https://raw.githubusercontent.com/rigortype/binpacker/master/docs/install.md
```

The agent installs the gem, runs `binpacker describe` to inspect the project, and follows the recommended skill (`binpacker-setup` or `binpacker-improve`). See [docs/design/agent-workflows.md](docs/design/agent-workflows.md).

### Manual setup

Install the gem:

```sh
gem install binpacker
```

Add a `binpacker.yml` at your project root:

```yaml
profiles:
  default:
    test_runner: rspec
    workers: auto
    timing_file: binpacker.timings
    test_pattern: "spec/**/*_spec.rb"
    scheduler:
      algorithm: multifit
      steal_enabled: true
  ci:
    extends: default
    workers: 4
```

For Minitest projects, set `test_runner: minitest` and use your test glob:

```yaml
profiles:
  default:
    test_runner: minitest
    workers: auto
    timing_file: binpacker.timings
    test_pattern: "test/**/*_test.rb"
    scheduler:
      algorithm: multifit
      steal_enabled: true
```

Run calibration once to seed timing data (required before the first parallel run):

```sh
binpacker calibrate
# after adding new specs, measure only the ones without timing data:
binpacker calibrate --incremental
```

Then run your suite in parallel:

```sh
binpacker run
# or pass arguments through to the test runner:
binpacker run -- --tag ~slow
binpacker run -- --name /UserTest#test_creates/
```

`workers: auto` uses the number of available CPU cores. Set `BINPACKER_PROFILE=ci` or pass `--profile ci` to select a profile; CI environments (GitHub Actions, GitLab CI, Jenkins) are auto-detected and fall back to the `ci` profile when present.

## Sharding across machines

Workers divide a suite across the cores of one machine and share its wall clock. A **shard** divides it across machines that have no wall clock in common, so the two compose: each shard runs its own workers over its own slice, and the suite's wall time becomes roughly the slowest shard.

```sh
binpacker run --shard 1/3    # or: BINPACKER_SHARD=1/3 binpacker run
```

The slice is cut by the same weight-balanced partitioner that assigns work to workers, over the same measured timings, so shards carry equal predicted time rather than equal file counts. The cut is a pure function of that timing data: every shard computes the identical N-way partition and keeps only its own bin, which is what lets them agree without talking to each other.

That agreement is also the one thing sharding can get wrong. **Every shard must load the same timing file.** A shard that loads a different one partitions differently, and the failure is silent — some tests land in no shard at all and every job still reports success. A shard cannot notice on its own, because it cannot tell "not mine" from "does not exist".

So audit the matrix afterwards. Give each shard a `--report`, collect them, and check them together:

```sh
binpacker run --shard 1/3 --report shard-1.json    # in each matrix job
binpacker shards-check shard-*.json                # in a job that needs them all
```

`shards-check` fails unless the reports describe one coherent split of one suite: same shard count, same discovered-test count, every index present exactly once, and the slices summing to the whole. In GitHub Actions, upload each shard's report as an artifact and run the check in a job that `needs` the matrix.

How many shards are worth it is bounded by your slowest single file, since a file is the scheduling unit and cannot be split: a shard's wall time can never fall below the heaviest file it holds. Past that point, more shards buy only more job setup.

## Roadmap

- **Example-level granularity for scheduling** — `test_granularity: example` already exists for timing; using it to partition would let sharding past the heaviest-file floor.

## License

Mozilla Public License Version 2.0. See [`LICENSE`](LICENSE).

[Rigor]: https://github.com/rigortype/rigor
[identical-machines scheduling problem]: https://en.wikipedia.org/wiki/Identical-machines_scheduling
[bin packing problem]: https://en.wikipedia.org/wiki/Bin_packing_problem
