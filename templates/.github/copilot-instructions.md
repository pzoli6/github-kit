# GitHub Copilot coding agent instructions

Before doing anything else, read, in order:

1. [`AGENTS.md`](../AGENTS.md) — universal rules: approval boundary, issue-to-PR workflow, Project
   status protocol and fields, branch/commit/validation/handoff/security/scope/PR rules, human
   authority.
2. [`docs/ai/PROJECT_CONFIG.md`](../docs/ai/PROJECT_CONFIG.md) — this repo's Project number, base
   branch, validation commands, and forbidden files.
3. [`docs/ai/AGENT_WORKFLOW.md`](../docs/ai/AGENT_WORKFLOW.md) — the detailed phase-by-phase
   workflow (task intake → plan review → issue/Project setup → branch/worktree → implementation →
   validation → commit/PR → review/continuation → completion).

Follow that workflow exactly:

- Plan first and wait for a human to reply `approve issue-to-pr-project` before branching or
  implementing.
- Open PRs as drafts targeting the base branch from `docs/ai/PROJECT_CONFIG.md`. Never merge.
- Keep the Project's `Status`, `Validation`, and `Last Agent Update` fields current as you work.
- Before stopping mid-task, write `docs/ai/handoffs/issue-<number>.md` so another agent (or a
  human) can continue without re-deriving context.
