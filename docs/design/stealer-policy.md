# Stealer Policy

The initial policy is minimal, designed for implementation speed and empirical tuning.

## Default behavior

| Axis | Initial | Rationale |
|------|---------|-----------|
| Steal amount | 1 Test at a time | Finest granularity; IPC overhead is negligible at expected scale |
| Trigger | Worker queue empty | Simplest; no predictive overhead |
| Selection | Largest remaining queue (by count) | Deterministic, matches ADR-0002, no Weight dependency for v1 |

## Tuning axis (future)

These can be made configurable once baseline measurements exist:

- **`steal_batch: N`** — Steal N Tests per request instead of 1. Reduces IPC frequency at the cost of coarser rebalancing.
- **`steal_threshold: N`** — Proactively steal when a Worker's queue drops to N items.
- **`selection: weighted`** — Select donor by sum of Test Weights instead of count. Requires a populated Timing file to be meaningful.

None of these are implemented initially. The default behavior is measured against the target project (Rigor) and adjusted from there.
