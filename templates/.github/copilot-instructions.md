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

- Plan first and wait for a human to reply `approve` before branching or
  implementing — unless the task itself was given as `/github_kit <task description>`, in which
  case that invocation is itself the approval for `<task>`; see `docs/ai/AGENT_WORKFLOW.md` →
  "Fast-path trigger: /github_kit" for the scope and limits of that exception. If a task naturally
  decomposes into independent pieces, propose that breakdown as a numbered list and accept
  `approve all` (run every sub-task in sequence) or `approve 1,3` (only the listed numbers) — see
  `AGENTS.md` → "Splitting a task into sub-tasks".
- Create the issue and PR with `scripts/project/create_agent_issue.sh`/`create_agent_pr.sh`,
  always passing `--agent`/`--area`/`--risk`/`--environment` explicitly (plus `--parent
  <parent-issue>` for a sub-task, `--agent-run`/`--handoff` on the PR) — never leave those Project
  fields blank. Open PRs as drafts targeting the base branch from `docs/ai/PROJECT_CONFIG.md`.
  Never merge.
- Keep the Project's `Status`, `Validation`, and `Last Agent Update` fields current as you work.
- Declare real issue/PR relationships in the body (`Blocked by #N`, `Blocks #N`, `Part of #N`);
  otherwise write `Relationships: none declared`. See `AGENTS.md` → "GitHub relationships and
  development links".
- Before stopping mid-task, write `docs/ai/handoffs/issue-<number>.md` so another agent (or a
  human) can continue without re-deriving context.
- This repo's reusable workflows auto-track `pzoli6/github-kit@main` (the always-latest channel) —
  central workflow changes apply on the next run automatically. Local bootstrap files (this file,
  `AGENTS.md`, skills, Cursor rules) only refresh when `/github_kit_update` or
  `update-github-kit.sh`/`.ps1` is run explicitly; don't assume they're current with `main`.
