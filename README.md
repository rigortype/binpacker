# binpacker

[![Gem Version](https://badge.fury.io/rb/binpacker.svg?icon=si%3Arubygems)](https://badge.fury.io/rb/binpacker)
[![GitHub License](https://img.shields.io/github/license/rigortype/rigor)](https://github.com/rigortype/rigor/blob/master/LICENSE)

A test runner wrapper that minimizes CI makespan by solving the [identical-machines scheduling problem]: distribute tests across N worker processes using LPT (Longest Processing Time first) scheduling with optional work-stealing.

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
      algorithm: lpt
      steal_enabled: true
  ci:
    extends: default
    workers: 4
```

Run calibration once to seed timing data (required before the first parallel run):

```sh
binpacker calibrate
```

Then run your suite in parallel:

```sh
binpacker run
# or pass arguments through to the test runner:
binpacker run -- --tag ~slow
```

`workers: auto` uses the number of available CPU cores. Set `BINPACKER_PROFILE=ci` or pass `--profile ci` to select a profile; CI environments (GitHub Actions, GitLab CI, Jenkins) are auto-detected and fall back to the `ci` profile when present.

## Roadmap

- **Minitest support** — currently only RSpec is fully supported; Minitest support is planned.
- **Dynamic scheduling** — idle workers pull tests from a shared queue at runtime instead of using a pre-computed static partition.
- **`multifit` algorithm** — LPT-based initial partition with a binary-search optimisation pass for tighter makespan bounds.
- **`binpacker calibrate --incremental`** — update only the tests whose timing data has grown stale rather than re-running the full suite serially.

## License

Mozilla Public License Version 2.0. See [`LICENSE`](LICENSE).

[Rigor]: https://github.com/rigortype/rigor
[identical-machines scheduling problem]: https://en.wikipedia.org/wiki/Identical-machines_scheduling
