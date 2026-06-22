# `binpacker.yml` Schema

Single config file at project root. Select active profile via `--profile <name>` (CLI), `BINPACKER_PROFILE` (env), or CI auto-detection — falling back to `default`.

## Top-level keys

```yaml
profiles:  # required
  <name>:
    extends: <parent_profile>    # optional; inherits all keys from parent, overrides below
    test_runner: rspec | minitest
    workers: auto | <integer>
    timing_file: <path>          # e.g. binpacker.timings
    test_pattern: <glob>         # e.g. "spec/**/*_spec.rb"
    test_exclude: <array>        # e.g. ["spec/system/**"]
    scheduler:
      strategy: static | dynamic | auto
      steal_enabled: boolean
```

## Profile selection

| Priority | Mechanism | Example |
|----------|-----------|---------|
| 1 | CLI flag | `binpacker run --profile ci` |
| 2 | Environment variable | `BINPACKER_PROFILE=ci binpacker run` |
| 3 | Auto-detection | CI env vars present → `ci` profile |
| 4 | Default | `default` profile |

## Inheritance

`extends: default` merges the parent's keys, then overrides with the child's. Nested keys (`scheduler`) are merged shallowly — a child `scheduler:` block replaces the parent's `scheduler:` block entirely.

## Test runner arguments

Passed through via `--` on the CLI:
```
binpacker run --profile ci -- --tag ~slow
```
Everything after `--` is forwarded verbatim to the test runner command. No `runner_options` in the config file.

## Built-in adapters

`test_runner: rspec` and `test_runner: minitest` are built-in adapters. Binpacker selects the correct test parser, test discovery strategy, and runner invocation for each. Free-form commands are not supported initially.

## Defaults

When no `binpacker.yml` exists, running `binpacker run` prints a guide to run `binpacker --init` or the AI-agent-driven `/binpacker-setup` workflow.
