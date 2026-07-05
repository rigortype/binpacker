# Structured run report for the improve workflow

`binpacker run --report <path>` writes a machine-readable JSON report of a Run's predicted versus actual per-Worker durations, plus the worst per-Test drift. This is the data substrate the `binpacker-improve` workflow reasons over; the human-readable summary is unchanged and remains the default.

## Context

- Today `binpacker run` emits only human-readable text (per-Worker times, balance deviation). Nothing captures the scheduler's *predicted* makespan, so nothing can measure prediction error after the fact.
- The scheduler already computes each Worker's predicted load (sum of Weights) at partition time, and actual per-Worker durations are already collected. Both halves exist; only a structured emission is missing.
- `binpacker-improve` (ADR-0003) needs predicted-vs-actual data from recent CI runs to propose config changes (worker count, algorithm, steal, re-calibration).

## Decision

1. Add `binpacker run --report <path>`. When set, binpacker writes a JSON report after the Run. The `ci` profile carries a default report path so CI always produces one.
2. The report is **additive** — the existing human-readable output is untouched. `--report` never replaces stdout.
3. Schema (see `docs/design/run-report-format.md`) carries a `schema` version integer, run metadata (profile, algorithm, worker_count), `predicted_makespan` / `actual_makespan`, a per-Worker array of predicted/actual/files/examples, a `balance` block (predicted vs actual deviation), and a `drift` array of the top-N Tests by predicted-vs-actual gap.
4. `drift` is capped at the top N entries, not the full Test set, to bound report size and cost.

## Considered Options

- **Always write to a fixed default path (no flag)** — rejected: surprises non-CI users with an unexpected file; the `ci` profile default covers the case that matters.
- **`--format json` replacing stdout** — rejected: the report and the human summary serve different readers; we want both, not one or the other.
- **Include every Test's drift** — rejected: unbounded size and compute for little gain; the worst N are what `improve` acts on.
- **No `schema` version** — rejected: the report is a consumed contract; versioning lets it evolve without breaking `improve`.

## Consequences

- The scheduler must expose its predicted per-Worker loads to the orchestrator (it computes them already; they just need to surface).
- `binpacker-improve` depends on this schema; changes to it are governed by the `schema` version.
- CI uploads the report as an artifact (ADR-0005 covers timing persistence); `improve` fetches recent artifacts to analyse trends.
