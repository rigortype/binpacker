# Rigor shard rebalance — findings for binpacker

Status: needs-triage

## Source

rigortype/rigor, 2026-09-09. Three PRs ([#863](https://github.com/rigortype/rigor/pull/863), [#867](https://github.com/rigortype/rigor/pull/867), [#889](https://github.com/rigortype/rigor/pull/889)) took the workflow from 371s to 220s. Run reports from 34269150881, 34274577832, 34275199747, 34318103625.

Follows `.scratch/rigor-ci-analysis/`, which analysed the same project's CI a cycle earlier. No overlap with issues 01–05 there.

## What the reports said

The presenting symptom was a 222s spread across a three-shard matrix (jobs at 339s / 172s / 117s). **The partition was not the cause.** LPT had cut all three slices to 534.6s of predicted weight apiece, and two of the three hit the twelve-worker theoretical floor exactly (`predicted_makespan: 133.661`, `actual_deviation_pct: 0.0`).

Two other things produced the spread:

1. **145s of steps pinned to one matrix arm.** Two suites outside the sharded set (`test_exclude`) ran as steps guarded by `if: matrix.shard == 1`. Nothing about them belonged to shard 1; they were parked there because the matrix runs once. Moving them to a peer job recovered 127s of critical path — more than every scheduler lever combined.
2. **One file over the per-worker budget.** `runner_spec.rb` weighed ~167s against a ~134s floor, so LPT correctly gave it a whole worker and the shard's makespan became that one file. Splitting it was the only remaining lever.

Both are worth teaching, because the first is invisible from binpacker's own data (the reports look balanced) and the second is easy to find in it (one `predicted` above the floor).

## Finding the seam is cheap, and the docs did not say so

The timing file records per **example**, so a heavy file can be attributed to its blocks with a few lines of Ruby and no instrumentation. On `runner_spec.rb` (5,955 lines) one `describe` was 65.2% of the cost and the next was 9.4% — a single seam, not a judgement call. This turned "split a 6,000-line file somehow" into a mechanical move.

## Then the split made things worse

Two binpacker behaviours turned a correct split into a regression, neither documented. Both are filed as issues:

| # | Slug | Severity | Summary |
|---|------|----------|---------|
| 01 | [timing-never-prunes-vanished-tests](issues/01-timing-never-prunes-vanished-tests.md) | High | A split/rename/delete leaves the old path charged for the moved tests forever |
| 02 | [report-write-no-mkpath](issues/02-report-write-no-mkpath.md) | Medium | `--report` into a missing directory raises `ENOENT`, and the failure also loses the run's timings |

## Documentation landed alongside

- README — a "When shards finish at visibly different times" subsection (rule out non-binpacker causes first; find the over-budget file; the per-example attribution recipe) and a "Timing data after a file moves" section.
- `binpacker-improve` — the over-budget-file pattern, ruling out pinned matrix steps, discarding history after a move, and not trusting a report from a cache-miss run.
- `binpacker-setup` — the generation token in the cache key, the `--report` directory, and the two-cold-runs cost of a bump.
