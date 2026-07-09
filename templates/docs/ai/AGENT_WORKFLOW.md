# AGENT_WORKFLOW.md — Workflow Specification

This is the delivery workflow summarized in [`../../AGENTS.md`](../../AGENTS.md). Read `AGENTS.md`
and [`PROJECT_CONFIG.md`](PROJECT_CONFIG.md) first — this file assumes both.

**How to read this file:** the "Happy path" checklist below is the whole workflow for a normal
task — read it and go. Everything under "Appendix" is conditional: read a section only when its
trigger actually applies to your current situation (you hit a usage limit, you're resuming stashed
work, the human said `approve main`, …). Don't read the appendix front-to-back every session.

## Solo mode

Check `PROJECT_CONFIG.md` → "Solo mode" first. When solo mode is active (default `auto`: active
while `Project Sync enabled` is `false` or `GitHub Project number` is `TBD`), the checklist below
collapses — skip the struck-through ceremony and run only:

**plan → (approval) → branch/worktree → implement → validate → draft PR.**

Concretely: skip issue creation for pre-approved iterations (create one only when the human asks
or the task will outlive the session; drop the `Closes #` line when no issue exists), skip every
Project-field update (steps marked *[Project]* below), and write a handoff file only when actually
stopping mid-task — a task that ends at an open draft PR needs no handoff. All safety rails still
apply: `approve` / `approve main` gates, draft-first PRs, explicit staging, honest validation.

## Happy path

1. **Intake** — read the request in full, plus `AGENTS.md` and `PROJECT_CONFIG.md`. If a related
   issue exists, read it and any `handoffs/issue-<n>.md` before starting fresh (run
   `scripts/project/check_resume_safety.sh --issue <n> --agent "<name>"` first — see "Resuming
   stashed work"). Ambiguous request → ask before planning.
2. **Plan** — state what will change, which files, what's out of scope. **Stop and wait for
   `approve`** (skipped when invoked via `/github_kit <task>` — see appendix). *[Project]* set
   `Status: Plan Review`. `approve` never covers the production branch — that needs `approve
   main` (see appendix).
3. **Issue** *(skip in solo mode for pre-approved iterations)* — create it with
   `scripts/project/create_agent_issue.sh --title <t> --body-file <f> --agent <a> --area <ar>
   --risk <Low|Medium|High> --environment <e>` (structure per
   `.github/ISSUE_TEMPLATE/agent_task.yml`; `--parent <issue>` for sub-tasks). This one call also
   adds it to the Project and sets `Status: Ready` + `Agent`/`Area`/`Risk`/`Environment`.
4. **Branch + worktree** — `scripts/project/publish_agent_branch.sh --issue <n> --slug <short>`.
   It forks fresh from `origin/<base branch>`, creates a real worktree, pushes the branch, and
   prints the worktree path as its last line. **`cd` into that path**, confirm with
   `git rev-parse --show-toplevel`, and read the `WORKTREE.md` it dropped there (dev port,
   dev-server command, preview route, auth notes, key paths). *[Project]* this call also sets
   `Status: In Progress` + `Branch`/`Base Branch`. Worktree caveats → appendix "Worktree notes".
5. **Implement** — only what the approved plan describes. Stage explicit files
   (`git add <file>`), never `git add -A` / `git add .`. Blocked → *[Project]* `Status: Blocked`
   with the reason, write a handoff, stop.
6. **Validate** — run every command under "Validation commands" in `PROJECT_CONFIG.md`. Report
   the true outcome (`Passed`/`Failed`/`Partial`/`Manual Required`/`Not Applicable`) — never
   claim `Passed` for something that didn't run. *[Project]* record it in the `Validation` field.
7. **Draft PR** — push, then `scripts/project/create_agent_pr.sh --issue <n> --base <b> --head
   <h> --title <t> --body-file <f> --agent <a> --area <ar> --risk <r> --environment <e>
   [--agent-run <url>] [--handoff <note>]`, body per `.github/PULL_REQUEST_TEMPLATE.md` (omit
   sections that don't apply — see the template's own notes). *[Project]* this call also sets
   `Status: In Review` + `PR URL` and the metadata fields. Report the PR link and end the turn —
   don't babysit CI or subscribe to PR activity unless the human asked for that.
8. **Review feedback** — address it, push. *[Project]* `Status: Changes Requested` → back to
   `In Review`. Stopping mid-task for any reason → write `handoffs/issue-<n>.md` (state, done,
   left, blockers, exact next step) and mirror it with `scripts/project/post_handoff_comment.sh`
   — see "Pausing" sections in the appendix.
9. **Completion** — a human merges; never you. On learning of the merge:
   `scripts/project/cleanup_merged_branches.sh --branch <branch>` (worktree + local branch +
   issue close, with built-in safety checks — trust its `SKIPPED` reasons). Abandoned instead of
   merged → `scripts/project/sync_project_fields.sh cancelled <issue-url>` and remove the
   worktree by hand.

---

# Appendix — read only the section your situation triggers

## Fast-path trigger: /github_kit

*Trigger: the human's message is `/github_kit <task description>`.*

A pre-approved alternative entry point. It changes exactly one thing — **step 2's stop-and-wait**
— and nothing else:

- The invocation itself **is** the human's approval for `<task>`, scoped strictly to the
  description supplied. Still write a visible plan for transparency, but don't wait for a
  separate `approve`.
- The pre-approval covers only what `<task>` describes. Scope needs to grow mid-task → stop and
  fall back to the normal `approve` gate for the additional scope; pre-approval never expands on
  its own.
- Every other step is unchanged (in solo mode, the solo-collapsed version of every other step).
  An issue created for a `/github_kit` task should note that approval came via direct invocation.
- Per-agent entry points: `.claude/commands/github_kit.md` (runbook:
  `.claude/skills/github_kit/SKILL.md`), the generic `.agents/skills/github_kit/SKILL.md`, and
  `.cursor/rules/github-kit-command.mdc`. Any agent without an adapter recognizes the trigger
  from this section and `AGENTS.md` directly.
- `/github_kit` runs entirely from local files and never requires network access — distinct from
  the reusable workflows' auto-tracking of `pzoli6/github-kit@main`.

## Production-branch gate: approve main

*Trigger: any branch/PR would target the production branch directly, or the base branch would be
pushed/merged into it.*

Plain `approve` (and `/github_kit`'s pre-approval) only ever covers the configured base branch.
Targeting the production branch requires a second, explicit phrase from the human:

```text
approve main
```

(Substitute the repo's actual production-branch name if it isn't literally `main`.) Same
exact-match rule as plain `approve`: rendered alone on its own line in a fenced code block,
matched only if the human's trimmed reply is exactly `approve main` (case-insensitive) or a
standing override they've stated. There is no separate hotfix exception — a hotfix landing on the
production branch directly needs `approve main` like anything else.

Once granted, add this exact line to the PR body before opening it — CI verifies it mechanically,
since it cannot see the conversation:

```text
Production-branch authorization: approve main
```

See `AGENTS.md` → "Production-branch gate (`approve main`)" and `PROJECT_CONFIG.md` →
"Production-branch approval gate (CI)".

## Stop-and-ask gates

*Trigger: you're unsure whether to stop and ask the human.*

`AGENTS.md` → "Stop-and-ask gates" is the complete, enumerated list of moments that need a human
reply — `approve`, `approve main`, ambiguous requests, mid-task scope expansion, genuine
blockers, unsafe resumes, actions requiring explicit human instruction, and merging. Anything not
on that list is your call to make without stopping; the list exists to cut down on interruptions,
not multiply them. Read it once per task, not once per decision.

## Splitting a task into sub-tasks

*Trigger: during planning (step 2), the task naturally decomposes into independent pieces.*

Propose the breakdown as a numbered list of sub-tasks instead of silently picking one, and offer
both a bulk and a selective approval (bulk first, it's the more common preference):

```text
To approve all of the above and continue through them without stopping again, reply:

approve all

To approve only specific ones, reply with their numbers, e.g.:

approve 1,3
```

- `approve all` approves every listed sub-task in one action: run steps 3–7 for each in sequence
  without stopping again (`create_agent_issue.sh --parent <parent-issue>` makes each a real
  GitHub sub-issue). Only stop early if a sub-task needs scope beyond what was described, or
  blocks on a human decision.
- `approve 1,3` (or any subset) approves only those numbers; the rest stay unapproved.
- Don't invent a breakdown just to have one — a task that's genuinely one unit of work stays one
  issue and one PR.

## Worktree notes

*Trigger: step 4, when the standard worktree flow doesn't fit.*

- Worktrees exist because agents run this repo in parallel — never branch in place or share a
  working tree when another agent might touch the repo concurrently.
- Only use `publish_agent_branch.sh --no-worktree` (in-place switch) where worktrees genuinely
  aren't possible — e.g. some CI, or a hosted platform (Claude Code on the web, Codex cloud)
  that already gives each session its own isolated clone and pre-assigned branch. In that hosted
  case the platform's clone *is* your isolation; don't fight it by renaming branches (see
  `PROJECT_CONFIG.md` → "Agent branch prefix" — `claude/*`/`codex/*` are allowed).
- `WORKTREE.md` is per-worktree scratch and is not committed.

## Local bootstrap refresh: /github_kit_update

*Trigger: the human invokes `/github_kit_update`, or local kit files look stale.*

Refreshes this repo's *local* github-kit bootstrap files (`AGENTS.md`/`CLAUDE.md` managed block,
skills, Cursor rules, `copilot-instructions.md`, this file, project helper scripts) from
`pzoli6/github-kit@main`. Requires network (that's its purpose); refuses a dirty working tree
unless explicitly allowed; never overwrites `docs/ai/PROJECT_CONFIG.md` unless `--force-config`;
always stops at a draft PR. Optional — the reusable-workflow callers auto-track `@main` on their
own; only local files lag until it's run.

## Free-tier limitations

*Trigger: branch protection or required checks seem to be "missing".*

- Private repos on the GitHub Free plan cannot enforce branch protection rulesets — no required
  reviews, no required status checks blocking a merge. Platform limitation, not a
  misconfiguration; don't work around it by changing repo visibility or plan without explicit
  human instruction.
- CI still runs and still reports pass/fail — treat a failing check as a real signal even though
  GitHub won't block a human merge on it.
- Compensate with process: draft PRs, actual human review, no self-merge (step 9).

## Pausing for AI usage limits (Codex, Claude Code, others)

*Trigger: you're hitting a usage/context limit mid-task.*

1. Commit what's safely committable with explicit `git add <file>` staging.
2. Stash the rest: `git stash push -m "issue-<n>: <short description>"` (the message identifies
   the task).
3. Write/update `handoffs/issue-<n>.md`: branch name, whether a stash exists and its message,
   what's done, what's left, exact next step.
4. If a PR exists, mirror it: `scripts/project/post_handoff_comment.sh --pr <pr> --file
   handoffs/issue-<n>.md --agent "<name>"` (it updates its own prior comment in place —
   re-running is expected, not noisy).
5. *[Project]* `Status: Blocked` ("paused — AI usage limit") if nothing can continue this
   session, else leave `In Progress`; update `Last Agent Update`.

Never stop with uncommitted, unstashed, undocumented changes in the worktree.

## Resuming stashed work

*Trigger: you're picking up a branch/issue you (or another agent) previously paused.*

1. `scripts/project/check_resume_safety.sh --issue <n> --agent "<your agent name>"`:
   - exit 0 (`SAFE_TO_PROCEED`) — continue;
   - exit 2 (`STOP: ...`) — issue closed or linked PR merged/closed; don't resume, tell the user;
   - exit 3 (`ACTIVE_ELSEWHERE: ...`) — another agent's claim is still fresh (within
     `AGENT_CLAIM_STALENESS_MINUTES`, default 120); report instead of duplicating work.
2. Read `handoffs/issue-<n>.md` — it should say whether a stash exists and what's in it.
3. Confirm `git status` / `git stash list` match the handoff. Mismatch → stop and investigate.
4. Apply a stash with `git stash apply` (not `pop`); review the diff before `git stash drop`.
5. Re-run the validation commands — the base branch may have moved during the pause.
6. Update the handoff so it no longer describes a stale "paused" state.

Never start fresh work in a worktree with unexplained stashed/uncommitted changes.

## When Project Sync isn't enabled

*Trigger: you're about to assume a Project field updated itself. (In solo mode this section is
moot — Project-field steps are skipped entirely.)*

`.github/workflows/project-sync.yml` is not installed by default — check `PROJECT_CONFIG.md`. If
it isn't enabled, no Project field updates itself: every *[Project]* step in the checklist means
*you* run the matching wrapper script (`create_agent_issue.sh`, `publish_agent_branch.sh`,
`create_agent_pr.sh`, `sync_project_fields.sh`) — or, only if a wrapper can't cover it, the
lower-level `project_set_status.sh`/`project_set_text.sh` or the Project UI. Nothing happens as a
side effect of pushing a commit or opening a PR; check the Project directly if unsure.

## Manual Project update fallback

*Trigger: `gh` isn't authenticated, the helper scripts fail, or there's no network to the GitHub
API — and Project tracking is enabled for this repo.*

- Update the Project via the GitHub web UI directly instead of skipping the update.
- Note in the handoff file that updates were made (or still need to be made) manually.
- Never silently skip a required Project update because a script failed — do it by hand or record
  in the handoff that it's outstanding.

## GitHub relationships and development links

*Trigger: an issue/PR genuinely relates to another (steps 3 and 7).*

`gh` (2.78.0) has no dedicated sub-issue/blocked-by subcommand; record real relationships as
plain body text — `Blocked by #12`, `Blocks #15`, `Part of #10`. If none exists, write exactly:

```text
Relationships: none declared
```

The issue's "Development" sidebar links automatically from the PR's `Closes #<n>` line — no extra
step. To link a branch *before* a PR exists, `gh issue develop <n> --name <branch>` is an
alternative to `publish_agent_branch.sh` (it creates the branch itself; you'd add a worktree for
it manually).

## Notifications and participation

*Trigger: someone needs to be "subscribed" to an issue/PR.*

`gh` can't subscribe people directly; participation is the mechanism — assigning, requesting
review, and @mentioning all trigger normal notification delivery. `create_agent_issue.sh` /
`create_agent_pr.sh` set `--assignee` (and `--reviewer`) by default for exactly this reason. If
neither is configured, say so in the body and @mention the relevant person. Record it as:

```text
Notifications: ensured through assignment
```
