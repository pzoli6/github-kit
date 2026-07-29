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
| Agent branch prefix | `agent/,claude/,codex/` |
| Default PR mode | draft |
| Solo mode | `auto` |
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

`Agent branch prefix` is a comma-separated allowlist of branch-name prefixes, matched by the
`pr-policy` CI check and swept by `cleanup_merged_branches.sh`. The **first** entry is what the
kit's own `publish_agent_branch.sh` uses when creating branches locally; the rest exist because
hosted agent platforms assign their own branch names (Claude Code on the web pushes `claude/*`,
Codex cloud pushes `codex/*`) and can't rename them without per-session human approval — the
policy's intent is "no arbitrary branch names targeting the base branch", which those prefixes
satisfy. Keep this list in sync with `require_agent_branch_prefix` in
`.github/workflows/pr-policy.yml`.

## Solo mode

`Solo mode` collapses the multi-agent-team ceremony to what a single maintainer iterating quickly
actually needs. Values:

- `auto` (default) — solo mode is **active** whenever `Project Sync enabled` is `false` **or**
  `GitHub Project number` is `TBD`; otherwise the full workflow applies. This means a fresh
  install behaves solo until a real GitHub Project is configured, with nothing extra to set.
- `true` — always active, even with a Project configured.
- `false` — never active; always run the full workflow.

While solo mode is active, agents follow the collapsed lifecycle in `AGENT_WORKFLOW.md` → "Solo
mode" instead of the full phase list:

- **Skip GitHub issue creation** for pre-approved iterations (`/github_kit` tasks, screenshot/
  preview-feedback rounds, review-comment fixes). Create an issue only when the human asks for
  one or the task will outlive the session. When no issue exists, drop the `Closes #` line from
  the PR body instead of leaving it empty.
- **Skip all Project-field steps** (`Status`, `Agent`, `Area`, `Risk`, `Environment`, `Branch`,
  `Base Branch`, `PR URL`, `Validation`, `Last Agent Update`, `Handoff`, `Agent Run`) — there is
  no board to update. The PR body's Validation section is the record instead.
- **Skip handoff files unless actually stopping mid-task** — an unfinished task still gets
  `docs/ai/handoffs/issue-<n>.md` (or `docs/ai/handoffs/<branch-slug>.md` when there's no issue)
  before you stop, but a task that ends at an open draft PR needs no handoff file.
- The lifecycle collapses to: **plan → implement → validate → draft PR.**

Everything else is unchanged in solo mode: the approval boundary (`approve` / `/github_kit`),
the production-branch gate (`approve main`), draft-first PRs, explicit `git add <file>` staging,
honest validation reporting, and never merging. Solo mode removes bookkeeping, not safety rails.

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
matching env var blank rather than guessing a real username or milestone title. `Default reviewer`
must name a human or team — never a paid review bot (e.g. GitHub Copilot code review): the kit's
workflow runs without any paid subscription, and a reviewer default must not quietly break that
(see `AGENT_WORKFLOW.md` → "Free-tier limitations").
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
      require_agent_branch_prefix: "agent/,claude/,codex/"
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

## Production-branch approval gate (CI)

A CI check, in the same `policy` job that already enforces `required_base_branch`, that fails the
PR if it targets the production branch (the "Production branch" key above, default `main`)
directly and its description is missing a specific human-authorization marker. This is the
mechanical enforcement of the conversational `approve main` gate — see `AGENTS.md` → "Production-
branch gate (`approve main`)" for what an agent must do before opening such a PR. It lives in
`reusable-pr-policy.yml`'s `policy` job, defaults to **off** centrally (so repos that installed
github-kit before this gate shipped aren't broken until they refresh), and is turned **on** by the
caller template in `.github/workflows/pr-policy.yml`:

```yaml
jobs:
  policy:
    uses: pzoli6/github-kit/.github/workflows/reusable-pr-policy.yml@main
    with:
      required_base_branch: develop
      require_agent_branch_prefix: "agent/,claude/,codex/"
      allow_hotfix: true
      production_branch: main
      require_production_branch_approval: true
      # production_branch_marker: "Production-branch authorization: approve main"  # default
```

`production_branch` should match the "Production branch" key in the table above. The check only
ever fires for a PR whose base is `production_branch` *and* doesn't already equal
`required_base_branch` — repos where both are the same branch (no develop/main split) never hit
this exception path, so there's nothing to configure for them beyond leaving the gate as-is or
turning it off. When it does fire, the PR body must contain this exact line (the agent adds it once
the human has said `approve main`):

```text
Production-branch authorization: approve main
```

The check reads the PR body only as data (never as a script), via GitHub Actions' `env:`
indirection — untrusted PR text is never interpolated directly into a shell command.

## CI trigger policy and Actions budget

How much CI this repo is willing to pay for, and what agents may do about it. The kit's caller
workflows ship budget-first defaults; if this repo wants something different, change the values
here **and** the `on:` triggers in `.github/workflows/*.yml` together.

| Key | Value |
|---|---|
| Actions budget posture | `metered` |
| CI on preview PRs (into the base branch) | `dispatch only` |
| CI on production-bound changes | `automatic` |
| Agents may dispatch CI | `only on explicit human request` |
| Agents may report CI status | `only for production-bound changes, or on request` |

- **`metered`** means Actions minutes cost real money on this account, so an unnecessary run is a
  real cost. Set it to `free` only for a public repo, where standard-runner minutes are free.
- **`dispatch only`** is why a preview PR normally shows **no checks at all**. That is the
  designed outcome, not a broken setup: agents must not investigate it, retry it, or mention it —
  see `AGENTS.md` → "CI expectations — don't chase checks".
- To run CI on a preview branch anyway, a human dispatches it explicitly:

  ```bash
  gh workflow run "CI (Node)" --ref <branch>     # or "CI (Python)" / "Agent Workflow Verify"
  ```

- To pause **every** kit workflow at once — e.g. to reserve the remaining budget for GitHub
  Copilot coding agent sessions, which also consume Actions minutes — set the repository Actions
  variable `KIT_ACTIONS_PAUSED` to `true` (Settings → Secrets and variables → Actions →
  Variables). See `docs/ai/AGENT_WORKFLOW.md` → "Actions budget and manual Copilot use".

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

## Worktree and dev-environment facts

Every agent task runs in its own git worktree (see `AGENTS.md` → "Branch and worktree rules").
`scripts/project/publish_agent_branch.sh` creates that worktree freshly branched from
`origin/<base branch>` and writes a `WORKTREE.md` preamble into it populated from the values below
— the facts an agent otherwise wastes calls reverse-engineering. Configure these in
`docs/ai/PROJECT_CONFIG.env` (copy from `.env.example`); this table documents what's expected, it
isn't read directly. Every one is optional — a blank or `TBD` value is simply left out of
`WORKTREE.md`.

| Key | Value | Purpose |
|---|---|---|
| `AGENT_WORKTREE_BASE` | TBD | Parent dir for worktrees. Default `<repo-parent>/<repo-name>-worktrees/<slug>` |
| `AGENT_DEV_SERVER_CMD` | TBD | Dev-server command, e.g. `npm run dev` |
| `AGENT_DEV_PORT_BASE` | TBD | Base port; each worktree gets a deterministic unique port (base + hash(slug)%100) so parallel agents don't collide |
| `AGENT_PREVIEW_ROUTE` | TBD | How to do visual QA without the auth wall, e.g. a `/dev` preview route |
| `AGENT_AUTH_NOTE` | TBD | What to know about auth-gating before loading the app |
| `AGENT_KEY_PATHS` | TBD | The few paths a newcomer needs first |
| `AGENT_VISUAL_QA_NOTE` | TBD | Browser gotchas, e.g. `Playwright: launch chromium with channel:'chrome'` |
| `AGENT_LAUNCH_TEMPLATE` | TBD | Optional path to a launch.json template copied into the worktree's `.claude/` with `__AGENT_DEV_PORT__` substituted |

The dev port, dev-server command, preview route, auth note, key paths, and Playwright/browser note
are exactly the things the github-kit authors found agents burning their first dozen calls
rediscovering — fill in the ones that apply to this repo and every agent inherits them through
`WORKTREE.md`.

## Repository-specific rules

Add anything specific to this repo that isn't already covered by the universal `AGENTS.md` —
deployment quirks, additional review requirements, naming conventions, etc.

```text
TBD
```
