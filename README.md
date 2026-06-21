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
3. **Install / update scripts** (`scripts/install-github-kit.sh`, `scripts/update-github-kit.sh`) —
   bring a target repo up to date without clobbering its existing content.
4. **Issue / PR templates** — a structured agent-task issue form and a PR template that captures
   Project metadata, validation state, and human review focus.
5. **GitHub Project helper scripts** (`templates/scripts/project/*.sh`) — thin `gh`/`jq` wrappers
   for adding items to a Project and updating its Status/text fields from a branch, a script, or a
   workflow run.

This repo intentionally contains very little repo-specific content. Everything that varies
per-repo (Project number, base branch, validation commands, forbidden files, etc.) lives in the
target repo's `docs/ai/PROJECT_CONFIG.md`, not here.

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
phase-by-phase specification, and [`templates/AGENTS.md`](templates/AGENTS.md) for the rules every
agent must follow.

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

## Installing into an existing repo

```bash
gh auth login
gh auth refresh -s project   # needed for Project read/write via gh

git switch -c agent/install-github-kit
/path/to/github-kit/scripts/install-github-kit.sh --target . --mode merge
git status
git diff --stat
```

`install-github-kit.sh` copies in any managed file that's missing, inserts/updates a managed block
in your existing `AGENTS.md`/`CLAUDE.md` instead of overwriting them, and never touches
`docs/ai/PROJECT_CONFIG.md` if it already exists. Review the diff, fill in
`docs/ai/PROJECT_CONFIG.md` with your repo's Project number/base branch/validation commands, copy
`docs/ai/PROJECT_CONFIG.env.example` to `docs/ai/PROJECT_CONFIG.env` (git-ignored) for the local
helper scripts, commit, and open a PR.

## Creating a new repo from this kit

Until a dedicated `template` repository exists, the same installer works on a brand-new repo:

```bash
gh repo create pzoli6/new-repo --private --clone
cd new-repo
/path/to/github-kit/scripts/install-github-kit.sh --target . --mode merge
```

## Configuring the Project number and token

1. Find your Project number: `gh project list --owner pzoli6`.
2. Fill in `docs/ai/PROJECT_CONFIG.md` (`GitHub Project owner` / `GitHub Project number`) and copy
   `docs/ai/PROJECT_CONFIG.env.example` → `docs/ai/PROJECT_CONFIG.env` for local script use.
3. Create a classic PAT (or fine-grained PAT) with the `project` scope, add it to the target repo
   as secret `AGENT_PROJECT_TOKEN` (Settings → Secrets and variables → Actions) — this is what the
   `project-sync.yml` caller workflow passes to `reusable-project-sync.yml`.

## How AI agents should use this

| Agent | Entry point |
|---|---|
| Claude Code | Reads `CLAUDE.md`, which points to `AGENTS.md` + `docs/ai/PROJECT_CONFIG.md` + `docs/ai/AGENT_WORKFLOW.md`. Also has a Claude Skill at `.claude/skills/issue-to-pr-project/SKILL.md`. |
| ChatGPT Codex | Reads `AGENTS.md` directly (the tool-agnostic universal rules file) plus the generic skill at `.agents/skills/issue-to-pr-project/SKILL.md`. |
| GitHub Copilot coding agent | Reads `.github/copilot-instructions.md`, which points to the same three files. |
| Cursor agents | Load `.cursor/rules/agent-workflow.mdc`, `git-safety.mdc`, `project-board.mdc`. |
| Antigravity / ChatGPT with repo context / future agents | Read `AGENTS.md` — it is intentionally tool-agnostic and is the fallback entry point for any agent without a dedicated adapter. |
| Manual development | Same lifecycle, same Project statuses — `AGENTS.md` and `docs/ai/AGENT_WORKFLOW.md` describe the human-authored path too. |

## Handoff files solve token-limit continuation

When an agent runs out of context/tokens mid-task, it writes its current state to
`docs/ai/handoffs/issue-<number>.md` and updates the Project's `Last Agent Update` and `Validation`
fields before stopping. The next agent (same tool or a different one entirely) reads that file
instead of re-deriving context from scratch — this is what let this exact task move from GitHub
Copilot to Claude Code mid-stream. See
[`templates/docs/ai/HANDOFF_INDEX.md`](templates/docs/ai/HANDOFF_INDEX.md).

## Updating target repos later

```bash
git switch -c agent/update-github-kit
/path/to/github-kit/scripts/update-github-kit.sh --target . --mode merge
git status
git diff --stat
```

`update-github-kit.sh` refreshes managed files and managed blocks but never overwrites
`docs/ai/PROJECT_CONFIG.md` or `docs/ai/PROJECT_CONFIG.env` unless you pass `--force-config`.
