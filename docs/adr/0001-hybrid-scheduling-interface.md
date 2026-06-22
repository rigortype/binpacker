# Hybrid scheduling interface: static partition with work-stealing

Binpacker needs an interface that supports both static (ahead-of-time) and dynamic (work-stealing) scheduling. We chose a two-layer design: a static partition maps tests to worker queues, and an optional `steal` operation lets an idle worker take the next test from another queue.

## Considered Options

### A — Pull-based (single `next(worker_id)`)

The scheduler exposes a single `next(worker_id) -> Test | nil` method. A static scheduler pre-loads its partition and returns `nil` when exhausted; a dynamic scheduler pops from a shared queue.

Rejected because the static case loses the ability to inspect or display the full partition before execution — any tooling that wants to show "worker 2 will run these 5 tests" would need a separate preview API.

### B — Push-based (single `assign(tests, worker_count)`)

Returns `Array<Array<Test>>`. Simple but inherently static — there is no natural extension to dynamic scheduling without introducing a second interface.

Rejected because it precludes the dynamic scheduling path entirely, and the user's stated goal is to keep dynamic scheduling as a viable future option.

### C — Hybrid partition + steal (selected)

Two methods:

```ruby
scheduler.partition(tests, worker_count) -> Array<WorkerQueue>
worker_queue.pop  -> Test | nil   # static: consumer drains its own queue
```

and optionally:

```ruby
scheduler.steal(worker_id) -> Test | nil   # dynamic: takes from non-empty queues
```

A static scheduler implements only `partition` and the consumer drains its queue. A work-stealing scheduler implements `steal` by probing peer queues. Both share the same `WorkerQueue` data structure.

## Consequences

- A common `WorkerQueue` type (backed by an array, a thread-safe queue, or a file) must be defined up front so both scheduling strategies share the same shape.
- The `steal` operation introduces a policy decision — which peer queue to steal from, and how many tests to transfer. This can be deferred.
- Partition-aware tooling (progress bars, ETA) can work from the initial partition alone, without knowing whether stealing is enabled.
- The interface is a superset of both approaches — a scheduler that implements `partition` + `steal` also works as a pure static scheduler by simply not calling `steal`.
