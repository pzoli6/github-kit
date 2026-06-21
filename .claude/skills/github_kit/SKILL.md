---
name: github_kit
description: Fast-path variant of issue-to-pr-project — run the full issue-to-PR-Project workflow for a task, treating the /github_kit invocation itself as the human's approval for that task instead of waiting for a separate "approve issue-to-pr-project" reply. Use when a user explicitly invokes /github_kit <task> with a task description.
---

# github_kit

This is the fast-path variant of [`issue-to-pr-project`](../issue-to-pr-project/SKILL.md). It
takes a task from "user typed `/github_kit <task>`" through to a reviewable draft PR, fully
tracked on the GitHub Project, following this repo's `AGENTS.md` and `docs/ai/AGENT_WORKFLOW.md`.

**The only difference from `issue-to-pr-project` is step 2.** Everything else — issue creation,
Project tracking, branching, implementation, validation, draft PR, handoff, review, completion, and
every hard rule — is identical. If anything here conflicts with `AGENTS.md`, `AGENTS.md` wins.

## Before you start

Read, in this repo:

- `AGENTS.md` — universal rules (approval boundary, Project status protocol/fields, branch/commit/
  validation/handoff/security/scope/PR rules, human authority)
- `docs/ai/PROJECT_CONFIG.md` — this repo's Project number, base branch, validation commands,
  forbidden files
- `docs/ai/AGENT_WORKFLOW.md` — the detailed phase spec this skill walks through, including the
  "Fast-path trigger: /github_kit" section

## Steps

1. **Plan.** Write a concrete plan: files touched, approach, explicit non-goals. Still produce this
   for transparency even though you won't stop and wait for it to be approved separately — the
   human already approved by invoking `/github_kit` with the task description.
2. **Treat the invocation as approval — do not stop.** The literal `/github_kit <task>` invocation
   *is* the human's approval for the task described in `<task>`, scoped strictly to that
   description. Proceed straight to step 3 without waiting for `approve issue-to-pr-project`. If
   you discover mid-task that the work needs to expand beyond what `<task>` described, stop and use
   the normal approval gate (`approve issue-to-pr-project`) for the expanded part only — the
   auto-approval never covers scope it didn't describe.
3. **Create the issue.** Use `.github/ISSUE_TEMPLATE/agent_task.yml` fields (problem, context,
   approved plan, acceptance criteria, intended agent, risk, base branch). Note in the issue body
   that approval came via direct `/github_kit` invocation rather than a separate approval reply.
4. **Add it to the Project and set status.**
   ```bash
   scripts/project/project_add_item.sh <issue-url>
   scripts/project/project_set_status.sh <issue-url> Ready
   ```
5. **Branch.** Create `agent/<short-description>` from the configured base branch. Use an
   isolated worktree if other agents may be working concurrently. Set status to `In Progress`.
6. **Implement.** Only what `<task>` describes. Stage explicit files; never `git add -A` /
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

- Never implement beyond the scope `<task>` described without falling back to the normal approval
  gate for the extra scope.
- Never merge a PR.
- Never push directly to the production branch.
- Never commit `docs/ai/PROJECT_CONFIG.env` or any secret.
- Never invoke this skill for a repo-specific or one-off hack — it must stay generic, same as
  `issue-to-pr-project`.
- This skill does not replace `issue-to-pr-project` — both remain available; use whichever the
  human invoked.
