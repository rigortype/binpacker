# 01 — Timing history never prunes tests that no longer exist

Status: needs-triage
Severity: High

## Problem

`Timing#load_per_file` weighs a file by summing the median of every `[file, name]` entry the history holds:

```ruby
def load_per_file
  samples_by_test.each_with_object({}) do |((file, _name), times), per_file|
    weight = median(times.last(MAX_SAMPLES_PER_TEST))
    per_file[file] = per_file.fetch(file, 0.0) + weight
  end
end
```

`compact!` bounds the history by trimming to `MAX_SAMPLES_PER_TEST` samples **per test**, but it rewrites `samples_by_test` wholesale and never drops a test that has stopped existing. So when a test file is split, renamed or deleted, its entries stay in the file and keep being charged to the old path — indefinitely, since nothing will ever refresh or evict them.

The new path, meanwhile, has no history at all and falls through to `fallback_weight`, i.e. filesize.

## Observed

rigortype/rigor split a 5,955-line spec file, moving 225 of its 357 examples to a new path. On the next CI run ([34274577832](https://github.com/rigortype/rigor/actions/runs/34274577832)):

```
spec/rigor/analysis/runner_spec.rb              predicted=163.895  actual=88.740
spec/rigor/analysis/runner_check_rules_spec.rb  predicted=0.309    actual=66.544
```

The old path was still carrying the moved examples' weight; the new one was weighed as a KB-scale filesize fallback. The shard holding them went from 5.8% to **43.6%** actual deviation and its job from 189s to 213s. **A correct split made the balance worse**, and would have stayed worse until the history was discarded by hand.

This is also a trap for `binpacker-improve`: the signature is a file whose `predicted` far exceeds its `actual` in the drift list, which reads exactly like stale timing data and invites a `calibrate --incremental` that cannot fix it — the stale entries are for tests `calibrate` will never run.

## Suggested fix

Prune at `compact!` time by existence on disk:

```ruby
samples.reject! { |(file, _name), _times| !File.exist?(file) }
```

Existence is the conservative predicate here. "Not discovered in this run" is **not** safe — a sharded run sees only its own slice, and a filtered run sees less than that — so pruning on the run's test set would delete siblings' history. Pruning on a missing file catches split / rename / delete exactly, which is the case that costs whole blocks of weight. An example renamed *within* a surviving file still ghosts, but that is one example's weight rather than a third of a file's.

Worth considering alongside: a warning when a run's discovered set and the history diverge sharply, so the condition is visible rather than silent.

## Interim workaround (now documented)

Discard the history: `rm` the timing file locally, or bump a generation token in the CI cache key. On GitHub Actions that costs two cold runs, not one — caches saved on a feature branch are invisible to the default branch, so the first run after the merge is cold as well.
