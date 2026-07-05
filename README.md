# binpacker

[![Gem Version](https://badge.fury.io/rb/binpacker.svg?icon=si%3Arubygems)](https://badge.fury.io/rb/binpacker)
[![GitHub License](https://img.shields.io/github/license/rigortype/rigor)](https://github.com/rigortype/rigor/blob/master/LICENSE)

A test runner wrapper that reduces CI makespan by scheduling the [identical-machines scheduling problem]: assign tests to N worker processes so that the maximum worker runtime is minimized. This is closely related to the [bin packing problem]. It ships MultiFit (default) and LPT (Longest Processing Time first) algorithms, with optional work-stealing between workers at runtime.

## Setup

Install the gem:

```sh
gem install binpacker
```

> [!NOTE]
> An AI-powered setup workflow (similar to [Rigor]'s `rigor-project-init`) is coming soon — stay tuned.

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

## Roadmap

- **AI-powered setup & improve workflows** — agent-driven `/binpacker-setup` and `/binpacker-improve` that calibrate, validate a parallel run, and tune settings from CI results.
- **Container/machine-level workers** — extend the Worker model beyond single-job processes to distribute Tests across containers or machines.

## License

Mozilla Public License Version 2.0. See [`LICENSE`](LICENSE).

[Rigor]: https://github.com/rigortype/rigor
[identical-machines scheduling problem]: https://en.wikipedia.org/wiki/Identical-machines_scheduling
[bin packing problem]: https://en.wikipedia.org/wiki/Bin_packing_problem
