# Agent-driven install and setup via hosted guide + gem-shipped skills

Binpacker's setup and tuning are delivered as agent-driven workflows rather than as interactive CLI wizards. A hosted `docs/install.md` is pasted to an AI agent, which installs the gem and then hands off to skills shipped inside the gem. The skills are surfaced through a `binpacker skill` CLI, and the agent — not the user — decides which one to run based on detected project state.

## Context

- The setup story mirrors the sibling project Rigor (same author): a hosted install guide the user gives to their coding agent, which drives the whole flow end to end. The direct UX inspiration is `oh-my-openagent` — agent-assisted setup to eliminate configuration mistakes.
- Binpacker's core (`run`, `calibrate`, scheduling) stays free of any AI-agent dependency — see the "CI cycle" glossary entry ("No AI agent involvement during the run itself"). The agent workflows live strictly outside the hot path.
- These workflows are used far less frequently than Rigor's (a project is set up once and re-tuned occasionally), so making the user choose the right skill is poor UX.

## Decision

1. **Hosted entry point.** `docs/install.md` is the single thing a user hands to their agent. It covers environment/runtime detection, `gem install binpacker`, a `binpacker --version` check, then delegates to `binpacker describe`.
2. **Gem-shipped skills.** User-facing skills live in a top-level `skills/` directory (`skills/binpacker-setup/`, `skills/binpacker-improve/`) and are packaged in the gem. The repo's own maintenance skills stay in `.agents/skills/` (e.g. `binpacker-release-prep`) and are not shipped.
3. **CLI surface, mirroring Rigor.** `binpacker skill` lists bundled skills; `binpacker skill <name>` prints the `SKILL.md` body for the agent to follow; `binpacker skill --path <name>` prints its absolute path; `binpacker skill --describe` (alias `binpacker describe`) reports project state and recommends the next skill. Printing the body keeps the flow harness-independent — any agent can consume it without a Claude-Code-specific file layout.
4. **Agent-driven routing.** `binpacker describe` inspects state (config present? timing data present and fresh? framework detected? CI wired? cache-miss pattern?) and recommends `binpacker-setup` (unconfigured) or `binpacker-improve` (configured). The user never picks a skill; each skill re-confirms state on entry and asks the user interactively at decision points.

## Considered Options

- **Bundle skills in the gem `.agents/skills/` only** — rejected: that directory is for the repo's internal maintenance skills, and mixing user-facing shipped skills there blurs the boundary.
- **`binpacker setup` / `binpacker improve` CLI subcommands that call Claude** — rejected: pulls an AI dependency into the core CLI, contradicting the AI-free CI cycle.
- **A separate plugin package** — rejected: extra distribution surface with no benefit over shipping inside the gem the user already installs.
- **One combined skill** — rejected in favour of two, because bootstrap (one-time) and tune (recurring) have genuinely different triggers and instructions; routing between them is automatic via `describe`.

## Consequences

- The gemspec must include `skills/` in its packaged files.
- The run-report and persistence decisions (ADR-0004, ADR-0005) exist to give `binpacker-improve` durable, comparable data to reason over.
- `binpacker describe` becomes the stable contract between `install.md` and the skills; its state-detection output can grow without changing the install guide.
