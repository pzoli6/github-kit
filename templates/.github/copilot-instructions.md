# GitHub Copilot coding agent instructions

Before doing anything else, read, in order:

1. [`AGENTS.md`](../AGENTS.md) — universal rules: approval boundary, production-branch gate,
   stop-and-ask gates, issue-to-PR workflow, Project status protocol and fields,
   branch/commit/validation/handoff/security/scope/PR rules, human authority.
2. [`docs/ai/PROJECT_CONFIG.md`](../docs/ai/PROJECT_CONFIG.md) — this repo's Project number, base
   branch, validation commands, and forbidden files.
3. [`docs/ai/AGENT_WORKFLOW.md`](../docs/ai/AGENT_WORKFLOW.md) — the workflow spec: a
   happy-path checklist (task intake → plan review → issue/Project setup → branch/worktree →
   implementation → validation → commit/PR → review/continuation → completion) plus an appendix
   read only when a section's trigger applies.

Follow that workflow exactly:

- Plan first and wait for a human to reply `approve` before branching or
  implementing — unless the task itself was given as `/github_kit <task description>`, in which
  case that invocation is itself the approval for `<task>`; see `docs/ai/AGENT_WORKFLOW.md` →
  "Fast-path trigger: /github_kit" for the scope and limits of that exception. If a task naturally
  decomposes into independent pieces, propose that breakdown as a numbered list and accept
  `approve all` (run every sub-task in sequence) or `approve 1,3` (only the listed numbers) — see
  `AGENTS.md` → "Splitting a task into sub-tasks". Plain `approve` never authorizes targeting the
  production branch directly — that needs a separate, explicit `approve main` plus the matching
  marker line in the PR body; see `AGENTS.md` → "Production-branch gate (`approve main`)". Beyond
  plan approval and that production-branch gate, `AGENTS.md` → "Stop-and-ask gates" is the
  complete, enumerated list of moments that need a human reply — anything not on that list is your
  judgment call, not a reason to pause.
- Create the issue and PR with `scripts/project/create_agent_issue.sh`/`create_agent_pr.sh`,
  always passing `--agent`/`--area`/`--risk`/`--environment` explicitly (plus `--parent
  <parent-issue>` for a sub-task, `--agent-run`/`--handoff` on the PR) — never leave those Project
  fields blank. Open PRs as drafts targeting the base branch from `docs/ai/PROJECT_CONFIG.md`.
  Never merge.
- Work in a dedicated git worktree. Create it with `scripts/project/publish_agent_branch.sh`
  (forks a real worktree from `origin/<base>`, prints its path), `cd` into that path, and read the
  `WORKTREE.md` it drops there before implementing — agents run this repo in parallel and must
  never share a working tree. See `AGENTS.md` → "Branch and worktree rules".
- After the PR merges, run `scripts/project/cleanup_merged_branches.sh --branch <branch>` to remove
  the worktree, delete the local branch, and close the linked issue — only when the merge is real
  and nothing unsaved would be lost (heed any `SKIPPED` line instead of forcing it).
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

## Manual Copilot use and the Actions budget

A human driving Copilot directly — assigning the coding agent to an issue or task, asking
`@copilot` to resolve a PR's merge conflicts or apply review feedback, requesting a Copilot code
review — is always their call and needs no `approve` phrase from this workflow; those aren't
agent-initiated actions. Be aware that coding-agent sessions execute as GitHub Actions workflow
runs in this repo and share the account's Actions budget with this repo's CI. If a session fails
to start because the Actions budget is exhausted, see `docs/ai/AGENT_WORKFLOW.md` → "Actions
budget and manual Copilot use": a human/billing admin can raise the budget (Settings → Billing
and licensing → Budgets and alerts), pause the kit's workflows by setting the repository Actions
variable `KIT_ACTIONS_PAUSED` to `true` to stop the drain, or have conflicts resolved locally,
which consumes no Actions minutes. Never change billing, budget, or Actions settings yourself.
