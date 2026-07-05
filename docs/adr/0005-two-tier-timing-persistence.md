# Two-tier timing persistence: CI cache plus a committable baseline

Timing data persists in two layers. The runtime layer is an `actions/cache` entry that CI restores and saves every run (the hot path). The durable layer is an optional `binpacker.timings` committed to the repository as a baseline, which `binpacker-improve` recommends adding when the evidence warrants — it is never forced.

## Context

- Good scheduling needs Weights from prior runs. A CI cache is the natural runtime store, but cache keys that include a lockfile hash miss on every dependency bump (observed directly in the Rigor CI analysis, local issue 02), and a cache miss means an unweighted first run.
- Committing the Timing file to git fixes cold starts and makes Weight changes reviewable in a PR, but committing on every run would churn the repository.
- These pull in opposite directions, so the choice was framed as cache *versus* commit. The resolution is that they are different layers, not alternatives.

## Decision

1. **Runtime layer — `actions/cache` (default, automatic).** The scaffolded CI workflow restores and saves `binpacker.timings` each run. Because the Timing file is append-only JSON Lines (merge-friendly), the cached file is baseline-plus-accumulated-measurements.
2. **Durable layer — committed baseline (recommended, interactive).** `binpacker.timings` may be committed to the repo as a cold-start floor. `binpacker-improve` proactively recommends committing (or refreshing) it, with reasons, when it detects: frequent cache misses (dependency-bump churn), stabilised timings (low drift — a good moment to fix a canonical baseline), or high drift (re-calibrate with `binpacker calibrate --incremental`, then commit).
3. **Precedence.** Restore cache if present (accumulated history); on cache miss fall back to the committed baseline; after the Run, append actuals and save the cache.
4. **Confirmation.** Persistence is always confirmed with the user. `improve` only *recommends*; it never commits automatically. This matches the workflow's propose-only stance.

## Consequences

- `binpacker describe` and `binpacker-improve` share cache-miss detection as a signal.
- The repo is not churned by default; a committed baseline appears only when the user accepts a recommendation.
- The append-only, merge-friendly Timing format (see `docs/design/timing-file-format.md`) is what lets the two layers compose without a merge strategy.
