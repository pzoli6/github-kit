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
  validation/handoff/security/scope/PR rules, relationships/notifications policy, human authority)
- `docs/ai/PROJECT_CONFIG.md` — this repo's Project number, base branch, validation commands,
  metadata defaults (assignee/labels/milestone/reviewer), forbidden files
- `docs/ai/AGENT_WORKFLOW.md` — the detailed phase spec this skill walks through

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
5. **Publish the agent branch immediately.**
   ```bash
   scripts/project/publish_agent_branch.sh --issue <issue-url> --slug <short-description>
   ```
   Run this **before writing any implementation code.** It branches from the configured base
   branch, pushes to `origin` right away — the branch is never local-only — comments the branch
   link on the issue, sets `Status` to `In Progress`, and sets the `Branch` field, all in one call.
6. **Optional: pre-PR Development link.** If you want the branch visible under the issue's
   "Development" sidebar section *before* a PR exists, use `gh issue develop --name
   <agent/branch-name> [--branch-repo <owner/repo>]` **instead of** step 5 — the two are
   alternatives, not complementary, since `gh issue develop` creates the branch itself. In the
   common case, skip this: step 15's PR body auto-links Development once the PR opens.
7. **Implement.** Only what the approved plan covers. Stage explicit files; never `git add -A` /
   `git add .`.
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
    current state — do this whether or not you're about to stop, so it's never stale.
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
17. **Stop for human review.** Do not merge.
18. **On change requests:**
    ```bash
    scripts/project/sync_project_fields.sh changes_requested <issue-url>
    ```
    Address the feedback, push the updates, then run
    `scripts/project/sync_project_fields.sh pr_opened <issue-url> <pr-url>` to move `Status` back
    to `In Review`.
19. **Completion is human-driven.** A human merges the PR — no agent merges its own or anyone
    else's.
20. **Record completion.**
    ```bash
    scripts/project/sync_project_fields.sh done <issue-url>
    # or: cancelled <issue-url>   (if the work was abandoned)
    ```

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
