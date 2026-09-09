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

### When shards finish at visibly different times

Reach for the reports before reaching for the config, because the most common cause is not the partition. Compare each report's `predicted_makespan`: if they agree, binpacker cut equal slices and the difference came from somewhere else. In one real matrix the three slices were 534.6s of predicted weight apiece and the jobs still ran 339s, 172s and 117s — the spread was 145s of *other* steps pinned to the first matrix job with `if: matrix.shard == 1`, which no scheduler setting could have fixed. Anything a matrix runs once and pins to an arbitrary arm belongs in its own job.

When the predicted makespans genuinely differ, one file is over the per-worker budget. Divide the suite's total predicted weight by shards × workers to get the floor every shard should reach, and look for a `predicted` above it in the reports — that file occupies a whole worker and sets its shard's makespan on its own.

Splitting such a file is easier than it looks, because the cost is usually concentrated rather than spread. The timing file records per **example**, so you can attribute a file to its blocks without instrumenting anything:

```sh
# Sum the median of each example's samples, grouped by whatever prefix you care about
ruby -rjson -e '
  rows = Hash.new { |h, k| h[k] = [] }
  File.foreach("tmp/binpacker.timings") do |l|
    r = JSON.parse(l) rescue next
    rows[r["name"]] << r["time"] if r["file"] == ARGV[0]
  end
  rows.each { |name, ts| puts format("%7.2f  %s", ts.sort[ts.size / 2], name) }
' spec/path/to/heavy_spec.rb | sort -rn | head -40
```

In the case above, one block was 65% of a 5,955-line file and the next was 9% — a single seam rather than a judgement call about where to cut.

**Before you split, read the two traps below.** A split is not free: binpacker will keep charging the old path for the tests that moved.

## Timing data after a file moves

binpacker weighs a file by summing the median of every `[file, name]` entry its history holds, and compaction trims samples per test without ever dropping a test that has stopped existing. Splitting, renaming or deleting a test file therefore leaves its old entries in place, charged to the old path forever, while the new path has no history and falls back to filesize weighting.

Measured on a real split: the old path stayed predicted at 163.9s while running 88.7s, and the new file was predicted at 0.3s against 66.5s actual. The shard holding them went from 5.8% to 43.6% deviation — the split made the balance *worse* until the history was discarded.

So after any such change, drop the timing history and let it rebuild. Locally that is `rm` on the timing file; in CI, put a generation token in the cache key and bump it:

```yaml
key: binpacker-timings-v2-${{ runner.os }}-${{ github.run_id }}
restore-keys: binpacker-timings-v2-${{ runner.os }}-
```

Two things to expect afterwards. The first run partitions on filesize weighting, which is the documented cold-start path and costs one noisy run. And on GitHub Actions a cache saved on a feature branch is invisible to the default branch, so the first run *after the merge* is cold as well — the bump costs two cold runs, not one. Do not read a partition's balance from a run whose restore step logged `Cache not found for input keys`.

## Roadmap

- **Example-level granularity for scheduling** — `test_granularity: example` already exists for timing; using it to partition would let sharding past the heaviest-file floor.

## License

Mozilla Public License Version 2.0. See [`LICENSE`](LICENSE).

[Rigor]: https://github.com/rigortype/rigor
[identical-machines scheduling problem]: https://en.wikipedia.org/wiki/Identical-machines_scheduling
[bin packing problem]: https://en.wikipedia.org/wiki/Bin_packing_problem
