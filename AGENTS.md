## rigor CLI

`rigor` (`rigortype` gem) is installed as a standalone gem — **never** invoke it via `bundle exec rigor`.
Run it directly as `rigor <command>` (e.g. `rigor sig-gen --write lib`).

## Agent skills

### Issue tracker

Issues are tracked as local markdown files under `.scratch/<feature>/` in this repo. See `docs/agents/issue-tracker.md`.

### Triage labels

Labels use the engineering skills default vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout — one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
