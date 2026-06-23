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
- **Stop and wait** for the human to reply `approve`. Do not create branches,
  install dependencies, or write implementation code before this.

## Phase 3 — Issue and Project setup

- If no GitHub issue exists for this task yet, create one with
  `scripts/project/create_agent_issue.sh --title <title> --body-file <path> --agent <name>
  --area <name> --risk <Low|Medium|High> --environment <name>`, using
  `.github/ISSUE_TEMPLATE/agent_task.yml`'s structure for the body (problem, context, approved
  plan, acceptance criteria, intended agent, risk, base branch). Pass `--parent <issue>` if this
  task is a sub-task of a parent issue (see "Splitting a task into sub-tasks" in `AGENTS.md`).
- This one script call adds the issue to the configured GitHub Project, sets `Status` to `Ready`,
  and sets `Agent`, `Area`, `Risk`, and `Environment` — there is no separate manual step. Always
  pass `--agent`/`--area`/`--risk`/`--environment` explicitly; don't rely on the
  `AGENT_DEFAULT_*` fallback in `docs/ai/PROJECT_CONFIG.env` to do it for you.
- `Base Branch` is set later, in Phase 4, once the actual base branch is resolved.

## Phase 4 — Branch and worktree

- Branch from the configured base branch, name it with the configured agent prefix (default
  `agent/`), e.g. `agent/issue-42-add-retry-logic`. Use
  `scripts/project/publish_agent_branch.sh --issue <issue> --slug <short-description>` to create
  and push it.
- Use an isolated worktree if this task may run concurrently with other agent sessions on the same
  repo.
- This script call sets `Status` to `In Progress` and updates both `Branch` and `Base Branch` —
  there is no separate step for `Base Branch`.

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

- Push the branch, then open a **draft PR** targeting the configured base branch with
  `scripts/project/create_agent_pr.sh --issue <issue> --base <branch> --head <branch> --title
  <title> --body-file <path> --agent <name> --area <name> --risk <Low|Medium|High> --environment
  <name> --agent-run <url> --handoff <note>`. Use `.github/PULL_REQUEST_TEMPLATE.md`'s structure
  for the body file — fill in every section (summary, linked issue, Project metadata, validation
  state, commands run, results, human review focus, known risks, follow-up items); the body text
  is for human readers, the flags above are what actually update the Project.
- This one script call adds the PR to the Project, sets `Status` to `In Review`, and sets `PR
  URL`, `Agent`, `Area`, `Risk`, `Environment`, `Agent Run`, and `Handoff` — there is no separate
  manual step. See "Field-completeness checklist" in `AGENTS.md` → "Project fields" for the
  PR-template-section-to-Project-field mapping.

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

---

The sections below are cross-cutting — they apply at any phase above, not just one step in the
sequence.

## Fast-path trigger: /github_kit

`/github_kit <task description>` is a pre-approved alternative entry point into the lifecycle
above. It changes exactly one thing — **Phase 2's stop-and-wait** — and nothing else:

- The `/github_kit <task>` invocation itself **is** the human's approval for `<task>`, scoped
  strictly to the description supplied. The agent still writes a visible plan (Phase 2's first
  bullet) for transparency, but does not stop and wait for a separate `approve`
  reply before moving into Phase 3.
- The pre-approval covers only what `<task>` describes. If the agent discovers mid-task that the
  work needs to expand beyond that description, it stops and falls back to the normal `approve`
  gate for the additional scope — pre-approval never grows on its own.
- Every other phase is unchanged: the issue still uses `.github/ISSUE_TEMPLATE/agent_task.yml`
  (note in the issue body that approval came via direct `/github_kit` invocation), the item still
  gets added to the Project, `Status` still moves through the same values (an agent may move
  straight from `Backlog` to `Ready` without dwelling in `Plan Review`, since there's no separate
  wait), branching/implementation/validation/PR/handoff/review/completion rules are identical to
  the rest of this document and to `AGENTS.md`.
- This trigger is **additive**, not a replacement. `approve` remains the
  default gate for any task not invoked this way, and the `issue-to-pr-project` skill/runbook
  remains available unchanged. Nothing here removes a label requirement, makes Project Sync
  default, or permits self-merging/tagging — every other rule in `AGENTS.md` still applies in full.
- Per-agent entry points: Claude Code's `/github_kit` slash command (`.claude/commands/
  github_kit.md`, runbook at `.claude/skills/github_kit/SKILL.md`), the generic agent skill
  (`.agents/skills/github_kit/SKILL.md`) for Codex/Antigravity/other tools, and the Cursor rule
  (`.cursor/rules/github-kit-command.mdc`). Any agent without a dedicated adapter recognizes the
  trigger from this section and `AGENTS.md` directly — a message starting with `/github_kit`
  followed by a task description is the signal, regardless of tool.
- `/github_kit` runs entirely from local files and never requires network access — it is distinct
  from this repo's reusable-workflow auto-tracking of `pzoli6/github-kit@main` (see "Always-latest
  main channel" in `README.md`). Do not confuse the two: workflows auto-update, local bootstrap
  files do not.

## Splitting a task into sub-tasks

This applies inside Phase 2 (Plan review), as an alternative to presenting one plan for one issue.
If the task naturally decomposes into independent pieces, propose that breakdown as a numbered
list of sub-tasks instead of silently picking one, and offer both a bulk and a selective way to
approve it (bulk first, since it's the more common preference):

```text
To approve all of the above and continue through them without stopping again, reply:

approve all

To approve only specific ones, reply with their numbers, e.g.:

approve 1,3
```

- `approve all` approves every listed sub-task in one action. Once given, run Phases 3 through 7
  for each sub-task in sequence without stopping to ask again: create each as its own issue via
  `scripts/project/create_agent_issue.sh --parent <parent-issue>` (a real GitHub sub-issue of the
  parent, so the Project's native "Sub-issues progress" column reflects them), then branch,
  implement, validate, and open a draft PR for it before moving to the next. Only stop early if a
  sub-task needs scope beyond what was described when it was approved (same rule as
  `/github_kit`'s pre-approval never expanding on its own), or if one sub-task blocks on a human
  decision before the next can start.
- `approve 1,3` (or any subset) approves only the listed numbers; the rest stay in `Plan Review`,
  unapproved, until a later reply approves them too.
- Don't invent a breakdown just to have one — a task that's genuinely one unit of work stays one
  issue and one PR.

## Local bootstrap refresh: /github_kit_update

A separate, optional command/skill (`.claude/skills/github_kit_update/SKILL.md`,
`.agents/skills/github_kit_update/SKILL.md`) refreshes this repo's *local* github-kit bootstrap
files — `AGENTS.md`/`CLAUDE.md` managed block, skills, Cursor rules, `copilot-instructions.md`,
this file, project helper scripts — from `pzoli6/github-kit@main`. Unlike `/github_kit`, this
command requires reaching `github-kit@main` (that's its whole purpose); if it can't, it stops and
reports the block rather than silently doing nothing. It refuses a dirty working tree unless
explicitly allowed, never overwrites `docs/ai/PROJECT_CONFIG.md` unless `--force-config`, never
installs Project Sync unless requested, and always stops at a draft PR for human review — it never
merges. This command is optional because the reusable-workflow callers already auto-track `@main`
on their own; it only matters for local files, which lag behind until it's run.

## Free-tier limitations

- Private repositories on the GitHub Free plan cannot enforce branch protection rulesets: no
  required reviews, no required status checks blocking a merge at the platform level. This is a
  GitHub plan limitation, not something to work around by changing repo visibility or plan without
  explicit human instruction.
- CI workflows (`ci-node.yml`, `ci-python.yml`, etc.) still run and still report pass/fail — they
  just can't be made "required" to block a merge. Treat a failing check as a real signal to fix,
  even though GitHub won't stop a human from merging anyway.
- Compensate with process: always open as draft, always wait for actual human review, never
  self-merge (see Phase 9). If this repo is later upgraded to a plan that supports branch
  protection, a human can enable required reviews/status checks at that point.

## Pausing for AI usage limits (Codex, Claude Code, others)

AI coding agents can hit a usage limit mid-task. Treat that as a controlled pause:

1. Commit anything that's safely committable with explicit `git add <file>` staging.
2. For changes that aren't ready to commit, run `git stash push -m "issue-<number>: <short
   description>"` so the stash message identifies which task it belongs to.
3. Write or update `handoffs/issue-<number>.md` stating: the branch name, whether a stash exists
   and its message, what's done, what's left, and the exact next step.
4. Set `Status` to `Blocked` with the reason "paused — AI usage limit" if no one can continue this
   session, or leave it at `In Progress` if another session/agent will pick it up immediately.
5. Update `Last Agent Update`.

Never stop with uncommitted, unstashed, undocumented changes sitting in the worktree — the next
agent (or human) has no way to know whether those changes are intentional work-in-progress or
accidental local clutter.

## Resuming stashed work

Before writing any new code on a branch you're resuming:

1. Read `handoffs/issue-<number>.md` first — it should say whether a stash exists and what it
   contains.
2. Run `git status` and `git stash list` and confirm they match what the handoff file describes.
   If they don't match, stop and investigate before doing anything else — don't assume.
3. If a stash exists for this branch, apply it with `git stash apply` (not `pop`) so you can
   review the resulting diff before dropping the stash explicitly with `git stash drop`.
4. Re-run the validation commands in `PROJECT_CONFIG.md` before continuing — the pause may have
   been long enough that the base branch moved.
5. Update the handoff file once work resumes so it no longer describes a stale "paused" state.

Never start fresh work in a worktree that has unexplained stashed or uncommitted changes without
reading the handoff file that should account for them first.

## When Project Sync isn't enabled

`.github/workflows/project-sync.yml` (which would update Project fields automatically from PR/issue
activity) is **not installed by default** — see `docs/ai/PROJECT_CONFIG.md` for whether it's
enabled in this repo. If it isn't:

- `Status`, `Validation`, `Last Agent Update`, `PR URL`, `Branch`, `Base Branch`, `Agent`, `Area`,
  `Risk`, `Environment`, `Agent Run`, and `Handoff` do not update themselves. Every phase above
  means *you* run the matching wrapper script (`create_agent_issue.sh`, `publish_agent_branch.sh`,
  `create_agent_pr.sh`, `sync_project_fields.sh`) — or, only if a wrapper genuinely can't cover the
  case, the lower-level `project_set_status.sh`/`project_set_text.sh` directly, or edit the Project
  UI — at that point. None of this happens as a side effect of pushing a commit or opening a PR.
- Don't assume a field is current just because the underlying GitHub state (PR merged, issue
  closed) changed. Check the Project directly if you're unsure.

## Manual Project update fallback

If `gh` isn't authenticated, the Project helper scripts fail, or the environment has no network
access to the GitHub API:

- Update the Project via the GitHub web UI directly instead of skipping the update.
- Note in the handoff file that the automation scripts were unavailable and updates were made (or
  need to be made) manually — so the next agent or human knows why field updates might be delayed
  or inconsistent, rather than assuming the workflow was skipped carelessly.
- Never silently skip a required Project update because the script failed — either do it by hand
  or say explicitly in the handoff file that it still needs to happen.

## GitHub relationships and development links

Declare a real relationship between issues/PRs when one genuinely exists in Phase 3 or Phase 7 —
but never invent one just to fill a field. `gh` (2.78.0) has no dedicated sub-issue/blocked-by/
blocking subcommand; record real relationships as plain body-text references instead:

```text
Blocked by #12
Blocks #15
Part of #10
```

If no real relationship exists for a task, write this exact line in the issue or PR body rather
than leaving the question unaddressed:

```text
Relationships: none declared
```

An issue's "Development" sidebar section links automatically once Phase 7's
`scripts/project/create_agent_pr.sh` opens the PR — its `Closes #<n>` body line is what GitHub
uses to associate the PR with the issue, no extra step required. To get a branch linked under
Development *before* a PR exists, create it with `gh issue develop` instead of Phase 4's
`scripts/project/publish_agent_branch.sh` (the two are alternatives, not complementary — `gh issue
develop` creates the branch itself):

```bash
gh issue develop <issue-number> --name <agent/branch-name> [--branch-repo <owner/repo>]
```

## Notifications and participation

`gh` has no command to directly subscribe a person to issue/PR notifications. Get the right people
notified by participating them in the thread instead — assigning, requesting review, and
@mentioning all trigger GitHub's normal notification delivery:

```text
Notifications: ensured through assignment
```

Phase 3's `scripts/project/create_agent_issue.sh` and Phase 7's `scripts/project/
create_agent_pr.sh` set `--assignee` (and, for PRs, `--reviewer`) by default for exactly this
reason — being assigned or requested as reviewer is what puts someone "on notifications" for that
item; there is no separate subscribe step. If neither an assignee nor a reviewer is configured for
this repo, say so in the issue/PR body and `@mention` the relevant person instead of assuming
they'll see it.
