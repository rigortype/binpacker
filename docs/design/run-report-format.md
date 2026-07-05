# Run Report Format

A Run report is a single machine-readable JSON document describing one `binpacker run`: what the scheduler *predicted* versus what actually happened. It is written when `binpacker run --report <path>` is set (the `ci` profile sets a default path). It is additive — the human-readable summary printed to stdout is unchanged.

The report is the data the `binpacker-improve` workflow reasons over. See [ADR-0004](../adr/0004-structured-run-report.md).

## Schema

```json
{
  "schema": 1,
  "profile": "ci",
  "algorithm": "multifit",
  "worker_count": 4,
  "predicted_makespan": 333.0,
  "actual_makespan": 354.5,
  "workers": [
    { "id": 0, "predicted": 333.1, "actual": 354.5, "tests": 70, "examples": 1703 }
  ],
  "balance": { "predicted_deviation_pct": 0.3, "actual_deviation_pct": 6.4 },
  "drift": [
    { "file": "spec/slow_spec.rb", "predicted": 5.0, "actual": 7.2 }
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `schema` | int | Report schema version. Bumped on incompatible changes. |
| `profile` | string | The active `binpacker.yml` profile. |
| `algorithm` | string | Scheduling algorithm used (`lpt`, `multifit`). |
| `worker_count` | int | Number of Workers. |
| `predicted_makespan` | float | Highest predicted per-Worker load, in seconds (the scheduler's estimate). |
| `actual_makespan` | float | Highest measured per-Worker duration, in seconds. |
| `workers[]` | array | Per-Worker predicted/actual durations and counts. |
| `workers[].predicted` | float | Sum of scheduled Test Weights for this Worker at partition time. |
| `workers[].actual` | float | Measured wall-clock duration for this Worker. |
| `workers[].tests` | int | Number of scheduled Tests (the schedulable unit; files or examples depending on granularity). |
| `workers[].examples` | int | Number of examples executed by this Worker. |
| `balance.predicted_deviation_pct` | float | Max predicted-load deviation from a perfect split, as a percentage. |
| `balance.actual_deviation_pct` | float | Max actual deviation from a perfect split, as a percentage. |
| `drift[]` | array | Top-N files by absolute predicted-vs-actual gap, largest first. Predicted and actual are both aggregated to file level so the comparison holds even when timings are recorded per example. |

## Conventions

- **Encoding**: UTF-8. A single JSON object (not JSON Lines — one report per Run).
- **Emission**: Only when `--report <path>` is set. The `ci` profile carries a default path so CI always emits one.
- **`drift` cap**: Top-N files by `|actual - predicted|` (N is a small constant, e.g. 10). Never the full file set — see ADR-0004.
- **`drift` granularity**: Per file. Both predicted (schedule-time weights) and actual (measured times) are summed to normalized file paths, so drift is meaningful whether timings are recorded per file or per example.
- **Additive**: The report never replaces the human-readable stdout summary.

## Rationale

- **Predicted vs actual is the unit of improvement.** Worker count, algorithm choice, and stale-timing detection all follow from where prediction diverged from reality.
- **One JSON object, not JSON Lines.** Unlike the append-only Timing file, a report describes one Run and is consumed whole; a single object is the simpler shape.
- **Versioned.** `binpacker-improve` treats the schema as a contract; the `schema` field lets it evolve safely.
- **Artifact-friendly.** Emitted to a path so CI can `upload-artifact` it for the Improve workflow to fetch across runs.
