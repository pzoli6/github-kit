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

> **Setting this up, or something not propagating?** → **[docs/OWNER_SETUP.md](docs/OWNER_SETUP.md)**
> — the steps only the repo owner can do (tokens, secrets), each with a way to check whether it is
> already done, plus a troubleshooting table. Fan-out does nothing until Step 1 there is complete.

This repo intentionally contains very little repo-specific content. Everything that varies
per-repo (Project number, base branch, validation commands, forbidden files, github-kit version,
etc.) lives in the target repo's `docs/ai/PROJECT_CONFIG.md`, not here.

## Free-tier usage and branch protection

`github-kit` targets the **GitHub Free plan** as the default case, not an afterthought:

- **No paid subscription is required — or invoked — by any part of the kit's CI/CD.** Every
  workflow is plain GitHub Actions (free for public repos, free-minutes tier for private ones)
  using standard public actions (`actions/checkout`, `setup-node`, `setup-python`,
  `pnpm/action-setup`) plus the free `gh` CLI and GitHub Projects (v2). Nothing calls GitHub
  Copilot, GitHub Advanced Security/CodeQL, or a paid Marketplace app; PR review is human review.
  The Copilot *adapter file* (`.github/copilot-instructions.md`) is inert instruction text — free
  to keep, only read by Copilot if a repo owner separately subscribes — and a repo that doesn't
  use Copilot can delete it and set `require_copilot: false` in `agent-workflow-verify.yml`.
- **The kit's CI shares the account's Actions budget with everything else that runs on Actions** —
  notably manual GitHub Copilot coding agent runs (assign a task, resolve a PR's merge conflicts,
  apply review feedback), which execute as Actions workflow runs in the repo. So the kit is
  budget-aware: the template CI/verify workflows trigger only for production-bound changes (PR
  targeting the production branch, or a push to it) or an explicit `workflow_dispatch` — never
  automatically on preview-bound PRs, where agents validate locally instead; every reusable
  workflow job additionally skips — consuming no minutes — while the caller repo's Actions
  variable `KIT_ACTIONS_PAUSED` is `true`; and CI runs superseded by a newer push to the same PR
  are auto-cancelled. The pause switch and auto-cancel live in the reusable workflows, so repos on
  the `@main` channel get those without refreshing local files (the triggers live in each repo's
  caller files, refreshed via `/github_kit_update`). The kit also tells agents to **stop chasing
  checks**: a preview PR with no checks is the designed outcome, so agents must not fetch check
  runs, poll, subscribe to PR activity, self-dispatch a workflow, or report "CI didn't run / is
  red" — which keeps their tokens and your attention on the work instead of a non-problem. CI is
  their business only when you ask or when a change is production-bound; see
  [`templates/AGENTS.md`](templates/AGENTS.md) → "CI expectations — don't chase checks" and
  `docs/ai/PROJECT_CONFIG.md` → "CI trigger policy and Actions budget".
  Manual Copilot use itself is always the human's
  call and never blocked by the kit; the budget guidance (including a zero-Actions local
  conflict-resolution fallback) is in [`templates/docs/ai/AGENT_WORKFLOW.md`](templates/docs/ai/AGENT_WORKFLOW.md)
  → "Actions budget and manual Copilot use".
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
→ human approval ("approve")
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
specification — a happy-path checklist plus an on-demand appendix (free-tier limitations,
pausing/resuming for AI usage limits, the manual-Project-update fallback, and other
conditionally-read sections) — and [`templates/AGENTS.md`](templates/AGENTS.md) for the rules
every agent must follow.

Two knobs adapt this lifecycle to how a repo is actually used:

- **Solo mode** (`docs/ai/PROJECT_CONFIG.md` → "Solo mode", default `auto`) collapses the
  team-scale ceremony for a single maintainer iterating quickly: no issue for pre-approved
  iterations, no Project-field updates, handoff files only when actually stopping mid-task —
  plan → implement → validate → draft PR. With the default `auto`, solo mode is active until a
  real GitHub Project is configured, so fresh installs behave solo with nothing to set. The
  approval gates and git/PR safety rules are unchanged.
- **Branch-prefix allowlist.** The `pr-policy` check accepts a comma-separated list of branch
  prefixes (default `agent/,claude/,codex/`): `agent/` is what the kit's scripts create, while
  `claude/`/`codex/` are what hosted agent platforms (Claude Code on the web, Codex cloud) assign
  on their own and can't rename without per-session approval. The policy's intent is "no
  arbitrary branch names targeting the base branch" — rejecting a platform-assigned prefix only
  produces duplicate PRs and permanently red checks.

## Remote-first metadata workflow

An agent branch, issue, or PR with blank sidebar metadata is easy to lose track of — no assignee
means no notification, no labels means it's invisible to filters, and a branch that only exists
locally can vanish with the worktree. `github-kit` closes those gaps with four scripts in
`templates/scripts/project/` that every agent workflow now calls instead of raw `gh` commands:

| Script | When | What it fills in |
|---|---|---|
| `create_agent_issue.sh` | Creating the tracking issue | assignee, labels, milestone, adds the issue to the Project |
| `publish_agent_branch.sh` | Immediately after the issue exists, **before any implementation code** | pushes the agent branch to `origin` right away — never local-only |
| `sync_project_fields.sh <checkpoint> <issue-or-pr-url> [text]` | At each workflow checkpoint (issue created, branch pushed, PR opened, review states, done) | `Status`, `Validation`, `Last Agent Update`, and other Project fields, in one call |
| `create_agent_pr.sh` | Opening the draft PR | assignee, reviewer, labels, milestone, adds the PR to the Project |

Two policies apply alongside these scripts:

- **Relationships.** Every issue/PR body either declares real relationships (`Blocked by #12`,
  `Blocks #34`, `Part of #5`) or states `Relationships: none declared` — never silence on the
  question. See `templates/AGENTS.md` → "GitHub relationships and development links".
- **Notifications.** Agents rely on `--assignee`/`--reviewer` (set by the scripts above) to ensure
  the right humans are notified, rather than assuming a separate subscribe/watch step exists. See
  `templates/AGENTS.md` → "Notifications and participation".

`scripts/project/verify_agent_workflow.sh` (and its CI mirror,
`.github/workflows/reusable-agent-workflow-verify.yml`) checks that all four scripts are present
and that both policy phrases appear somewhere in the repo, so a repo can't silently drift back to
the old late-push, blank-metadata pattern.

## Always-latest main channel

By default, `install-github-kit.sh`/`.ps1` write caller `uses:` lines as literal
`pzoli6/github-kit/<path>@main` — not a tag, not a placeholder. Once a repo has `github-kit`
installed, its CI workflows automatically pick up every change merged to this repo's `main` branch
on their very next run.

What auto-tracks `@main` and what doesn't:

- **Reusable workflows auto-track `@main` directly.** Fix or extend a reusable workflow once here,
  and every repo that calls it gets the fix on its next workflow run — no version bump, no
  re-running the installer, no PR.
- **Local bootstrap files auto-propagate via the fan-out workflow (below), not via `@main`.**
  `AGENTS.md`/`CLAUDE.md`, Cursor rules, the Claude/Codex skills, and this kit's own scripts live in
  the target repo's working tree, so a `uses: …@main` reference can't reach them. Instead,
  [`.github/workflows/github-kit-fanout.yml`](.github/workflows/github-kit-fanout.yml) opens a draft
  PR in each target repo whenever those files drift from `main` — you review and merge, never the
  automation. Running `update-github-kit.sh`/`.ps1` or `/github_kit_update` by hand still works as
  an on-demand alternative.
- **Pinning is still supported, just no longer the default.** Pass `--ref <tag-or-sha>` /
  `-Ref <tag-or-sha>` to either the installer or the updater to deliberately pin a repo instead of
  auto-tracking `main`. The legacy `--workflow-ref`/`-WorkflowRef` flag names still work as aliases.
  If you pin, update `docs/ai/PROJECT_CONFIG.md`: set `github-kit ref` to the pinned ref and
  `github-kit update mode` to `pinned` (instead of the default `main-channel`), so agents don't
  assume auto-updates are happening that aren't.

Because a merge to this repo's `main` is live for every installed repo on their next CI run, with no
opt-in step, changes here deserve a higher review bar than a typical app repo.

## Fan-out propagation of bootstrap files

`@main` auto-tracking covers reusable workflows but structurally can't cover the *local* bootstrap
files copied into each repo (`AGENTS.md`/`CLAUDE.md`/`GEMINI.md` managed blocks, skills, Cursor
rules, `copilot-instructions.md`, `docs/ai/*`, `scripts/project/*`). The fan-out workflow closes
that gap so you never have to run `/github_kit_update` in each repo by hand.

[`.github/workflows/github-kit-fanout.yml`](.github/workflows/github-kit-fanout.yml) runs in
**github-kit itself** and:

- triggers on every push to `main` that touches `templates/**` or the install/update scripts, plus
  a weekly cron safety net and manual `workflow_dispatch`;
- reads the target list from [`.github/fanout-targets.json`](.github/fanout-targets.json) (add a
  repo by appending one `{ "repo": "...", "base": "..." }` entry — nothing is needed on the target
  side);
- for each target, refreshes its bootstrap files from `github-kit@main` via `update-github-kit.sh`
  and opens a **draft PR** on the repo's base branch if anything drifted — it never merges, never
  force-pushes, and never touches repo-specific files: `docs/ai/PROJECT_CONFIG.md` or
  `.github/workflows/pr-policy.yml` (which holds each repo's `required_base_branch` gate). The
  reusable policy *logic* still auto-tracks `@main`; only that repo's base-branch wiring is left
  alone.

**Required secret (one, in github-kit only):** `GITHUB_KIT_FANOUT_TOKEN`. The default
`GITHUB_TOKEN` can't reach other repos, which is why a PAT is needed. Until the secret exists, the
workflow fails fast with a clear message instead of silently doing nothing.

A **fine-grained** PAT (Contents: RW + Pull requests: RW on each target) is enough **only while
every target belongs to one account** — fine-grained PATs are scoped to a single resource owner and
cannot select repos you are merely an outside collaborator on. The target list now spans `pzoli6`
and `pszichocloud`, so it needs a **classic** PAT with the `repo` scope, created by an account
with push access to every target. Full instructions, including the least-privilege alternative:
**[docs/OWNER_SETUP.md](docs/OWNER_SETUP.md)**.

The mental model is: **you improve `github-kit`, and every repo gets a draft PR** — reusable CI
logic updates itself with no PR, and local files arrive as reviewable PRs.

## Fast-path trigger: /github_kit

`/github_kit <task description>` is a pre-approved alternative entry point into the same lifecycle
above. Typing it is itself the human's approval for `<task>`, scoped strictly to that description —
the agent still writes a visible plan, still creates the issue and tracks it on the Project, still
opens a **draft** PR, still never merges or tags, but skips the separate wait for `approve`.
If the work turns out to need more than `<task>` described, the agent falls back to the normal
approval gate for the extra scope.

This is additive: `approve` remains the default gate for everything else, and
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

> **Cross-account does not work, at all.** A private repo can only share its reusable
> workflows with repos owned by the **same** user or organisation — the Access setting offers no
> way to allow a repo owned by a different account. A caller in such a repo fails with `jobs = 0`
> and "This run likely failed because of a workflow file issue", which looks like a broken YAML
> file and isn't. If any target lives under a different account, **make `github-kit` public** —
> see [docs/OWNER_SETUP.md](docs/OWNER_SETUP.md) → "Making `github-kit` public".

If `github-kit` and your target repos are private **and owned by the same account**, the target
repo's `GITHUB_TOKEN` needs permission to call workflows in this repo:

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

## Worktree-per-task lifecycle

Because multiple agents work a repo in parallel, every task runs in its own git worktree —
`scripts/project/publish_agent_branch.sh --issue <issue> --slug <short>` fetches and forks a
**real** worktree from `origin/<base branch>` (its own checkout + `.git` file, registered in
`git worktree list`), pushes the branch, and prints the worktree path. It also drops a
`WORKTREE.md` preamble into the worktree — issue number, base branch, a unique per-worktree dev
port, dev-server command, preview/QA route, auth notes, and key paths sourced from
`docs/ai/PROJECT_CONFIG` — so an agent doesn't burn its first dozen calls reverse-engineering the
setup. Configure those facts once per repo in `docs/ai/PROJECT_CONFIG.env` (see "Worktree and
dev-environment facts" in `templates/docs/ai/PROJECT_CONFIG.md`).

Once an agent learns a PR has merged, it runs
`scripts/project/cleanup_merged_branches.sh --branch <branch>` (or with no `--branch` to sweep
every local branch matching the configured agent prefixes — `agent/`, `claude/`, `codex/` by
default — at once). For a merged branch it **removes the worktree,
deletes the local branch, and closes the linked issue** (Project `Status` → `Done` plus
`gh issue close`) — but only when its PR is actually `MERGED`, the local tip matches exactly what
GitHub merged, and the worktree has no unsaved work beyond the kit's own scratch files. Anything
that fails a check is left alone with a `SKIPPED: <reason>` line instead of being force-removed —
the remote branch is never touched. See `templates/AGENTS.md` → "Branch and worktree rules".

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
