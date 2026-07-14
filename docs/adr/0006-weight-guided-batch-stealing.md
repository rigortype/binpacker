# Weight-guided batch stealing

Under dynamic scheduling, work is dispatched to Workers in Batches sized by predicted Weight — each Batch drains half of a queue's remaining predicted Weight, floored at `MIN_BATCH_WEIGHT` (30s) — and an idle Worker steals from the queue with the most remaining predicted *time* rather than the most Tests. Supersedes ADR-0002's per-Test, count-based steal policy; the parent-managed IPC structure that ADR decided is unchanged.

## Context

- ADR-0002 chose parent-managed stealing and predicted that "adding a new scheduling strategy is localized to the parent's `next_test`". That prediction held: this change is confined to the parent's dispatch loop.
- Its v1 policy was deliberately Weight-free — one Test per steal, donor chosen by queue length — because no Timing file was assumed. Timings are now the normal case, so the reasons for that simplification are gone.
- The shipped implementation had drifted to a fixed 10-Test Batch, which is wrong at both ends of an LPT-ordered queue: ten head Tests can be minutes of work (coarse, poor balance), ten tail Tests under a second (a wasted test-runner boot, since every Batch is a fresh process).
- Donor-by-count is a poor proxy for remaining work: a queue of 50 fast Tests may hold less work than a queue of 3 slow ones, so the steal can fail to target the Worker that will actually finish last.

## Decision

1. **Batch size is weight-guided.** `drain_batch` pops Tests until the accumulated predicted Weight reaches `max(remaining_weight / 2, MIN_BATCH_WEIGHT)`, always taking at least one Test. Early Batches are large (boot cost amortized), tail Batches converge on the floor (fine granularity where balance is decided).
2. **`MIN_BATCH_WEIGHT` is 30s**, roughly an order of magnitude above the ~3s test-runner boot observed on the target project — enough that boot overhead stays in the noise.
3. **Donor selection is by remaining predicted time** (`WorkerQueue#total_weight`), not Test count.
4. **Stolen Tests move between progress totals**, so each Worker's `done/total` display reflects what it actually runs.
5. Neither constant is configurable yet. The policy is measured against the target project first; see `docs/design/stealer-policy.md`.

## Considered Options

- **Keep the fixed-count Batch, tune the count** — rejected: no single count is right for both ends of the queue. The failure is structural, not a bad constant.
- **One Test per steal (ADR-0002's original policy)** — rejected: optimal for balance, but pays a full runner boot per Test. Untenable once boot cost is measured rather than assumed negligible.
- **Drain the whole remaining queue on steal** — rejected: one greedy steal recreates the imbalance the steal was meant to fix.
- **Divisor other than 2** — considered; halving gave the best makespan among the divisors simulated, and no evidence yet justifies a knob.

## Consequences

- Batch sizing now depends on Weight quality, which couples dynamic scheduling to the Timing file more tightly than ADR-0002 assumed. On a cold start Weights fall back to file size in KB, which is crude — the policy degrades toward arbitrary batching rather than breaking, but a calibrated project gets meaningfully better balance.
- Simulated on the target project's real per-file Weights (312 files, 4 Workers, run-to-run CV 0.13, 3s boot): max deviation 8.6% → ~2% versus static LPT, at ~5 runner boots per Worker versus 8 under fixed-10 batching.
- `MIN_BATCH_WEIGHT` encodes an assumption about runner boot cost. A project whose boot is far from ~3s will want it exposed; that is the first knob to add if evidence appears.

## Amendment (2026-07-15)

The cold-start coupling flagged above in Consequences was resolved: `Timing#load_with_fallback` now estimates a seconds-per-KB coefficient from measured files and scales unmeasured files' filesize weight through it, so mixed measured/unmeasured suites compare Weights in one unit; on a pure cold start (no measurements to estimate a coefficient from), `Orchestrator` derives a scale-free batch floor targeting `COLD_START_BATCHES_PER_WORKER` (5) batches per Worker instead of reading `MIN_BATCH_WEIGHT` as seconds. A Monte Carlo simulation motivated the scale-free floor by surfacing its actual failure mode: not wastefully tiny batches, but the reverse — on small codebases (~57 KB total) the old fixed-30 floor exceeded a Worker's whole queue, collapsing dynamic mode into one boot per Worker and effectively disabling batching and stealing. `MIN_BATCH_WEIGHT`'s boot-cost assumption (Consequences, above) now only concerns calibrated runs; cold starts no longer read it.
