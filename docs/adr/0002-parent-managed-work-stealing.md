# Parent-managed work-stealing via IPC pipes

The scheduler (parent process) holds all WorkerQueues and responds to Worker pull requests. When a Worker's queue is empty, the parent rebalances by taking a Test from the most-loaded peer queue — implementing work-stealing without the Worker processes needing to coordinate peer-to-peer.

## Context

- Workers are spawned as subprocesses (Spawn), so they cannot share in-memory objects.
- The scheduling interface (ADR-0001) supports both static partition and dynamic `steal`.
- Static scheduling is the initial implementation target, but the infrastructure must not preclude dynamic scheduling.

## Decision

1. The parent process owns the `Array<WorkerQueue>` and a `partition` of Tests per Worker.
2. Each Worker communicates with the parent over an `IO.pipe`: it sends a pull request and waits for the next Test (or `nil`).
3. The parent's `next_test(worker_id)` first drains `partition[worker_id]`. When empty, it steals from the most-loaded non-empty queue.
4. Workers are unaware whether the Test they receive came from their own queue or was stolen.

## Considered Options

### File-based queues (C)

Each Worker reads/writes a queue file on disk. Steal moves entries between files. Rejected because IPC pipes are simpler for the expected test count (~hundreds to low thousands) and avoid file-locking complexity.

### Peer-to-peer IPC

Workers communicate directly with each other. Rejected because it requires each Worker to know about peers and handle connection setup, adding complexity with no clear benefit over parent-managed routing.

### DRb

Ruby's built-in distributed object system. Rejected as overkill for a single-machine process tree.

## Consequences

- The parent process is the single point of coordination — if it stalls, all Workers stall. For a test suite of hundreds to low thousands of tests with single-digit Worker counts, this is not a meaningful bottleneck.
- Adding a new scheduling strategy (e.g., dynamic `steal` with configurable batch size) is localized to the parent's `next_test` method.
- The pipe protocol can start minimal (a single line per request) and grow versioned headers if richer communication is needed later.
- Test logging from Workers must be routed separately (stderr, files) since the pipe is reserved for scheduling commands.
