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

## Solo mode

Check `docs/ai/PROJECT_CONFIG.md` → "Solo mode" first (default `auto` — active while no real
GitHub Project is configured). When active, skip the issue-creation step for pre-approved
iterations and every Project-field / `sync_project_fields.sh` step in this runbook, drop the
`Closes #` line when no issue exists, and write handoff files only when actually stopping
mid-task — the flow collapses to plan → approval → branch/worktree → implement → validate →
draft PR. Approval gates and all git/PR safety rules apply unchanged.

## Before you start

Use local repo instructions and docs first — they are this skill's source of truth and work with
zero network access:

- `AGENTS.md` — universal rules (approval boundary, Project status protocol/fields, branch/commit/
  validation/handoff/security/scope/PR rules, relationships/notifications policy, human authority)
- `docs/ai/PROJECT_CONFIG.md` — this repo's Project number, base branch, validation commands,
  metadata defaults (assignee/labels/milestone/reviewer), forbidden files, and `github-kit ref`/
  `github-kit update mode`
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
   issues/PRs (linked with `--parent`, step 4) without asking again — splitting alone doesn't
   expand scope. If a decomposition would expand scope, present it as a numbered breakdown and use
   the `approve all`/`approve 1,3` gate from `AGENTS.md` → "Splitting a task into sub-tasks" for the
   extra scope only.
   **If `<task>` is a path to a spec file, this approval is conditional.** A path is not a task
   description — it delegates the scope boundary to a document, and that document is normally
   written by an agent rather than by the human who invoked the command. Treat
   `/github_kit implement <path>` as approval only when that file's front matter carries a
   human-set `status: approved` together with `approved-by` and `approved-on`. Any other value
   — `draft`, `ready`, or absent — means report the file as awaiting human review and implement
   nothing. Where the marker is present, the approved scope is that file's **Acceptance criteria**
   section and nothing beyond it. If the repo ships a verification command for these markers, run
   it first and treat a failure as "not approved" — a marker that cannot be re-checked against a
   recorded human action is just text, and text is exactly what you can write yourself.

4. **Create the issue with full metadata.**
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
   `project_set_text.sh` call needed. Pass `--parent <parent-issue>` when this issue is one of a
   sub-task breakdown.
5. **Declare relationships.** If this task is genuinely blocked by, blocks, or is part of another
   issue, say so in the issue body (`Blocked by #12`, `Blocks #15`, `Part of #10`). Otherwise write
   `Relationships: none declared` — never leave the question unaddressed. See `AGENTS.md` →
   "GitHub relationships and development links".
6. **Create the worktree and publish the branch.**
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
7. **Optional: pre-PR Development link.** If you want the branch visible under the issue's
   "Development" sidebar section *before* a PR exists, use `gh issue develop --name
   <agent/branch-name>` **instead of** step 6 — but then create a worktree for that branch yourself
   (`git worktree add <dir> <agent/branch-name>`) to stay worktree-isolated. In the common case,
   skip this: step 16's PR body auto-links Development once the PR opens.
8. **Implement** in the worktree. Only what `<task>` describes. Stage explicit files; never
   `git add -A` / `git add .`.
9. **Mark implementation started.**
   ```bash
   scripts/project/sync_project_fields.sh implementation_started <issue-url> "<short note>"
   ```
10. **Commit and push incrementally.** Stage explicit files; never `git add -A` / `git add .`. Push
    regularly as you go — don't let commits pile up local-only until the very end.
11. **If blocked,** run `scripts/project/sync_project_fields.sh blocked <issue-url> "<reason>"`,
    write the reason in the issue or handoff file, and stop.
12. **Validate.** Run every command in `docs/ai/PROJECT_CONFIG.md` → Validation commands.
13. **Record the validation outcome.**
    ```bash
    scripts/project/sync_project_fields.sh validation_passed <issue-url>
    # or: validation_failed | validation_partial | validation_manual | validation_na
    ```
    Never record `validation_passed` unless it actually ran and passed.
14. **Create/update the handoff file.** Write or update `docs/ai/handoffs/issue-<number>.md` with
    current state — do this whether or not you're about to stop, so it's never stale.
15. **Record the handoff update.**
    ```bash
    scripts/project/sync_project_fields.sh handoff_updated <issue-url> "<short note>"
    ```
16. **Open a draft PR with full metadata.**
    ```bash
    scripts/project/create_agent_pr.sh --issue <issue-url> --base <base-branch> --head <branch> \
      --title "<title>" --body-file <path> --agent "<name>" --area "<area>" \
      --risk "<Low|Medium|High>" --environment "<env>" --agent-run "<url>" --handoff "<note>"
    ```
    Pass `--agent`/`--area`/`--risk`/`--environment` explicitly (same values as step 4), plus
    `--agent-run` and `--handoff` for this PR. This fills assignee/labels/milestone/reviewer from
    defaults, injects `Closes #<n>` into the body if missing, fills in
    `.github/PULL_REQUEST_TEMPLATE.md` sections by hand before passing `--body-file`, adds the PR
    to the Project, comments the PR URL on the issue, and sets the issue's `Status` to `In Review`,
    `PR URL`, `Agent`, `Area`, `Risk`, `Environment`, `Agent Run`, and `Handoff` itself. See
    "Field-completeness checklist" in `AGENTS.md` → "Project fields" for the full mapping.
17. **Confirm notifications are covered.** Step 16's `--assignee`/`--reviewer` is what notifies
    people — there's no separate subscribe step (`gh` has none). If neither is configured for this
    repo, `@mention` the relevant person directly in the issue/PR body instead of assuming they'll
    see it. See `AGENTS.md` → "Notifications and participation".
18. **Stop for human review.** Do not merge. Report the PR link and end the turn — don't look at,
    wait for, or mention CI. A preview PR normally shows no checks at all (CI runs only for
    production-bound changes or an explicit human dispatch), and that absence is by design, not a
    failure to report. See `AGENTS.md` → "CI expectations — don't chase checks".
19. **On change requests:**
    ```bash
    scripts/project/sync_project_fields.sh changes_requested <issue-url>
    ```
    Address the feedback, push the updates, then run
    `scripts/project/sync_project_fields.sh pr_opened <issue-url> <pr-url>` to move `Status` back
    to `In Review`.
20. **Completion is human-driven.** A human merges the PR — no agent merges its own or anyone
    else's.
21. **On merge, clean up after yourself.**
    ```bash
    scripts/project/cleanup_merged_branches.sh --branch <branch>
    ```
    Removes the task's worktree, deletes the local branch, and closes the linked issue (Project
    `Status` → `Done` plus `gh issue close`) — but only when the merge is real and nothing unsaved
    would be lost. A `SKIPPED` line means leave it alone and read why, not force-remove it. Run it
    from outside the task's own worktree (e.g. the main checkout). If the work was abandoned
    instead, run `scripts/project/sync_project_fields.sh cancelled <issue-url>` and remove the
    worktree by hand (`git worktree remove <path>`). See `AGENTS.md` → "Branch and worktree rules"
    → "Worktree + branch + issue cleanup after merge".
22. **Local bootstrap refresh is separate.** Refreshing this repo's *local* github-kit bootstrap
    files (skills, Cursor rules, instructions) from `github-kit/main` is the dedicated
    `/github_kit_update` command/skill's job — a distinct, explicit, opt-in operation, never a side
    effect of this skill.

## Hard rules

- Never implement beyond the scope `<task>` described without falling back to the normal approval
  gate for the extra scope.
- Never write a human-approval marker (`status: approved`, `approved-by`, `approved-on`) into a
  spec file on your own initiative — not one you authored, not one you were handed. That marker is
  the human's signature; an agent that writes it is forging its own approval. Recording one on
  explicit instruction is fine only where the repo can still verify it against a recorded human
  action; otherwise say so rather than writing an unverifiable marker.
- Never proceed past a dirty, unrelated working tree without asking first.
- Never leave an agent branch local-only — push it (step 6) before writing implementation code.
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
- Never invoke this skill for a repo-specific or one-off hack — it must stay generic, same as
  `issue-to-pr-project`.
- This skill does not replace `issue-to-pr-project` — both remain available; use whichever the
  human invoked.
- Never require network access to complete this skill — `pzoli6/github-kit@main` is consulted
  opportunistically, not mandatorily.
