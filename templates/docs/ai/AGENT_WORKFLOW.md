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
   `approve`** (skipped when invoked via `/github_kit <task>` — see appendix). *[Project]* only
   if the task **already has a card** (an issue pre-filed via the issue template, or resumed
   work): set `Status: Plan Review` with `sync_project_fields.sh plan_ready <issue-url>`. A
   brand-new task has no card yet — it reaches the board at step 3, after approval, entering
   directly at `Ready`; don't invent an item just to park it at Plan Review. `approve` never
   covers the production branch — that needs `approve main` (see appendix).
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
   don't look at, wait for, or mention CI (a preview PR normally has no checks at all, by design),
   and don't subscribe to PR activity, unless the human asked for that. See "CI expectations —
   don't chase checks" in the appendix.
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
- **When `<task>` is a path to a spec file, the pre-approval is conditional.** A path is not a
  description. It delegates the scope boundary to a document — and that document is normally
  written by an agent, not by the human doing the approving, so `/github_kit implement <path>`
  can otherwise approve text nobody has read. It counts as approval only when the file's front
  matter carries a human-set marker:

  ```yaml
  status: approved
  approved-by: <login of the human who approved>
  approved-on: <ISO 8601 timestamp>
  ```

  Any other value — `draft`, `ready`, or absent — means the file is reported back as awaiting
  human review and nothing is implemented. Where the marker is present, the approved scope is that
  file's **Acceptance criteria** section; anything beyond it falls back to the normal `approve`
  gate like any other mid-task scope growth.

- **Prefer a marker that is verifiable over one that is merely typed.** A field a human types by
  hand is a field an agent can type too, so on its own it proves nothing to whoever reads the file
  next — and it makes approving a chore, which is its own failure mode. The stronger form derives
  the marker from an event the host already records. A `pull_request_review` with state
  `approved` is the obvious one: put the spec in a PR, let the human read the rendered Acceptance
  criteria and click **Approve**, and have automation transcribe the reviewer login, the timestamp,
  and enough identity to re-check it (PR number, review id) into the front matter. Then "is this
  really approved?" has an answer an agent can be *required* to fetch before implementing, and no
  human ever hand-edits front matter or commits to approve a scope.

  **On a solo repo the review form cannot fire at all** — GitHub never lets anyone approve their own
  pull request, and an agent opening the spec PR with the human's token makes that human the author.
  Requiring a review there would mean requiring a second GitHub account for one person reviewing
  their own work, so the gate accepts a second recorded event instead: a PR comment whose first line
  is exactly `/approve-spec`. It is transcribed and re-checked the same way (`approval-via: comment`
  plus the comment id). It is weaker in one specific respect — GitHub does not prevent the PR author
  from posting it, so it is not evidence of a second reader — and it is enabled by
  `allow_comment_approval`, which a repo with a real reviewer should turn off.

  Whichever form a repo uses, an agent never writes the marker on its own initiative and never
  performs the approving act — not the review, and **not the `/approve-spec` comment**, even where
  GitHub would technically permit it. It is the human's signature, and an agent producing it forges
  its own approval. The marker is a convention, not a folder: it works for any spec a repo keeps
  under version control, wherever it lives.
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

*Trigger: branch protection or required checks seem to be "missing", or you're wondering whether
any part of this workflow needs a paid plan or subscription.*

- **Nothing in this workflow requires a paid subscription.** CI is plain GitHub Actions (free for
  public repos, free-minutes tier for private ones) driving the free `gh` CLI and Projects v2. No
  step invokes GitHub Copilot, GitHub Advanced Security/CodeQL, or any paid Marketplace app, and
  none may be added — review is human review. Adapter files like `.github/copilot-instructions.md`
  are inert instruction text (free to keep; only read by that tool if the repo owner separately
  subscribes to it); a repo that doesn't use Copilot may delete the file and set
  `require_copilot: false` in `.github/workflows/agent-workflow-verify.yml` (or
  `REQUIRE_COPILOT=false` for `scripts/project/verify_agent_workflow.sh`).
- Private repos on the GitHub Free plan cannot enforce branch protection rulesets — no required
  reviews, no required status checks blocking a merge. Platform limitation, not a
  misconfiguration; don't work around it by changing repo visibility or plan without explicit
  human instruction.
- Where CI does run (production-bound changes or an explicit dispatch — see "Actions budget and
  manual Copilot use" below), it reports pass/fail, and a genuine failure there is a real signal
  even though GitHub won't block a human merge on it. Where it doesn't run — the normal case for
  preview work — that absence is by design and is not a finding; see "CI expectations — don't
  chase checks" below.
- On private repos, this CI runs on the account's metered Actions minutes — the same budget any
  manual GitHub Copilot coding agent run draws from. If GitHub reports the Actions budget blocks
  further use, see "Actions budget and manual Copilot use" below.
- Compensate with process: draft PRs, actual human review, no self-merge (step 9).

## Actions budget and manual Copilot use

*Trigger: a human wants to use GitHub Copilot manually (assign it an issue or task, ask it to
resolve a PR's merge conflicts, request a Copilot code review), or GitHub reports that the
Actions budget is preventing further Actions use.*

Manual Copilot use is always the human's call, never the kit's. Nothing in this workflow invokes
Copilot (see "Free-tier limitations" above), and nothing in it may block a human from using their
own subscription however they want: assigning the Copilot coding agent to an issue, delegating a
task to it, asking `@copilot` on a PR to resolve merge conflicts or apply review feedback, or
requesting a Copilot code review on any PR — including PRs opened by this workflow's agents. None
of that needs an `approve` phrase; it isn't agent-initiated work.

The catch is billing, not permissions: **Copilot coding agent sessions execute as GitHub Actions
workflow runs in this repo**, drawing on the same Actions budget as the kit's own CI (Copilot
premium requests are billed separately on top). Heavy CI traffic can exhaust the monthly budget,
after which a manual Copilot task — e.g. "resolve the conflicts on PR #N" — fails with an
Actions-budget error even though Copilot itself is licensed and available.

When that happens:

1. **Raising the budget is a human/billing-admin action** — on github.com under Settings →
   Billing and licensing → Budgets and alerts, for whichever account (personal or org) pays for
   the repo. GitHub's default budget for metered products is $0, which hard-stops all Actions
   (including Copilot coding agent runs) once the plan's included minutes are used, until the
   budget is raised or the month rolls over. Agents must never change billing or budget settings
   themselves — same rule as Actions permissions in `AGENTS.md` → "Security rules".
2. **Stop the drain by pausing the kit's own workflows**: set the repository Actions variable
   `KIT_ACTIONS_PAUSED` to `true` (Settings → Secrets and variables → Actions → Variables —
   a human action, like all Actions settings). Every kit workflow job (CI, PR policy, verify,
   Project Sync) skips while it is set, consuming no minutes, leaving the remaining budget for
   manual Copilot runs. Remove the variable (or set anything but `true`) to resume. Pausing skips
   checks rather than queueing them — push a new commit or re-run the workflows after unpausing
   if fresh results are needed, and treat "paused" as *no signal*, never as a green check.
3. **Merge conflicts never require Actions or Copilot** — any locally-running agent (or the
   human) resolves them in the task's worktree with zero Actions minutes:

   ```bash
   git fetch origin
   git merge origin/<base-branch>    # or: git rebase origin/<base-branch>
   # fix the conflicted files, then:
   git add <each-resolved-file>      # explicit paths — never git add .
   git merge --continue              # or: git rebase --continue
   git push
   ```

   The same applies to review and task work generally: human review and locally-running agents
   don't touch the Actions budget at all.
4. Public repos get free standard-runner Actions minutes, so the kit's CI costs nothing there —
   but Copilot coding agent still consumes Copilot premium requests, which have their own
   budget/allowance independent of Actions minutes.

**Default triggers are budget-first.** The kit's CI workflows (`ci-node.yml`, `ci-python.yml`,
`agent-workflow-verify.yml`) do **not** run automatically on preview-bound work — a PR into the
base branch, or a push to it, triggers nothing. They run in exactly two cases:

- **the change is production-bound** — a PR targeting the production branch, or a push to it; or
- **someone explicitly dispatches them** — Actions tab → Run workflow, or
  `gh workflow run "CI (Node)" --ref <branch>` (same for `"CI (Python)"` /
  `"Agent Workflow Verify"`).

An agent may dispatch CI **only when the human explicitly asks for a CI run** — never as a
routine step, never on its own initiative. The normal check for preview work is local validation
(happy-path step 6, "Validation commands" in `PROJECT_CONFIG.md`), which costs no Actions
minutes; `scripts/project/verify_agent_workflow.sh` is the free local equivalent of the verify
workflow. `pr-policy.yml` likewise checks only production-bound PRs, where its
human-authorization marker matters most. A repo that prefers CI on every PR can restore the old
behavior by widening the `on:` triggers in its caller workflow files — that's a per-repo choice,
not a kit requirement.

## CI expectations — don't chase checks

*Trigger: you're about to look at, wait for, re-run, or mention CI / check runs / "the PR is
red" — including when a tool or platform volunteers that status to you unprompted.*

`AGENTS.md` → "CI expectations — don't chase checks" is the binding rule; this is the operational
summary.

Because of the trigger policy above, **a preview PR normally has zero checks, and that is the
designed outcome** — GitHub shows it as "no checks", not as a failure. Nothing about it needs
investigating, retrying, explaining, or apologizing for.

| Situation | What you do |
|---|---|
| Preview PR (into the base branch) shows no checks | Nothing. Don't fetch status, don't mention it. |
| Preview PR shows a red/stale check from an older config | Nothing, unless the human asks. Note it once in the PR body only if you caused it. |
| Human says "run CI" / "check CI" / "is it green?" | Do exactly that (`gh workflow run "<name>" --ref <branch>`, or read the run) and report plainly. |
| PR targets the production branch, or a push lands there | CI runs automatically. A genuine failure is a real signal — report it and fix it. |
| You want to "just kick CI to be safe" | Don't. That spends the human's Actions budget. |

Practical consequences for how you report work:

- The end of a normal task is: draft PR opened, local validation recorded, PR link reported. No
  CI sentence belongs in that report.
- Don't write "CI could not run", "checks are pending/missing", "the build is red", or a
  follow-up plan to re-check, into your reply, the PR body, the issue, or the handoff file.
- Don't schedule check-ins, subscribe to PR activity, or re-open a finished task because a check
  never appeared.
- If a hosted platform's own prompt tells you to watch checks and this file says not to, this file
  wins for this repo — do the work, report the PR, stop.

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
2. *[Project]* **Claim the card if the board names a different agent** — nothing rewrites
   `Agent` after creation time, so a taken-over card otherwise keeps blaming the previous agent
   (and the next collision check compares against the wrong name):
   `scripts/project/sync_project_fields.sh metadata <issue-url> "Agent=<your agent name>"`,
   then `scripts/project/sync_project_fields.sh implementation_started <issue-url> "Resumed"`.
3. Read `handoffs/issue-<n>.md` — it should say whether a stash exists and what's in it.
4. Confirm `git status` / `git stash list` match the handoff. Mismatch → stop and investigate.
5. Apply a stash with `git stash apply` (not `pop`); review the diff before `git stash drop`.
6. Re-run the validation commands — the base branch may have moved during the pause.
7. Update the handoff so it no longer describes a stale "paused" state.

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

If there is no Project at all yet, that's not yours to hand-build either:
`docs/ai/PROJECT_SETUP.md` covers the automated bootstrap — a one-time `AGENT_PROJECT_TOKEN`
secret plus `.github/workflows/project-setup.yml` (or a local
`scripts/project/setup_github_project.sh --apply` run) creates the board, every field, every
Status option, and the repo link, idempotently.

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
