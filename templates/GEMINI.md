# GEMINI.md — Gemini CLI Adapter

This file tells Gemini CLI how to work in this repository. It is intentionally short — the actual
rules live in the files below, which are tool-agnostic and shared with every other agent that
works on this repo.

Read, in order, before doing anything else:

1. [`AGENTS.md`](../AGENTS.md) — universal rules: approval boundary, production-branch gate,
   stop-and-ask gates, issue-to-PR workflow, Project status protocol and fields,
   branch/commit/validation/handoff/security/scope/PR rules, human authority.
2. [`docs/ai/PROJECT_CONFIG.md`](../docs/ai/PROJECT_CONFIG.md) — this repo's specific Project
   number, base branch, validation commands, and forbidden files.
3. [`docs/ai/AGENT_WORKFLOW.md`](../docs/ai/AGENT_WORKFLOW.md) — the detailed phase-by-phase
   workflow spec (task intake → plan review → issue/Project setup → branch/worktree →
   implementation → validation → commit/PR → review/continuation → completion).

A matching runbook describing this same workflow lives at
`.agents/skills/issue-to-pr-project/SKILL.md` — read it when running the issue-to-PR-project flow
end to end. Gemini CLI has no dedicated `.gemini/` skill directory in this kit; it shares the
generic `.agents/skills/` runbooks used by Codex, Antigravity, and other non-Claude tools.

A fast-path trigger, `/github_kit <task>`, is also available — runbook at
`.agents/skills/github_kit/SKILL.md` — invoking it is itself the human's approval for the described
task, see "Non-negotiable behaviors" below. A companion trigger, `/github_kit_update` (runbook:
`.agents/skills/github_kit_update/SKILL.md`), refreshes this repo's local github-kit bootstrap
files from `pzoli6/github-kit@main` via a draft PR — use it when local files seem stale, not as
part of routine `/github_kit` runs.

## Non-negotiable behaviors for Gemini CLI specifically

- **Plan first, then stop — unless invoked via `/github_kit`.** For any non-trivial task, produce a
  plan and wait for the human to reply with `approve` before creating a branch,
  writing code, or running installer/update scripts. Don't treat a description of the problem as
  approval to implement. The one exception: if the human's message is itself `/github_kit <task>`,
  that invocation is the approval for `<task>` — proceed per `.agents/skills/github_kit/SKILL.md`
  instead of waiting for the separate phrase.
- **Update handoff files before running low on context.** If you're approaching a context/token
  limit mid-task, write your current state to `docs/ai/handoffs/issue-<number>.md` and update the
  Project's `Last Agent Update` and `Validation` fields *before* you stop — the next agent (Gemini
  CLI again, or a completely different tool) picks up from that file, not from re-reading the
  whole conversation.
- **Never merge a PR.** Open draft PRs, push updates, respond to review feedback — merging is
  always a human action.
- **Never push directly to the base or production branch**, and never run `git add -A` / `git add
  .` — stage explicit files only, per `AGENTS.md`.
- **Targeting the production branch needs a second, explicit `approve main`.** Plain `approve`
  only authorizes work against the configured base branch — never create a branch/PR aimed at the
  production branch, or push/merge the base branch into it, without that separate phrase from the
  human, and never without adding the required marker line to the PR body. See `AGENTS.md` →
  "Production-branch gate (`approve main`)".
- **Stop only at the listed gates.** Beyond plan approval and the production-branch gate above,
  `AGENTS.md` → "Stop-and-ask gates" is the complete, enumerated list of moments that need a human
  reply — anything not on that list is your judgment call, not a reason to pause.
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
approve
```

Fast path: `/github_kit <task>` is a pre-approved alternative entry point — the invocation itself is the approval for the described task, scoped to that task only. See `docs/ai/AGENT_WORKFLOW.md` → "Fast-path trigger: /github_kit".

Agents must not push to protected branches, merge PRs, modify secrets, use `git add .`, or claim validation passed unless validation actually ran.

Before stopping, losing context, or handing off to another agent, agents must update:
- `docs/ai/handoffs/issue-<number>.md`
- Project field: `Last Agent Update`
- Project field: `Validation`
<!-- END GITHUB-KIT UNIVERSAL WORKFLOW -->
