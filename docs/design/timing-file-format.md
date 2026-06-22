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
- **Write behavior**: Append-only. New runs append entries rather than overwriting. Older entries for the same `(file, name)` key are superseded by the latest entry.
- **Read behavior**: Scan entire file, keeping the last entry per `(file, name)` as the authoritative Weight.
- **No initial weights**: When no Timing file exists (or a Test has no entries), the Test receives a default Weight of 1.0.

## Rationale

JSON Lines was chosen over JSON, YAML, and CSV because:
- **Appendable**: CI caches can accumulate runs without rewriting the entire file.
- **Streamable**: A reader processes one line at a time; no need to parse the whole file.
- **Merge-friendly**: Concatenating `binpacker.timings` from multiple shards is trivial (`cat`).
- **Machine-readable by AI agents**: Each line is self-contained JSON — agents consume and produce it naturally.
