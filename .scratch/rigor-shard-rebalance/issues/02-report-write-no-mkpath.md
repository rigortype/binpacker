# 02 — `--report` into a missing directory raises ENOENT, and takes the run's timings with it

Status: needs-triage
Severity: Medium

## Problem

`Report#write` is a bare `File.write`:

```ruby
def write(path)
  File.write(path, JSON.pretty_generate(to_h))
end
```

`Timing#append` / `#append_all` both do `@path.dirname.mkpath` first, so the timing file creates its own directory and the report does not. `--report tmp/report.json` therefore raises `Errno::ENOENT` unless something else already made `tmp/`.

In CI that "something else" is usually `actions/cache` restoring the timing file into the same directory. The dependency is invisible: every run passes while the cache hits, and the first genuine miss fails the job.

## Observed

rigortype/rigor bumped its timing-cache key (to discard the history — see issue 01) and the next run's whole test matrix failed ([34275199747](https://github.com/rigortype/rigor/actions/runs/34275199747)) with **every one of the shard's 3,357 examples passing**:

```
Finished in 1 minute 37.56 seconds
367 examples, 0 failures

bundler: failed to load command: binpacker
binpacker/report.rb:47:in 'IO.write': No such file or directory @ rb_sysopen - tmp/binpacker-report-1.json (Errno::ENOENT)
	from binpacker/report.rb:47:in 'Binpacker::Report#write'
	from binpacker/orchestrator.rb:258:in 'Binpacker::Orchestrator#write_report'
```

## Second problem, same trace

Both run paths call `write_report` **before** `finalize` — the static one at `orchestrator.rb:131` and the dynamic one at `:239`:

```ruby
progress.summary(worker_stats)
write_report(worker_stats, all_timings)

workers.each(&:cleanup)
finalize(timing, all_timings, all_passed, total_examples, passed_examples, tests)
```

So a failed report write also discards the run's measured timings. In the case above that turned a one-run cold start into a two-run one: the run that was supposed to re-measure the suite recorded nothing.

## Suggested fix

Two independent changes:

1. `Report#write` mkpaths its own directory, matching `Timing#append`.
2. `write_report` moves after `finalize`, or is wrapped so a report failure cannot cost the timings. The report is a diagnostic artifact; the timing history is state the next run depends on, and it should be the more durable of the two.

## Interim workaround (now documented)

`mkdir -p` the report directory in the CI step before `binpacker run`.
