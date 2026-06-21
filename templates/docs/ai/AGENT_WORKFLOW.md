# AGENT_WORKFLOW.md — Detailed Workflow Specification

This is the detailed, phase-by-phase version of the lifecycle summarized in
[`../../AGENTS.md`](../../AGENTS.md). Read `AGENTS.md` and
[`PROJECT_CONFIG.md`](PROJECT_CONFIG.md) first — this file assumes both.

## Phase 1 — Task intake

- Read the user's request in full before doing anything else.
- Read `AGENTS.md` and `PROJECT_CONFIG.md` for this repo's rules and config.
- If a related issue already exists, read it and any linked handoff file in
  [`handoffs/`](handoffs/) before starting fresh — don't re-derive context that's already written
  down.
- If the request is ambiguous or has multiple reasonable approaches, ask before planning.

## Phase 2 — Plan review

- Produce a concrete plan: what will change, which files, what's explicitly out of scope.
- Set/leave the tracking item's `Status` at `Plan Review` (create the issue first if one doesn't
  exist yet — see Phase 3 — or note the plan directly in the conversation if no issue exists yet).
- **Stop and wait** for the human to reply `approve issue-to-pr-project`. Do not create branches,
  install dependencies, or write implementation code before this.

## Phase 3 — Issue and Project setup

- If no GitHub issue exists for this task yet, create one using
  `.github/ISSUE_TEMPLATE/agent_task.yml` (problem, context, approved plan, acceptance criteria,
  intended agent, risk, base branch).
- Add the issue to the configured GitHub Project with
  `scripts/project/project_add_item.sh <issue-url>`.
- Set `Status` to `Ready` with `scripts/project/project_set_status.sh <issue-url> Ready`.
- Set the `Agent`, `Area`, `Risk`, and `Base Branch` fields with
  `scripts/project/project_set_text.sh` / the status script as appropriate.

## Phase 4 — Branch and worktree

- Branch from the configured base branch, name it with the configured agent prefix (default
  `agent/`), e.g. `agent/issue-42-add-retry-logic`.
- Use an isolated worktree if this task may run concurrently with other agent sessions on the same
  repo.
- Set `Status` to `In Progress` and update the `Branch` field.

## Phase 5 — Implementation

- Implement only what the approved plan describes (see "Scope rules" in `AGENTS.md`).
- Commit incrementally with explicit `git add <file>` staging — never `git add -A`/`git add .`.
- If you hit a blocker you can't resolve, set `Status` to `Blocked`, write why in the issue, and
  write a handoff file (Phase 8) before stopping.

## Phase 6 — Validation

- Run every command listed under "Validation commands" in `PROJECT_CONFIG.md`.
- Record the true outcome in the Project's `Validation` field: `Passed`, `Failed`, `Partial`,
  `Manual Required`, or `Not Applicable` — never `Passed` unless it actually ran and passed.
- If something can't be validated in this environment (e.g. needs a live service, a UI you can't
  drive), say so explicitly rather than claiming it works.

## Phase 7 — Commit and PR

- Push the branch, open a **draft PR** targeting the configured base branch using
  `.github/PULL_REQUEST_TEMPLATE.md` — fill in every section (summary, linked issue, Project
  metadata, agent/tool used, Agent Run, area, risk, base branch, branch, handoff path, validation
  state, commands run, results, human review focus, known risks, follow-up items).
- Update the Project: `Status` → `In Review`, `PR URL`, `Last Agent Update`.

## Phase 8 — Review and continuation

- When a human requests changes, set `Status` to `Changes Requested`, address the feedback, push
  updates, and set `Status` back to `In Review` once done.
- Whenever you stop mid-task — context limit, end of session, explicit handoff to another agent or
  tool — write/update `handoffs/issue-<number>.md` with: current state, what's done, what's left,
  open decisions/blockers, and the exact next step. Update `Last Agent Update` and `Validation`.
  This is what lets a different agent (or a different AI tool entirely) pick the task back up.

## Phase 9 — Completion

- A human merges the PR — no agent merges its own or anyone else's PR.
- Once merged/closed, set `Status` to `Done` (or `Cancelled` if the work was abandoned).
- Optionally remove or archive the task's handoff file once the Project item is `Done`.
