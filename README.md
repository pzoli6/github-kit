# github-kit

Central reusable GitHub workflow and AI-agent development kit.

`github-kit` is the canonical source of truth for the issue-to-PR-to-Project workflow used across
all of `pzoli6`'s repositories, for both human contributors and AI coding agents (Claude Code,
ChatGPT Codex, GitHub Copilot coding agent, Cursor agents, Antigravity, ChatGPT with repo context,
and future agents). It provides:

1. **Reusable GitHub Actions workflows** (`.github/workflows/reusable-*.yml`) — called via
   `workflow_call` from any target repo.
2. **AI-agent workflow templates** (`templates/`) — `AGENTS.md`, `CLAUDE.md`, Cursor rules, Claude
   and generic agent skills, Copilot instructions, and the `docs/ai/` workflow specification.
3. **Install / update / doctor scripts** — both Bash (`scripts/*.sh`, for Linux/macOS/WSL/Git
   Bash) and native PowerShell (`scripts/*.ps1`, for Windows) — bring a target repo up to date
   without clobbering its existing content, and audit `github-kit`'s own packaging.
4. **Issue / PR templates** — a structured agent-task issue form and a PR template that captures
   Project metadata, validation state, and human review focus.
5. **GitHub Project helper scripts** (`templates/scripts/project/*.sh`) — thin `gh`/`jq` wrappers
   for adding items to a Project and updating its Status/text fields from a branch, a script, or a
   workflow run, plus an idempotent standard-labels creator.

This repo intentionally contains very little repo-specific content. Everything that varies
per-repo (Project number, base branch, validation commands, forbidden files, github-kit version,
etc.) lives in the target repo's `docs/ai/PROJECT_CONFIG.md`, not here.

## Free-tier usage and branch protection

`github-kit` targets the **GitHub Free plan** as the default case, not an afterthought:

- **Private repositories on GitHub Free cannot enforce branch protection rulesets** — no required
  reviews, no required status checks blocking a merge, at the platform level. This is a GitHub
  plan limitation, not a `github-kit` configuration gap.
- The kit compensates with **process discipline instead of platform enforcement**: every PR opens
  as a draft, CI workflows still run and report pass/fail (they just can't be marked "required"),
  and the agent rules in `AGENTS.md` forbid self-merging regardless of what GitHub will technically
  allow.
- If a repo is later upgraded to a plan that supports branch protection (or made public), a human
  can enable required reviews/status checks at that point — nothing here needs to change first.
- `docs/ai/PROJECT_CONFIG.md` records this per repo as `Branch protection enforced: false` so
  agents don't assume enforcement that isn't actually happening.

## The universal workflow

Every repo that installs this kit follows the same lifecycle:

```text
User task
→ agent reads repo instructions (AGENTS.md, docs/ai/PROJECT_CONFIG.md, docs/ai/AGENT_WORKFLOW.md)
→ agent creates plan
→ human approval ("approve issue-to-pr-project")
→ GitHub issue
→ GitHub Project update
→ agent branch
→ isolated worktree
→ implementation
→ validation
→ draft PR
→ handoff file
→ human review
→ human merge
```

See [`templates/docs/ai/AGENT_WORKFLOW.md`](templates/docs/ai/AGENT_WORKFLOW.md) for the full
phase-by-phase specification (including free-tier limitations, pausing/resuming for AI usage
limits, and the manual-Project-update fallback), and [`templates/AGENTS.md`](templates/AGENTS.md)
for the rules every agent must follow.

## Always-latest main channel

By default, `install-github-kit.sh`/`.ps1` write caller `uses:` lines as literal
`pzoli6/github-kit/<path>@main` — not a tag, not a placeholder. Once a repo has `github-kit`
installed, its CI workflows automatically pick up every change merged to this repo's `main` branch
on their very next run.

What auto-tracks `@main` and what doesn't:

- **Reusable workflows auto-track `@main`.** Fix or extend a reusable workflow once here, and every
  repo that calls it gets the fix on its next workflow run — no version bump, no re-running the
  installer.
- **Local bootstrap files never auto-track anything.** `AGENTS.md`/`CLAUDE.md`, Cursor rules, the
  Claude/Codex skills, and this kit's own scripts live in the target repo's working tree. They only
  refresh when you explicitly run `update-github-kit.sh`/`.ps1`, or its `/github_kit_update` wrapper
  (see below) — `@main` auto-tracking has no effect on them.
- **Pinning is still supported, just no longer the default.** Pass `--ref <tag-or-sha>` /
  `-Ref <tag-or-sha>` to either the installer or the updater to deliberately pin a repo instead of
  auto-tracking `main`. The legacy `--workflow-ref`/`-WorkflowRef` flag names still work as aliases.
  If you pin, update `docs/ai/PROJECT_CONFIG.md`: set `github-kit ref` to the pinned ref and
  `github-kit update mode` to `pinned` (instead of the default `main-channel`), so agents don't
  assume auto-updates are happening that aren't.

Because a merge to this repo's `main` is live for every installed repo on their next CI run, with no
opt-in step, changes here deserve a higher review bar than a typical app repo.

## Fast-path trigger: /github_kit

`/github_kit <task description>` is a pre-approved alternative entry point into the same lifecycle
above. Typing it is itself the human's approval for `<task>`, scoped strictly to that description —
the agent still writes a visible plan, still creates the issue and tracks it on the Project, still
opens a **draft** PR, still never merges or tags, but skips the separate wait for `approve
issue-to-pr-project`. If the work turns out to need more than `<task>` described, the agent falls
back to the normal approval gate for the extra scope.

This is additive: `approve issue-to-pr-project` remains the default gate for everything else, and
the existing `issue-to-pr-project` workflow is untouched. Each agent has its own entry point —
Claude Code's `/github_kit` slash command, the generic `.agents/skills/github_kit/SKILL.md` skill,
and the `.cursor/rules/github-kit-command.mdc` Cursor rule — see the table below and
[`templates/docs/ai/AGENT_WORKFLOW.md`](templates/docs/ai/AGENT_WORKFLOW.md) → "Fast-path trigger:
/github_kit" for the full spec.

`/github_kit` is unrelated to the always-latest `@main` channel above: it runs entirely from
whatever local files already exist in the repo's working tree and never requires network access.
Refreshing those local files from `pzoli6/github-kit@main` is a separate, optional command —
`/github_kit_update`, described next.

## Local bootstrap refresh: /github_kit_update

`@main` auto-tracking only covers reusable workflows. `AGENTS.md`/`CLAUDE.md`, Cursor rules,
Claude/Codex skills, `copilot-instructions.md`, and this kit's own helper scripts are local files
that lag behind until something explicitly refreshes them. `/github_kit_update`
(`.claude/skills/github_kit_update/SKILL.md`, `.agents/skills/github_kit_update/SKILL.md`) is that
something: it runs `update-github-kit.sh`/`.ps1` against `pzoli6/github-kit@main`, refuses a dirty
working tree unless told otherwise, never overwrites `docs/ai/PROJECT_CONFIG.md` unless
`--force-config`/`-ForceConfig`, never installs Project Sync unless requested, and always stops at a
**draft PR** for human review — it never merges. Unlike `/github_kit`, this command requires
actually reaching `github-kit@main`; if it can't, it stops and reports the block rather than
silently doing nothing. Run it whenever local bootstrap files seem stale — it's optional precisely
because the reusable-workflow callers already auto-track `@main` on their own.

## Enabling private reusable workflow access

If `github-kit` and your target repos are private, the target repo's `GITHUB_TOKEN` needs
permission to call workflows in this repo:

1. In `pzoli6/github-kit` → **Settings → Actions → General → Access**, choose **"Accessible from
   repositories in the `pzoli6` organization/account"** (or explicitly allow the target repo).
2. In the target repo, the caller workflow's job needs at minimum:
   ```yaml
   permissions:
     contents: read
   ```
   Reusable workflows that call `gh project` commands additionally need a PAT with the `project`
   scope passed in as a secret (see below) — the default `GITHUB_TOKEN` cannot read/write Projects.
3. If both repos are public, no extra access configuration is required — public reusable workflows
   are callable from any repo.

## Working-tree requirements

Every install/update script (Bash and PowerShell) refuses to run against a target repo with
uncommitted changes, unless you pass `--allow-dirty` / `-AllowDirty`:

```text
target repository has uncommitted changes.
Commit or stash your work first, then re-run — or pass --allow-dirty if you understand the risk.
```

This exists because a script that copies/refreshes files is much easier to review (and revert, if
something looks wrong) against a clean `git diff` than mixed in with unrelated in-progress work.
Commit or `git stash` first; only reach for `--allow-dirty`/`-AllowDirty` if you've deliberately
decided to review everything together afterward.

## Installing into an existing repo

### Linux / macOS / WSL / Git Bash

```bash
gh auth login
gh auth refresh -s project   # needed for Project read/write via gh

git switch -c agent/install-github-kit
/path/to/github-kit/scripts/install-github-kit.sh --target . --mode merge
git status
git diff --stat
```

### Windows (PowerShell)

```powershell
gh auth login
gh auth refresh -s project   # needed for Project read/write via gh

git switch -c agent/install-github-kit
& "C:\path\to\github-kit\scripts\install-github-kit.ps1" -Target . -Mode merge
git status
git diff --stat
```

Both installers behave identically: they copy in any managed file that's missing, insert/update a
managed block in your existing `AGENTS.md`/`CLAUDE.md` instead of overwriting them, and never touch
`docs/ai/PROJECT_CONFIG.md` if it already exists. Review the diff, fill in
`docs/ai/PROJECT_CONFIG.md` with your repo's Project number/base branch/validation commands, copy
`docs/ai/PROJECT_CONFIG.env.example` to `docs/ai/PROJECT_CONFIG.env` (git-ignored) for the local
helper scripts, commit, and open a PR.

`.github/workflows/project-sync.yml` is **not installed by default** by either installer — pass
`--include-project-sync` / `-IncludeProjectSync` once you've set up a real GitHub Project and an
`AGENT_PROJECT_TOKEN` secret (see "Configuring the Project number and token" below, and "Why
Project Sync is Phase 2" further down).

## Creating a new repo from this kit

Until a dedicated `template` repository exists, the same installers work on a brand-new repo:

```bash
gh repo create pzoli6/new-repo --private --clone
cd new-repo
/path/to/github-kit/scripts/install-github-kit.sh --target . --mode merge
```

```powershell
gh repo create pzoli6/new-repo --private --clone
Set-Location new-repo
& "C:\path\to\github-kit\scripts\install-github-kit.ps1" -Target . -Mode merge
```

## Configuring the Project number and token

1. Find your Project number: `gh project list --owner pzoli6`.
2. Fill in `docs/ai/PROJECT_CONFIG.md` (`GitHub Project owner` / `GitHub Project number`) and copy
   `docs/ai/PROJECT_CONFIG.env.example` → `docs/ai/PROJECT_CONFIG.env` for local script use.
3. Create a classic PAT (or fine-grained PAT) with the `project` scope, add it to the target repo
   as secret `AGENT_PROJECT_TOKEN` (Settings → Secrets and variables → Actions) — this is what the
   `project-sync.yml` caller workflow passes to `reusable-project-sync.yml`.

## Optional: standard labels

`templates/scripts/project/create_standard_labels.sh` creates (or updates, via `--force`) a set of
`status:`/`type:`/`risk:` labels used for filtering issues/PRs. It's installed by both installers
automatically, but never run automatically — labels are a convenience, not a requirement:

```bash
gh auth login   # needs repo scope
scripts/project/create_standard_labels.sh
```

Their absence never blocks creating an issue, opening a PR, or moving a tracked item through the
workflow — see "Project Sync and labels (optional)" in `templates/AGENTS.md`.

## Why Project Sync is Phase 2

`.github/workflows/project-sync.yml` would update Project fields (`Status`, `PR URL`, etc.)
automatically from PR/issue activity. It's deliberately **not** part of the default install
because it needs two things most repos don't have on day one:

1. A real GitHub Project already created, with its number filled into `docs/ai/PROJECT_CONFIG.md`.
2. An `AGENT_PROJECT_TOKEN` secret with `project` scope — the default `GITHUB_TOKEN` can't read or
   write Projects.

Until both exist, agents update Project fields manually with `scripts/project/project_set_status.sh`
/ `project_set_text.sh` (or by editing the Project UI) at each phase transition — see "When Project
Sync isn't enabled" in `templates/docs/ai/AGENT_WORKFLOW.md`. Add it later with
`--include-project-sync` / `-IncludeProjectSync` on either installer/updater once the prerequisites
are in place, and flip `Project Sync enabled` to `true` in `docs/ai/PROJECT_CONFIG.md`.

## Pausing and resuming work (AI usage limits)

AI coding agents (Codex, Claude Code, and others) can hit a usage limit mid-task. `github-kit`
treats that as a controlled pause, not an abandoned task — commit or `git stash` what's in
progress, write a handoff file describing exactly what's stashed and how to resume, and set the
Project's `Status` to `Blocked` with the reason. The next session (same agent, later, or a
different tool entirely) reads the handoff file before touching the worktree. Full procedure:
"Pausing for AI usage limits" and "Resuming stashed work" in
[`templates/docs/ai/AGENT_WORKFLOW.md`](templates/docs/ai/AGENT_WORKFLOW.md).

## How AI agents should use this

| Agent | Entry point |
|---|---|
| Claude Code | Reads `CLAUDE.md`, which points to `AGENTS.md` + `docs/ai/PROJECT_CONFIG.md` + `docs/ai/AGENT_WORKFLOW.md`. Also has a Claude Skill at `.claude/skills/issue-to-pr-project/SKILL.md`, and the fast-path `/github_kit` slash command (`.claude/commands/github_kit.md`, runbook `.claude/skills/github_kit/SKILL.md`). |
| ChatGPT Codex | Reads `AGENTS.md` directly (the tool-agnostic universal rules file) plus the generic skill at `.agents/skills/issue-to-pr-project/SKILL.md` (and its fast-path counterpart, `.agents/skills/github_kit/SKILL.md`). |
| GitHub Copilot coding agent | Reads `.github/copilot-instructions.md`, which points to the same three files. |
| Cursor agents | Load `.cursor/rules/agent-workflow.mdc`, `git-safety.mdc`, `project-board.mdc`, and `github-kit-command.mdc` (the `/github_kit` fast-path trigger). |
| Antigravity / ChatGPT with repo context / future agents | Read `AGENTS.md` — it is intentionally tool-agnostic and is the fallback entry point for any agent without a dedicated adapter, including recognizing the `/github_kit` trigger. |
| Manual development | Same lifecycle, same Project statuses — `AGENTS.md` and `docs/ai/AGENT_WORKFLOW.md` describe the human-authored path too. |

## Handoff files solve token-limit continuation

When an agent runs out of context/tokens mid-task, it writes its current state to
`docs/ai/handoffs/issue-<number>.md` and updates the Project's `Last Agent Update` and `Validation`
fields before stopping. The next agent (same tool or a different one entirely) reads that file
instead of re-deriving context from scratch — this is what let this exact task move from GitHub
Copilot to Claude Code mid-stream. See
[`templates/docs/ai/HANDOFF_INDEX.md`](templates/docs/ai/HANDOFF_INDEX.md).

## Updating target repos later

### Linux / macOS / WSL / Git Bash

```bash
git switch -c agent/update-github-kit
/path/to/github-kit/scripts/update-github-kit.sh --target .
git status
git diff --stat
```

### Windows (PowerShell)

```powershell
git switch -c agent/update-github-kit
& "C:\path\to\github-kit\scripts\update-github-kit.ps1" -Target .
git status
git diff --stat
```

Both updaters refresh managed files and managed blocks (caller workflows stay pinned to literal
`@main` unless you pass `--ref`/`-Ref` to deliberately repoint them) but never overwrite
`docs/ai/PROJECT_CONFIG.md` or `docs/ai/PROJECT_CONFIG.env` unless you pass `--force-config` /
`-ForceConfig`.

## Pinning to a fixed ref (opt-out of the main channel)

Target repos default to the always-latest `@main` channel (see above) and need no action to stay
current. If you'd rather pin a repo to a fixed tag or commit SHA instead — e.g. to freeze behavior
during a migration, or to review `github-kit` changes before they land — pass `--ref`/`-Ref` to the
installer or updater:

```bash
/path/to/github-kit/scripts/update-github-kit.sh --target . --ref v0.3.0
```

```powershell
& "C:\path\to\github-kit\scripts\update-github-kit.ps1" -Target . -Ref v0.3.0
```

This repoints only the `uses: pzoli6/github-kit/...` lines in caller workflows — it never touches
unrelated occurrences of "main" (e.g. `branches: [main, develop]` triggers). Afterward, update
`docs/ai/PROJECT_CONFIG.md`: set `github-kit ref` to the pinned value and `github-kit update mode`
to `pinned`, so agents and the verifier know not to expect auto-updates. To move a pinned repo to a
newer ref later, re-run the same command with a different `--ref`/`-Ref` value.

## Recommended rollout sequence

For a brand-new repo, in order:

1. Install with the default flags (`--mode merge`, no `--include-project-sync`).
2. Fill in `docs/ai/PROJECT_CONFIG.md` (Project name/number, base branch, validation commands,
   forbidden files).
3. Optional: run `create_standard_labels.sh` once `gh auth login` has repo scope.
4. If the repo's GitHub plan supports it, enable branch protection / required status checks by
   hand — `github-kit` won't do this for you, and most repos start without it (see "Free-tier
   usage and branch protection" above).
5. Once a real GitHub Project and `AGENT_PROJECT_TOKEN` exist, re-run the installer/updater with
   `--include-project-sync` to add automatic field syncing — treat this as a deliberate Phase 2
   step, not part of initial setup.

Run `scripts/doctor-github-kit.sh` (or `.ps1`) inside `github-kit` itself — not a target repo —
before tagging a new release, to catch packaging regressions (CRLF line endings, stale Action
versions, template caller workflows missing literal `@main`, stale `GITHUB_KIT_VERSION`
placeholders, missing required files/phrases).

## Versioning

Tags (`v0.1.0`, `v0.2.0`, ...) remain available as optional pin targets for repos that opt out of
the always-latest `@main` channel (see "Pinning to a fixed ref" above) — they are no longer the
default for new installs. Bump the minor version for additive changes (new optional
scripts/templates, new flags with safe defaults) and the patch version for fixes that don't change
behavior for repos that don't opt in to anything new. See
[`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md) for the exact tagging procedure — tagging
is a human action taken after a hardening/feature PR merges, never something an agent does as part
of implementing that PR, and is now a courtesy for pinned repos rather than a required release step.
