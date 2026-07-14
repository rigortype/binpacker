# Stealer Policy

See [ADR-0006](../adr/0006-weight-guided-batch-stealing.md) for the decision behind this policy, and [ADR-0002](../adr/0002-parent-managed-work-stealing.md) for the parent-managed IPC structure it runs on.

Dynamic scheduling (`scheduler.steal_enabled`) dispatches work to Workers in batches rather than one Test at a time. A batch is one test-runner invocation, so batch sizing trades boot cost against balance. The current policy is weight-guided: batch size is derived from predicted Weight, and so is the choice of donor queue.

## Default behavior

| Axis | Policy | Rationale |
|------|--------|-----------|
| Batch amount | Drain half the queue's remaining predicted Weight, floored at a per-run minimum, always at least one Test | Every batch is a fresh test-runner process. Early batches are large, so the boot cost is amortized over minutes of work; tail batches shrink toward the floor, keeping granularity where balance is actually decided. A fixed count cannot do both: ten head-of-queue Tests can be minutes of work, ten tail Tests under a second. |
| Trigger | Worker's own queue empty | Simplest; no predictive overhead. The Worker asks for more only when it has nothing left. |
| Donor selection | Non-empty queue with the most remaining predicted time (`WorkerQueue#total_weight`) | Count is a poor proxy for remaining work — a queue of 50 fast Tests may hold less work than a queue of 3 slow ones. Weight-based selection targets the queue that is actually going to finish last. |

The batch floor itself depends on whether the project is calibrated. On a calibrated run, Weights are measured seconds (or a KB-fallback scaled into seconds via a coefficient estimated from the measured files — see [timing-file-format.md](timing-file-format.md)), so the floor is the fixed `MIN_BATCH_WEIGHT` (30s of predicted work). On a pure cold start — no measurements at all, so no coefficient can be estimated — Weights are raw filesize KB, and a fixed 30 has no seconds meaning against them. The floor there is scale-free instead: total predicted Weight divided by `worker_count * COLD_START_BATCHES_PER_WORKER`, targeting ~5 batches per Worker regardless of the project's size, with a fallback to `MIN_BATCH_WEIGHT` if there's nothing to divide (zero total Weight or zero Workers).

A Monte Carlo simulation (200+ trials per config, 312 files / 4 Workers / 3s boot / execution-noise CV 0.13, filesize as a noisy duration predictor) validated this split. At the simulated project's scale (~900 KB of spec files) the old fixed-30 floor and the new scale-free floor were statistically indistinguishable — 30-as-KB happened to land near `total / 20`. The old floor's real failure mode showed up on small codebases: at ~57 KB total, a floor of 30 KB exceeded a Worker's entire queue, collapsing dynamic mode into one boot per Worker — batching and stealing effectively disabled — at 9.2% max deviation, versus ~2.7 boots/Worker and 7.4% deviation for the scale-free floor at the same scale. `COLD_START_BATCHES_PER_WORKER` itself proved insensitive: sweeping 3→8 moved boots/Worker only ~2.6→2.8, since the halving drain rule reaches the floor in roughly `log2` steps regardless; 5 was kept as a reasonable default rather than over-tuned.

Stolen Tests move between the donor's and the receiver's progress totals, so the `done/total` display stays consistent with what each Worker actually runs.

## Measurements

Simulated against Rigor's real per-file weights (312 files, 4 Workers, measured run-to-run CV 0.13, 3s runner boot cost):

- Max deviation from the mean Worker runtime: **8.6% → ~2%** versus a static LPT partition.
- Runner boots: **~5 per Worker**, versus 8 under fixed-10-file batching.
- Best makespan among the batching and donor-selection policies tried.

## Tuning axis (future)

Nothing here is configurable yet; the policy above is the hard-coded default. Candidates, should evidence warrant them:

- **`steal_threshold: N`** — Proactively steal before a Worker's queue empties, hiding the IPC round-trip behind the tail of the current batch.
- **`min_batch_weight: SECONDS`** — Expose `MIN_BATCH_WEIGHT` for suites whose runner boot cost is far from the ~3s this default assumes. Now specifically a calibrated-run concern: cold starts derive their own scale-free floor and don't read this constant.
- **`batch_divisor: N`** — Drain 1/N of the remaining Weight instead of half, trading boot count against balance.
