# Stealer Policy

See [ADR-0006](../adr/0006-weight-guided-batch-stealing.md) for the decision behind this policy, and [ADR-0002](../adr/0002-parent-managed-work-stealing.md) for the parent-managed IPC structure it runs on.

Dynamic scheduling (`scheduler.steal_enabled`) dispatches work to Workers in batches rather than one Test at a time. A batch is one test-runner invocation, so batch sizing trades boot cost against balance. The current policy is weight-guided: batch size is derived from predicted Weight, and so is the choice of donor queue.

## Default behavior

| Axis | Policy | Rationale |
|------|--------|-----------|
| Batch amount | Drain half the queue's remaining predicted Weight, floored at `MIN_BATCH_WEIGHT` (30s of predicted work), always at least one Test | Every batch is a fresh test-runner process. Early batches are large, so the boot cost is amortized over minutes of work; tail batches shrink toward the floor, keeping granularity where balance is actually decided. A fixed count cannot do both: ten head-of-queue Tests can be minutes of work, ten tail Tests under a second. |
| Trigger | Worker's own queue empty | Simplest; no predictive overhead. The Worker asks for more only when it has nothing left. |
| Donor selection | Non-empty queue with the most remaining predicted time (`WorkerQueue#total_weight`) | Count is a poor proxy for remaining work — a queue of 50 fast Tests may hold less work than a queue of 3 slow ones. Weight-based selection targets the queue that is actually going to finish last. |

Weights come from the Timing file (measured seconds), falling back to file size in KB on a cold start — see [timing-file-format.md](timing-file-format.md).

Stolen Tests move between the donor's and the receiver's progress totals, so the `done/total` display stays consistent with what each Worker actually runs.

## Measurements

Simulated against Rigor's real per-file weights (312 files, 4 Workers, measured run-to-run CV 0.13, 3s runner boot cost):

- Max deviation from the mean Worker runtime: **8.6% → ~2%** versus a static LPT partition.
- Runner boots: **~5 per Worker**, versus 8 under fixed-10-file batching.
- Best makespan among the batching and donor-selection policies tried.

## Tuning axis (future)

Nothing here is configurable yet; the policy above is the hard-coded default. Candidates, should evidence warrant them:

- **`steal_threshold: N`** — Proactively steal before a Worker's queue empties, hiding the IPC round-trip behind the tail of the current batch.
- **`min_batch_weight: SECONDS`** — Expose `MIN_BATCH_WEIGHT` for suites whose runner boot cost is far from the ~3s this default assumes.
- **`batch_divisor: N`** — Drain 1/N of the remaining Weight instead of half, trading boot count against balance.
