---
name: issue-to-pr-project
description: Run the full issue-to-PR-Project workflow for a task in this repository — plan, get approval, create the issue, track it on the GitHub Project, branch, implement, validate, open a draft PR, and write handoff files. Use whenever a user asks to implement a feature/fix that should go through the standard agent workflow, or explicitly invokes this skill.
---

# issue-to-pr-project

Use this skill to take a task from "user asked for X" through to a reviewable draft PR, fully
tracked on the GitHub Project, following this repo's `AGENTS.md` and `docs/ai/AGENT_WORKFLOW.md`.
This skill is a runbook for those files, not a replacement — if anything here conflicts with
`AGENTS.md`, `AGENTS.md` wins.

## Solo mode

Check `docs/ai/PROJECT_CONFIG.md` → "Solo mode" first (default `auto` — active while no real
GitHub Project is configured). When active, skip the issue-creation step for pre-approved
iterations and every Project-field / `sync_project_fields.sh` step in this runbook, drop the
`Closes #` line when no issue exists, and write handoff files only when actually stopping
mid-task — the flow collapses to plan → approval → branch/worktree → implement → validate →
draft PR. Approval gates and all git/PR safety rules apply unchanged.

## Before you start

Read, in this repo:

- `AGENTS.md` — universal rules (approval boundary, Project status protocol/fields, branch/commit/
  validation/handoff/security/scope/PR rules, relationships/notifications policy, human authority)
- `docs/ai/PROJECT_CONFIG.md` — this repo's Project number, base branch, validation commands,
  metadata defaults (assignee/labels/milestone/reviewer), forbidden files
- `docs/ai/AGENT_WORKFLOW.md` — the detailed phase spec this skill walks through

## If resuming existing work

If this task continues an issue that already exists (not a fresh task), first run:
```bash
scripts/project/check_resume_safety.sh --issue <issue-number> --agent "<name>"
```
- `STOP: ...` (exit 2) — the issue is closed, or its linked PR is already merged/closed. Don't
  resume; tell the user.
- `ACTIVE_ELSEWHERE: ...` (exit 3) — another agent's claim still looks fresh. Report which agent
  and when, instead of duplicating work.
- `SAFE_TO_PROCEED` (exit 0) — continue per `docs/ai/AGENT_WORKFLOW.md` → "Resuming stashed work".

## Steps

1. **Plan.** Write a concrete plan: files touched, approach, explicit non-goals. Do not implement
   yet. If the task naturally decomposes into independent pieces, propose that breakdown as a
   numbered list instead of picking one — see "Splitting a task into sub-tasks" in `AGENTS.md`.
2. **Stop for approval.** Wait for the human to reply exactly:
   ```text
   approve
   ```
   If you proposed a numbered sub-task breakdown in step 1, also accept `approve all` (run every
   sub-task in sequence without stopping again) or `approve 1,3` (only the listed numbers). Do not
   proceed past this point without one of these replies.
3. **Create the issue with full metadata.**
   ```bash
   scripts/project/create_agent_issue.sh --title "<title>" --body-file <path> \
     --agent "<name>" --area "<area>" --risk "<Low|Medium|High>" --environment "<env>" \
     [--parent <parent-issue>]
   ```
   Always pass `--agent`/`--area`/`--risk`/`--environment` explicitly — don't rely on the
   `AGENT_DEFAULT_*` fallback in `docs/ai/PROJECT_CONFIG.env` to fill them in. This fills
   assignee/labels/milestone from `docs/ai/PROJECT_CONFIG.env` defaults (never leaves them blank),
   adds the issue to the configured Project, sets `Status` to `Ready`, and sets `Agent`/`Area`/
   `Risk`/`Environment` itself — no separate `project_add_item.sh`/`project_set_status.sh`/
   `project_set_text.sh` call needed. Pass `--parent <parent-issue>` when this issue is one of an
   `approve all`/`approve 1,3` sub-task breakdown, to link it as a real GitHub sub-issue.
4. **Declare relationships.** If this task is genuinely blocked by, blocks, or is part of another
   issue, say so in the issue body (`Blocked by #12`, `Blocks #15`, `Part of #10`). Otherwise write
   `Relationships: none declared` — never leave the question unaddressed. See `AGENTS.md` →
   "GitHub relationships and development links".
5. **Create the worktree and publish the branch.**
   ```bash
   worktree="$(scripts/project/publish_agent_branch.sh --issue <issue-url> --slug <short-description>)"
   cd "$worktree"
   ```
   Run this **before writing any implementation code.** Every task runs in its own git worktree —
   the script forks from `origin/<base>` (never a stale local tip), creates a *real* worktree (own
   checkout + `.git` file), pushes the branch, comments the link on the issue, sets `Status` to
   `In Progress` and the `Branch`/`Base Branch` fields, and prints the worktree path (captured
   above). **`cd` into it and read its `WORKTREE.md` first** — that's the base branch, unique dev
   port, verify commands, and auth notes you'd otherwise reverse-engineer. See `AGENTS.md` →
   "Branch and worktree rules".
6. **Optional: pre-PR Development link.** If you want the branch visible under the issue's
   "Development" sidebar section *before* a PR exists, use `gh issue develop --name
   <agent/branch-name>` **instead of** step 5 — but then create a worktree for that branch yourself
   (`git worktree add <dir> <agent/branch-name>`) to stay worktree-isolated. In the common case,
   skip this: step 15's PR body auto-links Development once the PR opens.
7. **Implement** in the worktree. Only what the approved plan covers. Stage explicit files; never
   `git add -A` / `git add .`.
8. **Mark implementation started.**
   ```bash
   scripts/project/sync_project_fields.sh implementation_started <issue-url> "<short note>"
   ```
9. **Commit and push incrementally.** Stage explicit files; never `git add -A` / `git add .`. Push
   regularly as you go — don't let commits pile up local-only until the very end.
10. **If blocked,** run `scripts/project/sync_project_fields.sh blocked <issue-url> "<reason>"`,
    write the reason in the issue or handoff file, and stop.
11. **Validate.** Run every command in `docs/ai/PROJECT_CONFIG.md` → Validation commands.
12. **Record the validation outcome.**
    ```bash
    scripts/project/sync_project_fields.sh validation_passed <issue-url>
    # or: validation_failed | validation_partial | validation_manual | validation_na
    ```
    Never record `validation_passed` unless it actually ran and passed.
13. **Create/update the handoff file.** Write or update `docs/ai/handoffs/issue-<number>.md` with
    current state — do this whether or not you're about to stop, so it's never stale. If a PR
    already exists for this issue (a re-handoff after step 15, e.g. on review feedback or a
    paused session), also mirror it onto the PR:
    ```bash
    scripts/project/post_handoff_comment.sh --pr <pr-url> --file docs/ai/handoffs/issue-<number>.md --agent "<name>"
    ```
    This updates its own prior comment in place (by marker), so re-running it every time is
    expected, not noisy.
14. **Record the handoff update.**
    ```bash
    scripts/project/sync_project_fields.sh handoff_updated <issue-url> "<short note>"
    ```
15. **Open a draft PR with full metadata.**
    ```bash
    scripts/project/create_agent_pr.sh --issue <issue-url> --base <base-branch> --head <branch> \
      --title "<title>" --body-file <path> --agent "<name>" --area "<area>" \
      --risk "<Low|Medium|High>" --environment "<env>" --agent-run "<url>" --handoff "<note>"
    ```
    Pass `--agent`/`--area`/`--risk`/`--environment` explicitly (same values as step 3), plus
    `--agent-run` and `--handoff` for this PR. This fills assignee/labels/milestone/reviewer from
    defaults, injects `Closes #<n>` into the body if missing, fills in
    `.github/PULL_REQUEST_TEMPLATE.md` sections by hand before passing `--body-file`, adds the PR
    to the Project, comments the PR URL on the issue, and sets the issue's `Status` to `In Review`,
    `PR URL`, `Agent`, `Area`, `Risk`, `Environment`, `Agent Run`, and `Handoff` itself. See
    "Field-completeness checklist" in `AGENTS.md` → "Project fields" for the full mapping.
16. **Confirm notifications are covered.** Step 15's `--assignee`/`--reviewer` is what notifies
    people — there's no separate subscribe step (`gh` has none). If neither is configured for this
    repo, `@mention` the relevant person directly in the issue/PR body instead of assuming they'll
    see it. See `AGENTS.md` → "Notifications and participation".
17. **Stop for human review.** Do not merge. Report the PR link and end the turn — don't look at,
    wait for, or mention CI. A preview PR normally shows no checks at all (CI runs only for
    production-bound changes or an explicit human dispatch), and that absence is by design, not a
    failure to report. See `AGENTS.md` → "CI expectations — don't chase checks".
18. **On change requests:**
    ```bash
    scripts/project/sync_project_fields.sh changes_requested <issue-url>
    ```
    Address the feedback, push the updates, then run
    `scripts/project/sync_project_fields.sh pr_opened <issue-url> <pr-url>` to move `Status` back
    to `In Review`.
19. **Completion is human-driven.** A human merges the PR — no agent merges its own or anyone
    else's.
20. **On merge, clean up after yourself.**
    ```bash
    scripts/project/cleanup_merged_branches.sh --branch <branch>
    ```
    Removes the task's worktree, deletes the local branch, and closes the linked issue (Project
    `Status` → `Done` plus `gh issue close`) — but only when the merge is real and nothing unsaved
    would be lost. A `SKIPPED` line means leave it alone and read why, not force-remove it. Run it
    from outside the task's own worktree (e.g. the main checkout) — it can't remove the worktree
    you're standing in. See `AGENTS.md` → "Branch and worktree rules" → "Worktree + branch + issue
    cleanup after merge".
21. **If the work was abandoned** (not merged), run
    `scripts/project/sync_project_fields.sh cancelled <issue-url>` instead, and remove the worktree
    by hand with `git worktree remove <path>`.

## Hard rules

- Never implement before the approval phrase.
- Never leave an agent branch local-only — push it (step 5) before writing implementation code.
- Never leave issue/PR sidebar metadata (assignee, labels, milestone) blank when
  `docs/ai/PROJECT_CONFIG.env` has a default configured — use `create_agent_issue.sh`/
  `create_agent_pr.sh`, not raw `gh issue create`/`gh pr create`.
- Never omit `--agent`/`--area`/`--risk`/`--environment` from `create_agent_issue.sh`/
  `create_agent_pr.sh` — a blank Project metadata field after either script ran is a bug in this
  workflow, not expected behavior.
- Never leave the relationships question unaddressed — declare a real one or write
  `Relationships: none declared`.
- Never merge a PR.
- Never push directly to the production branch.
- Never commit `docs/ai/PROJECT_CONFIG.env` or any secret.
