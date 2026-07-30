---
name: github_kit
description: Fast-path variant of issue-to-pr-project — run the full issue-to-PR-Project workflow for a task, treating the /github_kit invocation itself as the human's approval for that task instead of waiting for a separate "approve" reply. Use when a user explicitly invokes /github_kit <task> with a task description.
---

# github_kit

This is the fast-path variant of [`issue-to-pr-project`](../issue-to-pr-project/SKILL.md). It
takes a task from "user typed `/github_kit <task>`" through to a reviewable draft PR, fully
tracked on the GitHub Project, following this repo's `AGENTS.md` and `docs/ai/AGENT_WORKFLOW.md`.

**The only behavioral difference from `issue-to-pr-project` is the approval step.** Everything
else — issue creation, Project tracking, branching, implementation, validation, draft PR, handoff,
review, completion, and every hard rule — is identical. If anything here conflicts with
`AGENTS.md`, `AGENTS.md` wins.

## Before you start

Use local repo instructions and docs first — they are this skill's source of truth and work with
zero network access:

- `AGENTS.md` — universal rules (approval boundary, Project status protocol/fields, branch/commit/
  validation/handoff/security/scope/PR rules, human authority)
- `docs/ai/PROJECT_CONFIG.md` — this repo's Project number, base branch, validation commands,
  forbidden files, and `github-kit ref`/`github-kit update mode`
- `docs/ai/AGENT_WORKFLOW.md` — the detailed phase spec this skill walks through, including the
  "Fast-path trigger: /github_kit" section

If `pzoli6/github-kit@main` is reachable (e.g. a local clone, or `gh api`/raw fetch access),
treat it as the latest central guidance and cross-check it against the local files above — but
never block on it. If central guidance is unavailable, continue on the local fallback instructions
without comment; network access is never required to run `/github_kit`. Local skill/Cursor-rule/
instruction files may lag behind `github-kit/main` until someone runs `/github_kit_update` or
`update-github-kit.sh`/`.ps1` — that staleness is expected, not an error condition.

## Steps

1. **Plan.** Write a concrete plan: files touched, approach, explicit non-goals. Still produce this
   for transparency even though you won't stop and wait for it to be approved separately — the
   human already approved by invoking `/github_kit` with the task description.
2. **Clean repo check.** Run `git status`. If the working tree is dirty with changes unrelated to
   this task, stop and ask before proceeding — auto-approval covers the task, not silently
   committing alongside someone else's in-progress work. A dirty tree that's clearly part of this
   same task (e.g. resuming after a pause) is fine; say so explicitly before continuing.
3. **Treat the invocation as approval — do not stop.** The literal `/github_kit <task>` invocation
   *is* the human's approval for the task described in `<task>`, scoped strictly to that
   description. Proceed straight to step 4 without waiting for `approve`. If
   you discover mid-task that the work needs to expand beyond what `<task>` described, stop and use
   the normal approval gate (`approve`) for the expanded part only — the
   auto-approval never covers scope it didn't describe. If `<task>` naturally decomposes into
   independent pieces that all stay within what was described, you may split it into multiple
   issues/PRs (note `Part of #<parent-issue>` in each body) without asking again — splitting alone
   doesn't expand scope. If a decomposition would expand scope, present it as a numbered breakdown
   and use the `approve all`/`approve 1,3` gate from `templates/AGENTS.md` → "Splitting a task into
   sub-tasks" for the extra scope only (this repo's own root `AGENTS.md` doesn't restate that
   section; it lives in the payload doc).
   **If `<task>` is a path to a spec file, this approval is conditional.** A path is not a task
   description — it delegates the scope boundary to a document, and that document is normally
   written by an agent rather than by the human who invoked the command. Treat
   `/github_kit implement <path>` as approval only when that file's front matter carries a
   human-set `status: approved` together with `approved-by` and `approved-on`. Any other value
   — `draft`, `ready`, or absent — means report the file as awaiting human review and implement
   nothing. Where the marker is present, the approved scope is that file's **Acceptance criteria**
   section and nothing beyond it.

4. **Create the issue.** Use `.github/ISSUE_TEMPLATE/agent_task.yml` fields (problem, context,
   approved plan, acceptance criteria, intended agent, risk, base branch). Note in the issue body
   that approval came via direct `/github_kit` invocation rather than a separate approval reply.
5. **Add it to the Project and set status.**
   ```bash
   scripts/project/project_add_item.sh <issue-url>
   scripts/project/project_set_status.sh <issue-url> Ready
   ```
6. **Branch.** Create `agent/<short-description>` from the configured base branch. Use an
   isolated worktree if other agents may be working concurrently. Set status to `In Progress`.
7. **Implement.** Only what `<task>` describes. Stage explicit files; never `git add -A` /
   `git add .`.
8. **Validate.** Run every command in `docs/ai/PROJECT_CONFIG.md` → Validation commands. Record
   the real outcome — `Passed`, `Failed`, `Partial`, `Manual Required`, or `Not Applicable`.
9. **Create/update the handoff file.** Write or update `docs/ai/handoffs/issue-<number>.md` with
   current state — do this whether or not you're about to stop, so it's never stale.
10. **Commit and push.** Stage explicit files; never `git add -A` / `git add .`.
11. **Open a draft PR.** Target the configured base branch, fill in
    `.github/PULL_REQUEST_TEMPLATE.md` completely. Set status to `In Review`, set `PR URL`.
12. **Stop for human review.** Do not merge. Report the PR link and end the turn — don't look at,
    wait for, or mention CI; a PR with no checks is expected here (see `AGENTS.md` → "CI
    expectations — don't chase checks" in an installed repo, and the same rule in
    `templates/AGENTS.md`). On change requests, set status to `Changes Requested`, fix, set back
    to `In Review`.
13. **Completion is human-driven.** A human merges. After merge/close, set status to `Done`
    (or `Cancelled` if abandoned).

For refreshing this repo's *local* github-kit bootstrap files (skills, Cursor rules, instructions)
from `github-kit/main`, use the separate `/github_kit_update` command/skill — that's a distinct,
explicit, opt-in operation, not something this skill does as a side effect.

## Hard rules

- Never implement beyond the scope `<task>` described without falling back to the normal approval
  gate for the extra scope.
- Never write a human-approval marker (`status: approved`, `approved-by`, `approved-on`) into a
  spec file — not one you authored, not one you were handed. That marker is the human's signature;
  an agent that writes it is forging its own approval.
- Never proceed past a dirty, unrelated working tree without asking first.
- Never merge a PR.
- Never push directly to the production branch.
- Never commit `docs/ai/PROJECT_CONFIG.env` or any secret.
- Never invoke this skill for a repo-specific or one-off hack — it must stay generic, same as
  `issue-to-pr-project`.
- This skill does not replace `issue-to-pr-project` — both remain available; use whichever the
  human invoked.
- Never require network access to complete this skill — `pzoli6/github-kit@main` is consulted
  opportunistically, not mandatorily.
