# CLAUDE.md — Claude Code Adapter

This file tells Claude Code how to work in this repository. It is intentionally short — the actual
rules live in the files below, which are tool-agnostic and shared with every other agent that
works on this repo.

Read, in order, before doing anything else:

1. [`AGENTS.md`](../AGENTS.md) — universal rules: approval boundary, issue-to-PR workflow, Project
   status protocol and fields, branch/commit/validation/handoff/security/scope/PR rules, human
   authority.
2. [`docs/ai/PROJECT_CONFIG.md`](../docs/ai/PROJECT_CONFIG.md) — this repo's specific Project
   number, base branch, validation commands, and forbidden files.
3. [`docs/ai/AGENT_WORKFLOW.md`](../docs/ai/AGENT_WORKFLOW.md) — the detailed phase-by-phase
   workflow spec (task intake → plan review → issue/Project setup → branch/worktree →
   implementation → validation → commit/PR → review/continuation → completion).

A matching Claude Skill describing this same workflow lives at
`.claude/skills/issue-to-pr-project/SKILL.md` — use it when running the issue-to-PR-project flow
end to end.

A fast-path slash command, `/github_kit <task>`, is also available at
`.claude/commands/github_kit.md` (runbook: `.claude/skills/github_kit/SKILL.md`) — invoking it is
itself the human's approval for the described task, see "Non-negotiable behaviors" below. A
companion command, `/github_kit_update` (`.claude/skills/github_kit_update/SKILL.md`), refreshes
this repo's local github-kit bootstrap files from `pzoli6/github-kit@main` via a draft PR — use it
when local files seem stale, not as part of routine `/github_kit` runs.

## Non-negotiable behaviors for Claude Code specifically

- **Plan first, then stop — unless invoked via `/github_kit`.** For any non-trivial task, produce a
  plan and wait for the human to reply with `approve issue-to-pr-project` before creating a branch,
  writing code, or running installer/update scripts. Don't treat a description of the problem as
  approval to implement. The one exception: if the human's message is itself `/github_kit <task>`,
  that invocation is the approval for `<task>` — proceed per `.claude/skills/github_kit/SKILL.md`
  instead of waiting for the separate phrase.
- **Update handoff files before running low on context.** If you're approaching a context/token
  limit mid-task, write your current state to `docs/ai/handoffs/issue-<number>.md` and update the
  Project's `Last Agent Update` and `Validation` fields *before* you stop — the next agent (Claude
  Code again, or a completely different tool) picks up from that file, not from re-reading the
  whole conversation.
- **Never merge a PR.** Open draft PRs, push updates, respond to review feedback — merging is
  always a human action.
- **Never push directly to the base or production branch**, and never run `git add -A` / `git add
  .` — stage explicit files only, per `AGENTS.md`.
- **Declare relationships explicitly.** If an issue/PR is blocked by, blocks, or is part of
  another, say so in the body (`Blocked by #12`); otherwise write `Relationships: none declared`
  rather than leaving it unaddressed. See `AGENTS.md` → "GitHub relationships and development
  links".

<!-- BEGIN GITHUB-KIT UNIVERSAL WORKFLOW -->
## Universal AI-Agent Workflow

This repository follows the universal issue-to-PR workflow from `pzoli6/github-kit`.

Agents must read:
- `AGENTS.md`
- `docs/ai/PROJECT_CONFIG.md`
- `docs/ai/AGENT_WORKFLOW.md`

Every implementation task must follow:
User task → plan → human approval → GitHub issue → Project update → agent branch/worktree → implementation → validation → draft PR → handoff → human review.

Required approval phrase:
```text
approve issue-to-pr-project
```

Fast path: `/github_kit <task>` is a pre-approved alternative entry point — the invocation itself is the approval for the described task, scoped to that task only. See `docs/ai/AGENT_WORKFLOW.md` → "Fast-path trigger: /github_kit".

Agents must not push to protected branches, merge PRs, modify secrets, use `git add .`, or claim validation passed unless validation actually ran.

Before stopping, losing context, or handing off to another agent, agents must update:
- `docs/ai/handoffs/issue-<number>.md`
- Project field: `Last Agent Update`
- Project field: `Validation`
<!-- END GITHUB-KIT UNIVERSAL WORKFLOW -->
