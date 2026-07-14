# Timing File Format

Timing data is stored as JSON Lines (`.jsonl`), a line-delimited JSON format that supports append-only writes and easy concatenation.

## Schema

```json
{"file":"path/to/test_file.rb","name":"test description","time":0.034}
```

| Field | Type | Description |
|-------|------|-------------|
| `file` | string | Test file path, relative to project root |
| `name` | string | Test name as reported by the test runner (e.g., RSpec description, Minitest method name) |
| `time` | float | Measured wall-clock duration in seconds |

## Conventions

- **File name**: `binpacker.timings` (or as configured in `binpacker.yml`)
- **Location**: Project root (alongside `binpacker.yml`)
- **Encoding**: UTF-8, LF line endings
- **Write behavior**: Append-only during a Run. New runs append entries rather than overwriting, so a `(file, name)` key accumulates one sample per Run.
- **Compaction**: After appending a Run's results, the file is rewritten in place keeping only the most recent `MAX_SAMPLES_PER_TEST` (3) samples per `(file, name)`. Without this the history — and any CI cache built from it — would grow by one full run per invocation. Compaction preserves append order, so "recent" means "most recently written".
- **Read behavior**: A Test's Weight is the **median of its last 3 samples**; a file's Weight is the sum of its Tests' medians. The history must not be summed wholesale: a file present in N historical runs would weigh ~N× its true cost, starving newly added files in the partition. The median (over an odd, small window) also keeps a single anomalous run — a GC pause, a noisy CI neighbour — from moving the Weight.
- **No initial weights**: When a Test has no samples, its Weight falls back to file size, in one of two regimes depending on whether the project has any measurements at all. If at least one Test elsewhere has a measured sample, a seconds-per-KB coefficient is estimated from the median `measured_seconds / size_kb` ratio across measured files that still exist on disk, and the unmeasured Test's file size is scaled through it (floored at `0.01`, since sub-second predictions are meaningful once the unit is seconds). If there are no measurements to estimate a coefficient from — a pure cold start — the fallback is the file's raw size in KB (floored at `1.0`). Either way, a file that cannot be read falls back to `1.0`. File size is a crude but non-degenerate proxy for cost, and it is strictly better than giving every unmeasured Test the same Weight.
- **Path normalization**: Paths are compared after `Pathname#cleanpath` and stripping a leading `./`, so `./spec/foo_spec.rb` and `spec/foo_spec.rb` are the same key.

## Rationale

JSON Lines was chosen over JSON, YAML, and CSV because:
- **Appendable**: A Run records its results with a plain append; the periodic compaction that bounds the history is a separate, whole-file rewrite.
- **Streamable**: A reader processes one line at a time; no need to parse the whole file.
- **Merge-friendly**: Concatenating `binpacker.timings` from multiple shards is trivial (`cat`).
- **Machine-readable by AI agents**: Each line is self-contained JSON — agents consume and produce it naturally.
