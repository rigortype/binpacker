---
name: binpacker-setup
description: Bring a project from zero to a working parallel test run with binpacker — detect the framework, generate config, calibrate timing data, validate a parallel run, and wire CI. Use when binpacker is installed but not yet set up (no binpacker.yml, or no timing data), or when the user asks to set up / configure / adopt binpacker.
---

# Binpacker Setup

A one-time workflow that takes a project from zero to a working parallel test run. Run `binpacker describe` first — if it recommends `binpacker-improve`, the project is already set up and you want that skill instead.

Assess state as you go and **ask the user at each decision point** rather than assuming. Do not run destructive or outward-facing steps (committing, opening a PR) without explicit confirmation.

## 1. Detect

- Confirm binpacker is installed: `binpacker --version`.
- Run `binpacker describe` to read current state (config present? timing data? framework? CI wired?).
- Determine the test framework (rspec / minitest) and the test glob. If `binpacker describe` reports one, trust it; otherwise inspect the repo.

## 2. Config

If `binpacker.yml` is absent, create it with `binpacker init` (it auto-detects the framework and writes `default` + `ci` profiles). Then review the generated file with the user and adjust:

- `workers` — `auto` locally; a fixed number (e.g. `4`) for the `ci` profile matching the CI runner.
- `test_pattern` / `test_exclude` — match the project's real layout.
- `scheduler.algorithm` — `multifit` (default) unless there's a reason to use `lpt`.
- `scheduler.steal_enabled` — `true` to let idle workers steal at runtime.
- `report_file` (on the `ci` profile) — e.g. `binpacker-report.json`, so CI always emits a run report.

## 3. Calibrate

Seed timing data so the scheduler has real Weights:

```sh
binpacker calibrate
```

If some timing data already exists, measure only the gaps:

```sh
binpacker calibrate --incremental
```

## 4. Validate

Run the suite in parallel and confirm it is green and balanced:

```sh
binpacker run
```

Check the summary's `Balance: max deviation`. A large deviation on the first run is expected before timing data accumulates; note it and move on.

## 5. Wire CI

Add (or extend) a CI workflow so the suite runs under binpacker. The workflow should:

- Install binpacker (via the project's dependency manager or `gem install binpacker`).
- Restore and save `binpacker.timings` with `actions/cache` (key includes OS + a hash of the test files). This is the runtime timing layer.
- Run `binpacker run --profile ci` (which emits the run report via `report_file`).
- Upload the run report with `actions/upload-artifact` so `binpacker-improve` can read it later.

Propose the workflow YAML and let the user review it before writing.

## 6. Handoff

Only after the user confirms:

- Create a branch, commit `binpacker.yml`, the CI workflow, and (if the user wants a committed baseline) `binpacker.timings`.
- Open a PR with `gh`, summarising what was set up.
- After CI runs, point the user at `binpacker-improve` to tune from real CI data.

## Done when

- `binpacker run` passes locally across workers.
- `binpacker.yml` reflects the project's framework, layout, and CI worker count.
- CI runs `binpacker run` and uploads a run report.
- The user has confirmed any commit / PR.
