# Installing binpacker (for AI coding agents)

You are an AI coding agent setting up **binpacker** in this project. binpacker reduces CI test-suite makespan by scheduling tests across worker processes. Follow these phases in order. Report any command failure to the user instead of guessing; stop and ask when a step is ambiguous.

At the end you will hand off to a binpacker skill, which drives the actual project setup interactively.

## Phase 1 — Detect the environment

Determine how Ruby and gems are managed in this project. Check, in order:

1. **Version manager** — is `mise` or `asdf` present (`mise --version`, `asdf --version`)? Is there a `mise.toml` / `.tool-versions`?
2. **Ruby** — `ruby --version`. binpacker requires Ruby >= 3.2.
3. **Bundler project** — is there a `Gemfile`? If so, binpacker should be added to it rather than installed globally.

Pick the pathway that matches what you found.

## Phase 2 — Install binpacker

**Bundler project (has a `Gemfile`):**

```sh
bundle add binpacker --group development
```

If binpacker should be available in CI's default group, adjust the group accordingly.

**No Gemfile (global install):**

```sh
gem install binpacker
```

**Via mise (managing the Ruby and the gem):** ensure a supported Ruby is installed and activated, then use the appropriate `bundle add` or `gem install` above.

If Ruby is older than 3.2, install a newer Ruby (via the detected version manager) before continuing.

## Phase 3 — Verify

```sh
binpacker --version
```

(In a Bundler project, use `bundle exec binpacker --version`.) Confirm it prints a version. If the executable isn't found, re-check the install pathway with the user.

## Phase 4 — Analyze the project and hand off

Ask binpacker what to do next:

```sh
binpacker describe
```

This reports the project's state (config present? timing data? test framework? CI wired?) and recommends the next skill — `binpacker-setup` for an unconfigured project, or `binpacker-improve` for one that is already running in CI.

Load that skill's instructions and follow them:

```sh
binpacker skill <recommended-skill>
```

`binpacker skill <name>` prints the skill's full instructions to stdout — read them and carry out the workflow, asking the user at each decision point. Do not commit or open a PR without explicit confirmation.

## Summary

1. Detect version manager / Ruby / Gemfile.
2. Install binpacker (`bundle add` or `gem install`).
3. `binpacker --version` to verify.
4. `binpacker describe`, then `binpacker skill <recommended-skill>` and follow it.
