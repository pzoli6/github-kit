---
name: issue-to-pr-project
description: Run the full issue-to-PR-Project workflow for a task in this repository — plan, get approval, create the issue, track it on the GitHub Project, branch, implement, validate, open a draft PR, and write handoff files. Use whenever a user asks to implement a feature/fix that should go through the standard agent workflow, or explicitly invokes this skill.
---

# issue-to-pr-project

Use this skill to take a task from "user asked for X" through to a reviewable draft PR, fully
tracked on the GitHub Project, following this repo's `AGENTS.md` and `docs/ai/AGENT_WORKFLOW.md`.
This skill is a runbook for those files, not a replacement — if anything here conflicts with
`AGENTS.md`, `AGENTS.md` wins.

## Before you start

Read, in this repo:

- `AGENTS.md` — universal rules (approval boundary, Project status protocol/fields, branch/commit/
  validation/handoff/security/scope/PR rules, human authority)
- `docs/ai/PROJECT_CONFIG.md` — this repo's Project number, base branch, validation commands,
  forbidden files
- `docs/ai/AGENT_WORKFLOW.md` — the detailed phase spec this skill walks through

## Steps

1. **Plan.** Write a concrete plan: files touched, approach, explicit non-goals. Do not implement
   yet.
2. **Stop for approval.** Wait for the human to reply exactly:
   ```text
   approve issue-to-pr-project
   ```
   Do not proceed past this point without it.
3. **Create the issue.** Use `.github/ISSUE_TEMPLATE/agent_task.yml` fields (problem, context,
   approved plan, acceptance criteria, intended agent, risk, base branch).
4. **Add it to the Project and set status.**
   ```bash
   scripts/project/project_add_item.sh <issue-url>
   scripts/project/project_set_status.sh <issue-url> Ready
   ```
5. **Branch.** Create `agent/<short-description>` from the configured base branch. Use an
   isolated worktree if other agents may be working concurrently. Set status to `In Progress`.
6. **Implement.** Only what the approved plan covers. Stage explicit files; never `git add -A` /
   `git add .`.
7. **Validate.** Run every command in `docs/ai/PROJECT_CONFIG.md` → Validation commands. Record
   the real outcome — `Passed`, `Failed`, `Partial`, `Manual Required`, or `Not Applicable`.
8. **Open a draft PR.** Target the configured base branch, fill in
   `.github/PULL_REQUEST_TEMPLATE.md` completely. Set status to `In Review`, set `PR URL`.
9. **Handle review.** On change requests, set status to `Changes Requested`, fix, set back to
   `In Review`.
10. **Hand off if you stop early.** Before running out of context or ending the session mid-task,
    write `docs/ai/handoffs/issue-<number>.md` with current state / what's left / next step, and
    update `Last Agent Update` + `Validation` on the Project item.
11. **Completion is human-driven.** A human merges. After merge/close, set status to `Done`
    (or `Cancelled` if abandoned).

## Hard rules

- Never implement before the approval phrase.
- Never merge a PR.
- Never push directly to the production branch.
- Never commit `docs/ai/PROJECT_CONFIG.env` or any secret.
