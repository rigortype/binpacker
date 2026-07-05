# Agent-Driven Workflows

Binpacker's setup and tuning are delivered as agent-driven workflows, not interactive CLI wizards. The core (`run`, `calibrate`, scheduling) stays free of any AI dependency; the workflows sit strictly outside the hot path. See [ADR-0003](../adr/0003-agent-driven-install-and-skills.md).

## Entry point

A hosted `docs/install.md` is the single thing a user hands to their coding agent. The agent:

1. Detects runtime/tooling and installs the gem (`gem install binpacker`).
2. Verifies with `binpacker --version`.
3. Runs `binpacker describe` and follows its recommendation.

The user never chooses which skill to run — the agent routes based on detected state, and each skill re-confirms state on entry and asks the user interactively at decision points.

## CLI surface

Mirrors Rigor's `rigor skill` for a familiar vocabulary:

| Command | Purpose |
|---------|---------|
| `binpacker skill` | List bundled skills. |
| `binpacker skill <name>` | Print the `SKILL.md` body for the agent to follow. |
| `binpacker skill --path <name>` | Print the absolute path of the skill's `SKILL.md`. |
| `binpacker skill --describe` (alias `binpacker describe`) | Report project state and recommend the next skill. |

Printing the skill body (rather than relying on a file layout) keeps the flow harness-independent — any agent can consume it.

### `binpacker describe` — state detection

Reports and routes on:

- **binpacker.yml present?** absent → recommend `binpacker-setup`.
- **Timing data present and fresh?** missing/stale → recommend calibration.
- **Test framework** detected (rspec / minitest).
- **CI wired?** whether a workflow runs `binpacker run`.
- **Cache-miss pattern?** frequent misses → recommend committing a baseline (see ADR-0005).

Configured and healthy → recommend `binpacker-improve`.

## Skills

Shipped user-facing skills live in the gem's top-level `skills/` directory. (The repo's own maintenance skills stay in `.agents/skills/` and are not shipped.)

### `binpacker-setup` — one-time bootstrap

1. **Detect** — framework and worker count (reuses `binpacker init` detection).
2. **Config** — `binpacker init` writes `binpacker.yml` (default + ci profiles); the skill reviews and adjusts.
3. **Calibrate** — `binpacker calibrate` (or `--incremental` if partial timing data exists).
4. **Validate** — a local `binpacker run`; confirm green and check balance.
5. **CI wiring** — scaffold a workflow that installs binpacker, restores/saves the timing cache, runs `binpacker run`, and uploads the run report artifact. Bundled here, not a separate skill.
6. **Handoff** — commit on a branch and open a PR via `gh`, always with explicit user confirmation.

### `binpacker-improve` — recurring, propose-only tuning

1. Fetch recent CI run reports (`gh run list` → `gh run download` of the report artifact).
2. Analyse predicted-vs-actual trends: persistent per-Worker skew, recurring high-drift files, cache-miss frequency.
3. Propose `binpacker.yml` changes — `worker_count`, `algorithm` (`lpt` ↔ `multifit`), `steal_enabled` — and recommend `binpacker calibrate --incremental` or committing a baseline when warranted.
4. Present changes as a diff and confirm. It never auto-applies or auto-commits.

## Timing persistence

Two layers (see [ADR-0005](../adr/0005-two-tier-timing-persistence.md)):

- **Runtime — `actions/cache`** (default, automatic): restored and saved each CI run.
- **Durable — committed `binpacker.timings` baseline** (recommended interactively by `binpacker-improve`): a cold-start floor and a PR-reviewable record, added only when the user accepts the recommendation.

Precedence: restore cache → fall back to committed baseline on miss → append actuals and save cache after the Run.
