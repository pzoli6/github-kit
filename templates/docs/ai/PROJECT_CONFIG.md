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
| github-kit installed | `true` |
| github-kit ref | `main` |
| github-kit update mode | `main-channel` |
| Project Sync enabled | `false` |
| Project field completeness gate enabled | `false` |
| Branch protection enforced | `false` |

This repository follows `pzoli6/github-kit@main` for central reusable workflows. Local agent files
(`AGENTS.md`, `CLAUDE.md`, skills, Cursor rules, this file) are lightweight bootstraps and fallback
instructions — most central workflow updates are picked up automatically by this repo's next
workflow run from `github-kit/main`. Local slash-command/skill updates require explicitly running
`/github_kit_update` or `update-github-kit.sh`/`.ps1` — they do not happen on their own.

`github-kit ref` is `main` by default (the always-latest channel) — change it only if this repo has
deliberately pinned to a specific tag/branch/sha via `--ref`/`-Ref` on the installer/updater (the
legacy `--workflow-ref`/`-WorkflowRef` flag names still work as aliases). If pinned, `github-kit
update mode` should read `pinned` instead of `main-channel` so agents don't assume auto-updates are
happening. `Project Sync enabled` is `false` until you've installed
`.github/workflows/project-sync.yml` (`--include-project-sync`) and configured a real GitHub
Project + `AGENT_PROJECT_TOKEN` secret — see "When Project Sync isn't enabled" in
`AGENT_WORKFLOW.md`. `Branch protection enforced` is `false` for any private repo on the GitHub
Free plan (a platform limitation, not a config you can flip) — see "Free-tier limitations" in
`AGENT_WORKFLOW.md`.

## GitHub metadata defaults

Defaults that `scripts/project/create_agent_issue.sh` and `scripts/project/create_agent_pr.sh`
apply automatically, so issue/PR sidebar metadata (assignee, labels, milestone) is never left
blank. Configure the real values in `docs/ai/PROJECT_CONFIG.env` (copy from `.env.example`) — this
table documents what's expected, it isn't read directly by scripts.

| Key | Value |
|---|---|
| Default issue assignee | `@me` |
| Default PR assignee | `@me` |
| Default reviewer | TBD |
| Default issue labels | `status:ready-for-agent,type:agent-task` |
| Default PR labels | `type:agent-task` |
| Default milestone | TBD |

`Default reviewer` and `Default milestone` are `TBD` until this repo configures them — leave the
matching env var blank rather than guessing a real username or milestone title.
`create_agent_issue.sh`/`create_agent_pr.sh` skip a flag entirely when its value is empty or `TBD`;
they never fabricate one. If `Default milestone` is set but that milestone doesn't exist yet in
this repo's GitHub Issues, the scripts stop and ask rather than silently creating or skipping it.

## Project field defaults

Defaults for the GitHub Project custom fields (`Agent`, `Area`, `Risk`, `Environment` — see
`AGENTS.md` → "Project fields") that `create_agent_issue.sh` and `create_agent_pr.sh` write
automatically at issue-creation and PR-open time, so these fields are never left blank on the
board. Configure in `docs/ai/PROJECT_CONFIG.env`:

| Key | Value |
|---|---|
| Default agent | TBD |
| Default area | TBD |
| Default risk | TBD |
| Default environment | TBD |

These are a fallback, not the primary source: every agent invoking `create_agent_issue.sh` /
`create_agent_pr.sh` knows its own identity and the area/risk/environment of the task it's
working on, and should pass `--agent`, `--area`, `--risk`, `--environment` explicitly per
`docs/ai/AGENT_WORKFLOW.md` rather than relying on a repo-wide default. The env default only
covers the case where a flag is omitted — e.g. a repo that's effectively single-agent, or a manual
script invocation. Like the metadata above, a value left at `TBD` (or blank) means the script
skips that field rather than writing a placeholder into the Project.

## Project field completeness gate (CI)

An opt-in PR check, separate from Project Sync, that fails the PR if its Project item is missing
any of the fields agents are supposed to fill in (`Agent`, `Area`, `Risk`, `Environment`, `Base
Branch`, `Branch`, `PR URL` by default) — the check this kit added after agents were observed
opening PRs with those fields blank. It lives in `reusable-pr-policy.yml`'s `project-fields` job and
is off by default; enable it in `.github/workflows/pr-policy.yml`:

```yaml
jobs:
  policy:
    uses: pzoli6/github-kit/.github/workflows/reusable-pr-policy.yml@main
    with:
      required_base_branch: develop
      require_agent_branch_prefix: agent/
      allow_hotfix: true
      check_project_fields: true
      project_owner: <owner>
      project_number: <number>
      # required_project_fields: "Agent,Area,Risk,Environment,Base Branch,Branch,PR URL"  # default
    secrets:
      project_token: ${{ secrets.AGENT_PROJECT_TOKEN }}
```

Reuses the same `AGENT_PROJECT_TOKEN` PAT (the `project` scope) and `project_owner`/`project_number`
as Project Sync — you don't need a second token. Turning this on assumes the GitHub Project already
has those fields configured (see `AGENTS.md` → "Project fields"); enable it only after Project Sync
itself is working, since the gate reads the same Project the sync writes to.

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
