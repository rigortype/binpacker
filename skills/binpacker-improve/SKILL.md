---
name: binpacker-improve
description: Tune an already-configured binpacker project from real CI data — fetch recent run reports, analyze the gap between predicted and actual durations, and propose binpacker.yml adjustments. Use when binpacker is set up and running in CI and the user wants to reduce makespan, fix worker imbalance, or refresh stale timing data. Propose-only — never apply changes without confirmation.
---

# Binpacker Improve

A recurring, **propose-only** workflow. It reads real CI data and proposes config changes; it never edits `binpacker.yml`, commits, or pushes without explicit user confirmation.

Run `binpacker describe` first. If it recommends `binpacker-setup`, the project isn't configured yet — use that skill instead.

## 1. Gather CI data

Fetch recent run reports (see `docs/design/run-report-format.md` for the schema) from CI artifacts:

```sh
gh run list --workflow <ci-workflow> --limit 10
gh run download <run-id> --name <report-artifact>
```

Collect several recent reports so you can see trends, not just one run. Each report holds `predicted_makespan`, `actual_makespan`, per-worker predicted/actual durations, `balance`, and the worst-drift Tests.

## 2. Analyze

Look for patterns across the reports:

- **Persistent worker skew** — the same worker is consistently slowest → the partition or worker count is off.
- **Predicted vs actual gap** — `actual_makespan` far above `predicted_makespan` → timing data is stale; the scheduler is planning against wrong Weights.
- **Recurring high-drift files** — the same files top the `drift` list every run → their timing data is stale or they are outliers.
- **Cache-miss frequency** — if CI logs show frequent timing-cache misses (e.g. after dependency bumps), the runtime cache isn't helping cold starts.

## 3. Propose

Present a concrete `binpacker.yml` diff and/or commands, with the evidence behind each change. Typical levers:

- **`workers`** — raise/lower the `ci` worker count when actual makespan shows consistent under- or over-utilisation.
- **`scheduler.algorithm`** — `lpt` ↔ `multifit`. Prefer `multifit` for tighter balance; only suggest `lpt` if `multifit` isn't helping.
- **`scheduler.steal_enabled`** — enable when static balance is poor but runtime stealing would recover it.
- **Re-calibrate** — when drift is high or timing is stale, recommend `binpacker calibrate --incremental` to refresh the drifting Tests.
- **Commit a baseline** — when the cache misses often (dependency-bump churn) or timings have stabilised, recommend committing `binpacker.timings` as a durable baseline (cold-start floor). See `docs/adr/0005-two-tier-timing-persistence.md`.

## 4. Confirm and apply

- Show the diff. Explain the expected effect (e.g. "should cut max deviation from 6% toward <3%").
- Apply only what the user approves. Committing a baseline or editing config both require confirmation.
- If the user wants, open a PR with `gh`; otherwise leave the working tree changes for them to review.

## Done when

- The user has seen the predicted-vs-actual analysis with evidence.
- A concrete, confirmed set of changes (or an explicit "no change needed") has been reached.
- Any commit / PR was made only with confirmation.
