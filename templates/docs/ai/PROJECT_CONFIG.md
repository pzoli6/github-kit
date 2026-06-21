# PROJECT_CONFIG.md — Repository-Specific Configuration

> **This file is repo-specific.** `github-kit`'s installer creates it only if it doesn't already
> exist, and `update-github-kit.sh` never overwrites it (unless you explicitly pass
> `--force-config`). Fill in the values below for *this* repository — they are read by agents
> (per `AGENTS.md` / `docs/ai/AGENT_WORKFLOW.md`) and by the local helper scripts in
> `scripts/project/`.

| Key | Value |
|---|---|
| Project name | TBD |
| Repository | `owner/repo` |
| GitHub Project name | TBD |
| GitHub Project owner | TBD |
| GitHub Project number | TBD |
| Base branch | `develop` |
| Production branch | `main` |
| Agent branch prefix | `agent/` |
| Default PR mode | draft |

## Validation commands

List the exact commands an agent must run before opening a PR. Keep this list accurate — agents
report `Validation: Passed` based on what's listed here actually succeeding.

```bash
# example — replace with this repo's real commands
# npm run build
# npm run lint
# npm test
```

## Forbidden files

Files or paths agents must never create, edit, or delete in this repo (e.g. generated artifacts,
vendored code, secrets):

```text
# example
# .env
# *.pem
```

## Repository-specific rules

Add anything specific to this repo that isn't already covered by the universal `AGENTS.md` —
deployment quirks, additional review requirements, naming conventions, etc.

```text
TBD
```
