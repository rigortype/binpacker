# Scheduling Algorithm

## Built-in algorithms

| Algorithm | Description | Status |
|-----------|-------------|--------|
| `lpt` | Longest Processing Time first. Sort Tests descending by Weight, then repeatedly assign each Test to the Worker with the smallest current load. | Implemented |
| `multifit` | LPT-based initial partition plus a binary-search optimization pass over candidate makespans. | Implemented (default) |

## Selection

```yaml
# binpacker.yml
profiles:
  default:
    scheduler:
      strategy: static
      algorithm: multifit
```

## Extensibility

Binpacker does not provide a plugin load path. The algorithm list is hard-coded.

*Gentle escape hatch*: A custom initializer script specified in `binpacker.yml` (`init: path/to/script.rb`) is loaded at startup. If the script defines a class that matches the `Scheduler` interface and registers it via `Binpacker.register_scheduler(name, klass)`, the user can use it in `algorithm: <name>`. This is a deliberate gap — documented but not actively developed.

## Interface

```ruby
class LptScheduler < Binpacker::Scheduler
  # Returns an array of WorkerQueues, one per Worker.
  # Each WorkerQueue holds Tests in the order the Worker should execute them.
  def partition(tests: Array[Test], worker_count: Integer, timings: Hash[(String, String) -> Float])
    # ...
  end
end
```
