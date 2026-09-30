# github-kit

Central reusable GitHub workflow and AI-agent development kit.

`github-kit` is the canonical source of truth for the issue-to-PR-to-Project workflow used across
all of `pzoli6`'s repositories, for both human contributors and AI coding agents (Claude Code,
ChatGPT Codex, Cursor agents, Antigravity, Gemini CLI, ChatGPT with repo context, and future
agents). It provides:

1. **Reusable GitHub Actions workflows** (`.github/workflows/reusable-*.yml`) — called via
   `workflow_call` from any target repo.
2. **AI-agent workflow templates** (`templates/`) — `AGENTS.md`, `CLAUDE.md`, Cursor rules, Claude
   and generic agent skills, the `REVIEW.md` review rulebook, and the `docs/ai/` workflow
   specification.
3. **Install / update / doctor scripts** — both Bash (`scripts/*.sh`, for Linux/macOS/WSL/Git
   Bash) and native PowerShell (`scripts/*.ps1`, for Windows) — bring a target repo up to date
   without clobbering its existing content, and audit `github-kit`'s own packaging.
4. **Issue / PR templates** — a structured agent-task issue form and a PR template that captures
   Project metadata, validation state, and human review focus.
5. **GitHub Project helper scripts** (`templates/scripts/project/*.sh`) — thin `gh`/`jq` wrappers
   for adding items to a Project and updating its Status/text fields from a branch, a script, or a
   workflow run, plus an idempotent standard-labels creator.

> **Setting this up, or something not propagating?** → **[docs/OWNER_SETUP.md](docs/OWNER_SETUP.md)**
> — the steps only the repo owner can do (tokens, secrets), each with a way to check whether it is
> already done, plus a troubleshooting table. Fan-out does nothing until Step 1 there is complete.

This repo intentionally contains very little repo-specific content. Everything that varies
per-repo (Project number, base branch, validation commands, forbidden files, github-kit version,
etc.) lives in the target repo's `docs/ai/PROJECT_CONFIG.md`, not here.

## Free-tier usage and branch protection

`github-kit` targets the **GitHub Free plan** as the default case, not an afterthought:

- **No paid subscription is required — or invoked — by any part of the kit's CI/CD.** Every
  workflow is plain GitHub Actions (free for public repos, free-minutes tier for private ones)
  using standard public actions (`actions/checkout`, `setup-node`, `setup-python`,
  `pnpm/action-setup`) plus the free `gh` CLI and GitHub Projects (v2). Nothing calls a paid AI
  service, GitHub Advanced Security/CodeQL, or a paid Marketplace app; PR review is human review,
  optionally helped by AI reviewers you run outside CI (see "PR review" below). The kit no longer
  ships a GitHub Copilot adapter (see `AGENTS.md` → Migration notes).
- **The kit's CI shares one Actions budget with every other repo on the account.** So the kit is
  budget-aware: the template CI/verify workflows trigger only for production-bound changes (PR
  targeting the production branch, or a push to it) or an explicit `workflow_dispatch` — never
  automatically on preview-bound PRs, where agents validate locally instead; every reusable
  workflow job additionally skips — consuming no minutes — while the caller repo's Actions
  variable `KIT_ACTIONS_PAUSED` is `true`; and CI runs superseded by a newer push to the same PR
  are auto-cancelled. The pause switch and auto-cancel live in the reusable workflows, so repos on
  the `@main` channel get those without refreshing local files (the triggers live in each repo's
  caller files, refreshed via `/github_kit_update`). The kit also tells agents to **stop chasing
  checks**: a preview PR with no checks is the designed outcome, so agents must not fetch check
  runs, poll, subscribe to PR activity, self-dispatch a workflow, or report "CI didn't run / is
  red" — which keeps their tokens and your attention on the work instead of a non-problem. CI is
  their business only when you ask or when a change is production-bound; see
  [`templates/AGENTS.md`](templates/AGENTS.md) → "CI expectations — don't chase checks" and
  `docs/ai/PROJECT_CONFIG.md` → "CI trigger policy and Actions budget". The budget guidance
  (including a zero-Actions local conflict-resolution fallback) is in
  [`templates/docs/ai/AGENT_WORKFLOW.md`](templates/docs/ai/AGENT_WORKFLOW.md) → "Actions budget".
- **Private repositories on GitHub Free cannot enforce branch protection rulesets** — no required
  reviews, no required status checks blocking a merge, at the platform level. This is a GitHub
  plan limitation, not a `github-kit` configuration gap.
- The kit compensates with **process discipline instead of platform enforcement**: every PR opens
  as a draft, CI workflows still run and report pass/fail (they just can't be marked "required"),
  and the agent rules in `AGENTS.md` forbid self-merging regardless of what GitHub will technically
  allow.
- If a repo is later upgraded to a plan that supports branch protection (or made public), a human
  can enable required reviews/status checks at that point — nothing here needs to change first.
- `docs/ai/PROJECT_CONFIG.md` records this per repo as `Branch protection enforced: false` so
  agents don't assume enforcement that isn't actually happening.

## Auto-merge after green

Because a private Free-plan repo cannot have required status checks, GitHub's **native
auto-merge is unusable there** — it refuses to enable itself without a branch-protection rule
to wait on. `github-kit` ships the substitute:
[`.github/workflows/reusable-auto-merge.yml`](.github/workflows/reusable-auto-merge.yml), called
from every installed repo's `.github/workflows/auto-merge.yml` (a thin caller that the installer
**and** the updater refresh, like `ci-node.yml` — it carries no repo-specific values).

**What it does.** A PR that **a person marked ready for review** merges automatically — with a
**merge commit** — as soon as every check on its head commit has succeeded. The human still
decides, and the workflow verifies it: the kit's PRs always open as drafts, and only a
`ready_for_review` event by a User account (read from the PR timeline) hands a PR to
auto-merge. A PR that was **opened non-draft** — Dependabot/Renovate, an agent that skipped
`--draft`, a release PR opened for review — has no such event and is **never** merged
automatically (convert it to draft and mark it ready to hand it over). Nothing merges while the
caller repo's `KIT_ACTIONS_PAUSED` variable is `true`, and nothing merges while the account's
Actions budget is exhausted, because no run starts at all.

**The decision**, re-evaluated on every event that can change it — PR marked ready / reopened /
`no-automerge` removed, one of the repo's Actions workflows completing successfully
(`workflow_run`), a third-party check suite completing successfully (`check_suite`), a `success`
commit status arriving (`status`):

| Rule | Outcome when not met |
|---|---|
| PR is open and not a draft | nothing to do |
| a person (not a bot) marked it ready for review (`require_human_ready: true`) | never merged automatically |
| PR does not carry the **`no-automerge`** label (case-insensitive; re-checked right before the merge) | held back while the label is present |
| head branch lives in the same repository (`allow_forks: false`) | never merged |
| head branch is not a long-lived branch — the default branch or `main`/`master`/`develop`/`staging`/`production` (`skip_head_branches`) | never merged automatically: release/promotion PRs are a human merge |
| no reviewer's latest review is `CHANGES_REQUESTED` (`require_no_changes_requested: true`) | waits for the review to change |
| GitHub reports the PR mergeable, not `dirty` (conflicts) | not merged |
| every check run on the head commit is `completed` with `success` / `neutral` / `skipped` | queued/in-progress → wait for the next event; `failure` / `cancelled` / `timed_out` / `action_required` / `stale` → not merged, failing names logged |
| the latest run of every other workflow on the head commit is completed `success` / `neutral` / `skipped` | a queued run (even before its jobs exist) → wait; otherwise not merged |
| no check run of `CI (Node)` / `CI (Python)` / `Agent Workflow Verify` / PR Policy's `policy` job was **skipped** — those skip only when `KIT_ACTIONS_PAUSED` was set, and paused is *no signal*, never green | not merged until those workflows are re-run (or a commit is pushed) after unpausing |
| combined commit status is `success`, or there are no statuses | `pending` → wait; `failure` / `error` → not merged |
| at least one check run, commit status or workflow run exists on the head commit | **not merged** unless the repo opted in (below) |

**Fail closed.** Every gate reads the GitHub API explicitly; a read that fails (rate limit,
missing token permission, 5xx) is logged as an error and the PR is **not** merged — it never
reads as "no checks" or "no blockers".

**No checks is not green.** A head commit with no check runs, no statuses and no workflow runs
is not merged, because that is indistinguishable from CI that has not registered yet or did not
run (a commit pushed with `GITHUB_TOKEN` starts no workflows, a `paths` filter can skip one).
Mind what that means with the kit's **budget-first CI triggers**: a PR into the *base* branch
starts no kit workflow at all (CI and PR Policy run for production-bound PRs), so unless a
third-party check such as a Vercel preview reports on it, such a PR is **not** merged
automatically — a human merges it. A repo that wants "merge when marked ready" without checks
sets the repository Actions variable **`KIT_AUTOMERGE_ALLOW_NO_CHECKS=true`**; the
`no-automerge` label is then its only brake. The registry declares it per repo
(`"variables"` in `.github/fanout-targets.json`), and you apply it with
`scripts/apply-repo-variables.sh` (run it with `--dry-run` first; it needs `gh` logged in as the
repos' admin). Nothing in CI changes repository settings.

**Why hasn't my PR merged?** A ready PR that auto-merge holds back gets **one comment, kept
current**, that names the reason and the next step, so a held PR is never silent. Merging by
hand always works: private Free-plan repos have no branch protection that could block it.

| The comment says | Why | What to do |
|---|---|---|
| no check ran on this commit | A PR into the working branch starts no kit CI (budget-first) | Merge by hand, or set `KIT_AUTOMERGE_ALLOW_NO_CHECKS=true` for the repo |
| GitHub refuses to merge changes to `.github/workflows/*` | Every kit update PR changes workflow files; `GITHUB_TOKEN` can't merge those | Merge by hand, or add an `AUTOMERGE_TOKEN` secret |
| failing check run(s) / workflow run(s) did not succeed | A check failed | Fix and push, or re-run a one-off failure |
| skipped while `KIT_ACTIONS_PAUSED` was set | Pause leaves no signal, never green | Unpause, then re-run those workflows or push |
| waiting for check run(s) / workflow run(s) | Checks still running | Nothing; if they never start, the Actions budget is probably used up |
| changes requested by … | A reviewer asked for changes | Address them; reviewer approves or dismisses |
| merge conflicts / mergeable … | The branch conflicts with its base | Resolve locally (no Actions minutes) and push |
| *(no comment at all)* | Still a draft, opened non-draft, a long-lived head branch (release PR), `no-automerge`, `KIT_AUTOMERGE_DISABLED`, or **no run could start** (Actions budget exhausted, `KIT_ACTIONS_PAUSED`) | Mark it ready / merge by hand; check Billing → Budgets |

When the PR merges, that comment becomes the merge summary, so there is still one comment.

The workflow's own check run is excluded from that evaluation (by run id, by the caller
workflow's runs on the same commit, and by its job name), so it can never wait on itself. After
a PR is marked ready or reopened it first sleeps `grace_seconds` (default 30) so checks about
to be queued for that commit exist before they are counted; other events skip the sleep. It
never approves reviews, never bypasses anything, and never touches branch protection or
repository settings. On merge it deletes the head branch only if it is a same-repo branch
starting with one of the kit's agent prefixes (`agent/`, `claude/`, `codex/`, `cursor/`,
`gemini/` — `delete_branch_prefixes`) and no other open PR uses it as base or head,
and posts one short comment naming the checks that were green.

**Per-repo settings are repository Actions variables**, because the caller file is refreshed by
every kit update (edits to it are overwritten, and a deleted caller is recreated — the one
exception is the repo-workflows list below):

| Variable | Effect |
|---|---|
| `KIT_AUTOMERGE_DISABLED=true` | auto-merge is off in this repo (the durable opt-out; deleting `auto-merge.yml` lasts only until the next update or fan-out) |
| `KIT_AUTOMERGE_ALLOW_NO_CHECKS=true` | a ready PR with no checks at all merges |
| `KIT_ACTIONS_PAUSED=true` | every github-kit job pauses, auto-merge included |

**The repo's own PR workflows.** GitHub fires no `check_suite` event for suites that Actions
created, so a workflow's completion re-evaluates a PR only if its `name:` is listed under the
caller's `workflow_run` trigger. The template lists the kit's workflows plus `CI`. A workflow
that is not listed still blocks the merge while it runs or if it fails; its success alone just
does not wake auto-merge, so if it is the last check to finish, the PR waits for the next event.
List such workflows between the marker lines in the repo's `.github/workflows/auto-merge.yml`:

```yaml
      # >>> github-kit: repo workflows >>>
      - "Application quality"
      # <<< github-kit: repo workflows <<<
```

The updaters (`update-github-kit.sh` / `.ps1`), the fan-out and `install --mode force` carry
those lines over and refresh the rest of the file. A name that matches no workflow is harmless.

**Token caveats.** Merges made with the default `GITHUB_TOKEN` **do not trigger other Actions
workflows** on the base branch — GitHub suppresses workflow runs for events caused by
`GITHUB_TOKEN`. Vercel and other GitHub-app/webhook integrations are unaffected. GitHub also
refuses changes to `.github/workflows/*` from a token without the workflow permission, which
`GITHUB_TOKEN` can never have — so a PR that touches workflow files (every github-kit fan-out /
update PR does) is expected to be refused; the run then logs a warning saying a human merges it,
rather than failing red. (Expected from GitHub's documented rules; not yet observed live.) If
either matters, store a PAT in that repo as the `AUTOMERGE_TOKEN` secret; the caller passes it
through and the merge is made with it instead. Scopes and steps:
[docs/OWNER_SETUP.md](docs/OWNER_SETUP.md) → "Step 4".

**Budget.** On a private repo every run that starts is billed at least one full minute. The
reusable job drops events that cannot make a PR mergeable before a runner starts (drafts, label
edits other than removing `no-automerge`, failed workflow runs and suites, non-`success`
statuses, runs/suites with no associated PR). What remains is roughly one run per successful
workflow run, third-party check suite and `success` status on a PR head, plus about one
minute when a PR is marked ready (the 30-second grace sleep) — as an estimate, 3–5 billed
minutes for a typical PR with a Vercel preview and one CI workflow. The status comment costs no
extra runs: it is written by the same evaluation.

**For agents** this changes the wording of the old *human-merges-only* rule to
*human-approves-only, merge is automated after green* — and adds three hard rules: never mark a
PR ready for review, never add or remove `no-automerge`, never merge or enable GitHub's native
auto-merge. The rule lives in the managed block of `AGENTS.md`/`CLAUDE.md`/`GEMINI.md`, so the
updater and fan-out deliver it to existing repos (`templates/AGENTS.md` → "Auto-merge after
green" has the full text). The checked-in `.claude/settings.json` denies the two MCP merge tools
and `gh pr merge` / `gh pr ready` for new installs only (the file is create-only); nothing denies
`mcp__github__update_pull_request` with `draft: false` or a GraphQL `markPullRequestReadyForReview`,
so for those the instruction is the only guard.

Inputs (all optional, set in the caller): `merge_method` (`merge`), `opt_out_label`
(`no-automerge`), `delete_branch` (`true`), `delete_branch_prefixes`, `skip_head_branches`,
`allow_forks` (`false`), `allow_no_checks` (`false`; the caller passes
`vars.KIT_AUTOMERGE_ALLOW_NO_CHECKS`), `require_human_ready` (`true`), `grace_seconds` (`30`),
`require_no_changes_requested` (`true`), `comment` (`true`), `status_comment` (`true`); secret
`automerge_token`.
The caller needs `contents: write`, `pull-requests: write`, `issues: read`, `checks: read`,
`statuses: read`, `actions: read`. Because `workflow_run`, `check_suite` and `status` only fire
for a workflow file on the **default branch**, auto-merge starts working in a repo once its
fan-out/update PR has merged there. Runs started by those three events execute on the default
branch, so their own check run shows on the default branch's head commit rather than on the PR.

## The universal workflow

Every repo that installs this kit follows the same lifecycle:

```text
User task
→ agent reads repo instructions (AGENTS.md, docs/ai/PROJECT_CONFIG.md, docs/ai/AGENT_WORKFLOW.md)
→ agent creates plan
→ human approval ("approve")
→ GitHub issue
→ GitHub Project update
→ agent branch
→ isolated worktree
→ implementation
→ validation
→ draft PR
→ handoff file
→ human review
→ human marks the PR ready
→ auto-merge after green
```

See [`templates/docs/ai/AGENT_WORKFLOW.md`](templates/docs/ai/AGENT_WORKFLOW.md) for the full
specification — a happy-path checklist plus an on-demand appendix (free-tier limitations,
pausing/resuming for AI usage limits, the manual-Project-update fallback, and other
conditionally-read sections) — and [`templates/AGENTS.md`](templates/AGENTS.md) for the rules
every agent must follow.

Two knobs adapt this lifecycle to how a repo is actually used:

- **Solo mode** (`docs/ai/PROJECT_CONFIG.md` → "Solo mode", default `auto`) collapses the
  team-scale ceremony for a single maintainer iterating quickly: no issue for pre-approved
  iterations, no Project-field updates, handoff files only when actually stopping mid-task —
  plan → implement → validate → draft PR. With the default `auto`, solo mode is active until a
  real GitHub Project is configured, so fresh installs behave solo with nothing to set. The
  approval gates and git/PR safety rules are unchanged.
- **Branch-prefix allowlist.** The `pr-policy` check accepts a comma-separated list of branch
  prefixes (default `agent/,claude/,codex/`): `agent/` is what the kit's scripts create, while
  `claude/`/`codex/` are what hosted agent platforms (Claude Code on the web, Codex cloud) assign
  on their own and can't rename without per-session approval. The policy's intent is "no
  arbitrary branch names targeting the base branch" — rejecting a platform-assigned prefix only
  produces duplicate PRs and permanently red checks.

## Remote-first metadata workflow

An agent branch, issue, or PR with blank sidebar metadata is easy to lose track of — no assignee
means no notification, no labels means it's invisible to filters, and a branch that only exists
locally can vanish with the worktree. `github-kit` closes those gaps with four scripts in
`templates/scripts/project/` that every agent workflow now calls instead of raw `gh` commands:

| Script | When | What it fills in |
|---|---|---|
| `create_agent_issue.sh` | Creating the tracking issue | assignee, labels, milestone, adds the issue to the Project |
| `publish_agent_branch.sh` | Immediately after the issue exists, **before any implementation code** | pushes the agent branch to `origin` right away — never local-only |
| `sync_project_fields.sh <checkpoint> <issue-or-pr-url> [text]` | At each workflow checkpoint (issue created, branch pushed, PR opened, review states, done) | `Status`, `Validation`, `Last Agent Update`, and other Project fields, in one call |
| `create_agent_pr.sh` | Opening the draft PR | assignee, reviewer, labels, milestone, adds the PR to the Project |

Two policies apply alongside these scripts:

- **Relationships.** Every issue/PR body either declares real relationships (`Blocked by #12`,
  `Blocks #34`, `Part of #5`) or states `Relationships: none declared` — never silence on the
  question. See `templates/AGENTS.md` → "GitHub relationships and development links".
- **Notifications.** Agents rely on `--assignee`/`--reviewer` (set by the scripts above) to ensure
  the right humans are notified, rather than assuming a separate subscribe/watch step exists. See
  `templates/AGENTS.md` → "Notifications and participation".

`scripts/project/verify_agent_workflow.sh` (and its CI mirror,
`.github/workflows/reusable-agent-workflow-verify.yml`) checks that all four scripts are present
and that both policy phrases appear somewhere in the repo, so a repo can't silently drift back to
the old late-push, blank-metadata pattern.

## Always-latest main channel

By default, `install-github-kit.sh`/`.ps1` write caller `uses:` lines as literal
`pzoli6/github-kit/<path>@main` — not a tag, not a placeholder. Once a repo has `github-kit`
installed, its CI workflows automatically pick up every change merged to this repo's `main` branch
on their very next run.

What auto-tracks `@main` and what doesn't:

- **Reusable workflows auto-track `@main` directly.** Fix or extend a reusable workflow once here,
  and every repo that calls it gets the fix on its next workflow run — no version bump, no
  re-running the installer, no PR.
- **Local bootstrap files auto-propagate via the fan-out workflow (below), not via `@main`.**
  `AGENTS.md`/`CLAUDE.md`, Cursor rules, the Claude/Codex skills, and this kit's own scripts live in
  the target repo's working tree, so a `uses: …@main` reference can't reach them. Instead,
  [`.github/workflows/github-kit-fanout.yml`](.github/workflows/github-kit-fanout.yml) opens a draft
  PR in each target repo whenever those files drift from `main` — you review and merge, never the
  automation. Running `update-github-kit.sh`/`.ps1` or `/github_kit_update` by hand still works as
  an on-demand alternative.
- **Pinning is still supported, just no longer the default.** Pass `--ref <tag-or-sha>` /
  `-Ref <tag-or-sha>` to either the installer or the updater to deliberately pin a repo instead of
  auto-tracking `main`. The legacy `--workflow-ref`/`-WorkflowRef` flag names still work as aliases.
  If you pin, update `docs/ai/PROJECT_CONFIG.md`: set `github-kit ref` to the pinned ref and
  `github-kit update mode` to `pinned` (instead of the default `main-channel`), so agents don't
  assume auto-updates are happening that aren't.

Because a merge to this repo's `main` is live for every installed repo on their next CI run, with no
opt-in step, changes here deserve a higher review bar than a typical app repo.

## Fan-out propagation of bootstrap files

`@main` auto-tracking covers reusable workflows but structurally can't cover the *local* bootstrap
files copied into each repo (`AGENTS.md`/`CLAUDE.md`/`GEMINI.md` managed blocks, skills, Cursor
rules, `REVIEW.md`, `docs/ai/*`, `scripts/project/*`). The fan-out workflow closes
that gap so you never have to run `/github_kit_update` in each repo by hand.

[`.github/workflows/github-kit-fanout.yml`](.github/workflows/github-kit-fanout.yml) runs in
**github-kit itself** and:

- triggers on every push to `main` that touches `templates/**` or the install/update scripts, plus
  a weekly cron safety net and manual `workflow_dispatch`;
- reads the target list from [`.github/fanout-targets.json`](.github/fanout-targets.json) (add a
  repo by appending one `{ "repo": "owner/name", "tier": 1 }` entry — nothing is needed on the
  target side; `"base"` is optional and defaults to the repo's default branch, resolved at run
  time; see "Repository tiers" below);
- **skips, with a visible log line and no PR, any target that does not have the kit installed**
  (no `docs/ai/PROJECT_CONFIG.md` at its base branch) — unless the entry says `"install": true`,
  in which case the full installer runs there once and the resulting draft PR says so. The kit is
  never silently installed into a repo that never had it;
- for each installed target, refreshes its bootstrap files from `github-kit@main` via
  `update-github-kit.sh` and opens a **draft PR** on the repo's base branch if anything drifted —
  it never merges, never force-pushes, and never touches repo-specific files:
  `docs/ai/PROJECT_CONFIG.md` or `.github/workflows/pr-policy.yml` (which holds each repo's
  `required_base_branch` gate). The reusable policy *logic* still auto-tracks `@main`; only that
  repo's base-branch wiring is left alone. These PRs change `.github/workflows/*`, so
  `auto-merge.yml` can merge one only when the target has an `AUTOMERGE_TOKEN` with the workflow
  permission; otherwise a human merges it (see "Auto-merge after green" → token caveats).

**Required secret (one, in github-kit only):** `FANOUT_TOKEN`. The default
`GITHUB_TOKEN` can't reach other repos, which is why a PAT is needed. Until the secret exists, the
workflow fails fast with a clear message instead of silently doing nothing.

A **fine-grained** PAT (Contents: RW + Pull requests: RW on each target) is enough **only while
every target belongs to one account** — fine-grained PATs are scoped to a single resource owner and
cannot select repos you are merely an outside collaborator on. The target list now spans `pzoli6`
and `pszichocloud`, so it needs a **classic** PAT with the `repo` scope, created by an account
with push access to every target. Full instructions, including the least-privilege alternative:
**[docs/OWNER_SETUP.md](docs/OWNER_SETUP.md)**.

The mental model is: **you improve `github-kit`, and every repo gets a draft PR** — reusable CI
logic updates itself with no PR, and local files arrive as reviewable PRs.

## Single source of truth: the kit manifest

[`templates/docs/ai/KIT_MANIFEST.tsv`](templates/docs/ai/KIT_MANIFEST.tsv) lists every file the kit
installs, how install and update treat it (managed block, refresh, create-once, caller workflow),
which files `verify_agent_workflow.sh` requires, and the key phrases it checks. Everything that
used to keep its own copy of those lists now reads the manifest:

| Reader | Uses the manifest for |
|---|---|
| `install-github-kit.sh` / `.ps1`, `update-github-kit.sh` / `.ps1` (via `scripts/lib/kit.sh` / `Kit.ps1`) | which files to write and how |
| `verify_agent_workflow.sh` (installed as `docs/ai/KIT_MANIFEST.tsv` in every repo) | required files and phrases |
| `reusable-agent-workflow-verify.yml` | runs the repo's own `verify_agent_workflow.sh`, so CI and local checks agree |
| `github-kit-fanout.yml` | which paths to stage in the update PR |
| `doctor-github-kit.sh` / `.ps1` | every template is listed, repo-owned files keep a non-overwriting mode, managed blocks agree |

Managed-block text (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `REVIEW.md`) comes from each template's
own `<!-- BEGIN GITHUB-KIT ... -->` block; the scripts no longer carry a copy.

**Adding a template:** put the file under `templates/`, add one manifest row, run
`bash scripts/selfcheck-github-kit.sh`.

## Repository tiers

Every repo in `.github/fanout-targets.json` has a `tier` that decides how much of the shared Actions
budget it may spend automatically:

| Tier | CI and Agent Workflow Verify | Codex automatic review |
|---|---|---|
| **1** | run automatically on production-bound PRs and pushes | on |
| **2** | run only when dispatched by hand | off (`@codex review` on demand) |

The fan-out passes the tier to `update-github-kit.sh --tier`, which writes it into the refreshed CI
callers as a `# github-kit tier: N` line and keeps or drops the triggers between the
`# >>> github-kit tier-1 triggers` markers. A later update without `--tier` (for example
`/github_kit_update`) keeps the tier the file already has. `KIT_ACTIONS_PAUSED=true` still pauses a
repo completely, whatever its tier.

A repo without the kit gets it from the fan-out's first run when its entry says
`"install": true`; the tier applies from that install on. Tier 2 and auto-merge interact:
`auto-merge.yml` needs at least one check, so a ready PR in a tier 2 repo merges only after someone
dispatches its CI (or the repo sets `KIT_AUTOMERGE_ALLOW_NO_CHECKS=true`). The
Codex column is a setting in Codex, not something the kit can write; see
[docs/PR_REVIEW_SETUP.md](docs/PR_REVIEW_SETUP.md).

## PR review

`REVIEW.md` (installed in every repo, managed block plus a repo-specific section) is the one
rulebook for human reviewers, Codex, and Claude: what is blocking, what to always check, what to
skip, and how the PR's agent handles bot findings. Each tool's own instruction file points to it:
the `## Code Review Rules` section of the managed block in `AGENTS.md` (read by Codex) and
`CLAUDE.md`. Setup and the per-tier recommendation:
**[docs/PR_REVIEW_SETUP.md](docs/PR_REVIEW_SETUP.md)**.

## Checking github-kit itself

`bash scripts/selfcheck-github-kit.sh` runs the doctor, actionlint, `shellcheck -S error`, JSON
checks, and `scripts/test-install-update.sh`, which installs and updates throwaway repos with both
the bash and PowerShell scripts and asserts the kit's promises (repo-owned files survive, text
outside managed blocks is untouched, updates are idempotent, tiers round-trip, bash and PowerShell
produce identical trees). Missing optional tools are skipped locally. The
**github-kit selfcheck** workflow runs the same script with every tool installed, only when
dispatched by hand.

## Fast-path trigger: /github_kit

`/github_kit <task description>` is a pre-approved alternative entry point into the same lifecycle
above. Typing it is itself the human's approval for `<task>`, scoped strictly to that description —
the agent still writes a visible plan, still creates the issue and tracks it on the Project, still
opens a **draft** PR, still never merges or tags, but skips the separate wait for `approve`.
If the work turns out to need more than `<task>` described, the agent falls back to the normal
approval gate for the extra scope.

This is additive: `approve` remains the default gate for everything else, and
the existing `issue-to-pr-project` workflow is untouched. Each agent has its own entry point —
Claude Code's `/github_kit` slash command, the generic `.agents/skills/github_kit/SKILL.md` skill,
and the `.cursor/rules/github-kit-command.mdc` Cursor rule — see the table below and
[`templates/docs/ai/AGENT_WORKFLOW.md`](templates/docs/ai/AGENT_WORKFLOW.md) → "Fast-path trigger:
/github_kit" for the full spec.

`/github_kit` is unrelated to the always-latest `@main` channel above: it runs entirely from
whatever local files already exist in the repo's working tree and never requires network access.
Refreshing those local files from `pzoli6/github-kit@main` is a separate, optional command —
`/github_kit_update`, described next.

## Local bootstrap refresh: /github_kit_update

`@main` auto-tracking only covers reusable workflows. `AGENTS.md`/`CLAUDE.md`, Cursor rules,
Claude/Codex skills, `REVIEW.md`, and this kit's own helper scripts are local files
that lag behind until something explicitly refreshes them. `/github_kit_update`
(`.claude/skills/github_kit_update/SKILL.md`, `.agents/skills/github_kit_update/SKILL.md`) is that
something: it runs `update-github-kit.sh`/`.ps1` against `pzoli6/github-kit@main`, refuses a dirty
working tree unless told otherwise, never overwrites `docs/ai/PROJECT_CONFIG.md` unless
`--force-config`/`-ForceConfig`, never installs Project Sync unless requested, and always stops at a
**draft PR** for human review — it never merges. Unlike `/github_kit`, this command requires
actually reaching `github-kit@main`; if it can't, it stops and reports the block rather than
silently doing nothing. Run it whenever local bootstrap files seem stale — it's optional precisely
because the reusable-workflow callers already auto-track `@main` on their own.

## Enabling private reusable workflow access

> **Cross-account does not work, at all.** A private repo can only share its reusable
> workflows with repos owned by the **same** user or organisation — the Access setting offers no
> way to allow a repo owned by a different account. A caller in such a repo fails with `jobs = 0`
> and "This run likely failed because of a workflow file issue", which looks like a broken YAML
> file and isn't. If any target lives under a different account, **make `github-kit` public** —
> see [docs/OWNER_SETUP.md](docs/OWNER_SETUP.md) → "Making `github-kit` public".

If `github-kit` and your target repos are private **and owned by the same account**, the target
repo's `GITHUB_TOKEN` needs permission to call workflows in this repo:

1. In `pzoli6/github-kit` → **Settings → Actions → General → Access**, choose **"Accessible from
   repositories in the `pzoli6` organization/account"** (or explicitly allow the target repo).
2. In the target repo, the caller workflow's job needs at minimum:
   ```yaml
   permissions:
     contents: read
   ```
   Reusable workflows that call `gh project` commands additionally need a PAT with the `project`
   scope passed in as a secret (see below) — the default `GITHUB_TOKEN` cannot read/write Projects.
3. If both repos are public, no extra access configuration is required — public reusable workflows
   are callable from any repo.

## Working-tree requirements

Every install/update script (Bash and PowerShell) refuses to run against a target repo with
uncommitted changes, unless you pass `--allow-dirty` / `-AllowDirty`:

```text
target repository has uncommitted changes.
Commit or stash your work first, then re-run — or pass --allow-dirty if you understand the risk.
```

This exists because a script that copies/refreshes files is much easier to review (and revert, if
something looks wrong) against a clean `git diff` than mixed in with unrelated in-progress work.
Commit or `git stash` first; only reach for `--allow-dirty`/`-AllowDirty` if you've deliberately
decided to review everything together afterward.

## Installing into an existing repo

### Linux / macOS / WSL / Git Bash

```bash
gh auth login
gh auth refresh -s project   # needed for Project read/write via gh

git switch -c agent/install-github-kit
/path/to/github-kit/scripts/install-github-kit.sh --target . --mode merge
git status
git diff --stat
```

### Windows (PowerShell)

```powershell
gh auth login
gh auth refresh -s project   # needed for Project read/write via gh

git switch -c agent/install-github-kit
& "C:\path\to\github-kit\scripts\install-github-kit.ps1" -Target . -Mode merge
git status
git diff --stat
```

Both installers behave identically: they copy in any managed file that's missing, insert/update a
managed block in your existing `AGENTS.md`/`CLAUDE.md` instead of overwriting them, and never touch
`docs/ai/PROJECT_CONFIG.md` if it already exists. Review the diff, fill in
`docs/ai/PROJECT_CONFIG.md` with your repo's Project number/base branch/validation commands, copy
`docs/ai/PROJECT_CONFIG.env.example` to `docs/ai/PROJECT_CONFIG.env` (git-ignored) for the local
helper scripts, commit, and open a PR.

`.github/workflows/project-sync.yml` is **not installed by default** by either installer — pass
`--include-project-sync` / `-IncludeProjectSync` once you've set up a real GitHub Project and an
`AGENT_PROJECT_TOKEN` secret (see "Configuring the Project number and token" below, and "Why
Project Sync is Phase 2" further down).

## Creating a new repo from this kit

Until a dedicated `template` repository exists, the same installers work on a brand-new repo:

```bash
gh repo create pzoli6/new-repo --private --clone
cd new-repo
/path/to/github-kit/scripts/install-github-kit.sh --target . --mode merge
```

```powershell
gh repo create pzoli6/new-repo --private --clone
Set-Location new-repo
& "C:\path\to\github-kit\scripts\install-github-kit.ps1" -Target . -Mode merge
```

## Configuring the Project number and token

1. Find your Project number: `gh project list --owner pzoli6`.
2. Fill in `docs/ai/PROJECT_CONFIG.md` (`GitHub Project owner` / `GitHub Project number`) and copy
   `docs/ai/PROJECT_CONFIG.env.example` → `docs/ai/PROJECT_CONFIG.env` for local script use.
3. Create a classic PAT (or fine-grained PAT) with the `project` scope, add it to the target repo
   as secret `AGENT_PROJECT_TOKEN` (Settings → Secrets and variables → Actions) — this is what the
   `project-sync.yml` caller workflow passes to `reusable-project-sync.yml`.

## Optional: standard labels

`templates/scripts/project/create_standard_labels.sh` creates (or updates, via `--force`) a set of
`status:`/`type:`/`risk:` labels used for filtering issues/PRs. It's installed by both installers
automatically, but never run automatically — labels are a convenience, not a requirement:

```bash
gh auth login   # needs repo scope
scripts/project/create_standard_labels.sh
```

Their absence never blocks creating an issue, opening a PR, or moving a tracked item through the
workflow — see "Project Sync and labels (optional)" in `templates/AGENTS.md`.

## Why Project Sync is Phase 2

`.github/workflows/project-sync.yml` would update Project fields (`Status`, `PR URL`, etc.)
automatically from PR/issue activity. It's deliberately **not** part of the default install
because it needs two things most repos don't have on day one:

1. A real GitHub Project already created, with its number filled into `docs/ai/PROJECT_CONFIG.md`.
2. An `AGENT_PROJECT_TOKEN` secret with `project` scope — the default `GITHUB_TOKEN` can't read or
   write Projects.

Until both exist, agents update Project fields manually with `scripts/project/project_set_status.sh`
/ `project_set_text.sh` (or by editing the Project UI) at each phase transition — see "When Project
Sync isn't enabled" in `templates/docs/ai/AGENT_WORKFLOW.md`. Add it later with
`--include-project-sync` / `-IncludeProjectSync` on either installer/updater once the prerequisites
are in place, and flip `Project Sync enabled` to `true` in `docs/ai/PROJECT_CONFIG.md`.

## Pausing and resuming work (AI usage limits)

AI coding agents (Codex, Claude Code, and others) can hit a usage limit mid-task. `github-kit`
treats that as a controlled pause, not an abandoned task — commit or `git stash` what's in
progress, write a handoff file describing exactly what's stashed and how to resume, and set the
Project's `Status` to `Blocked` with the reason. The next session (same agent, later, or a
different tool entirely) reads the handoff file before touching the worktree. Full procedure:
"Pausing for AI usage limits" and "Resuming stashed work" in
[`templates/docs/ai/AGENT_WORKFLOW.md`](templates/docs/ai/AGENT_WORKFLOW.md).

## How AI agents should use this

| Agent | Entry point |
|---|---|
| Claude Code | Reads `CLAUDE.md`, which points to `AGENTS.md` + `docs/ai/PROJECT_CONFIG.md` + `docs/ai/AGENT_WORKFLOW.md`. Also has a Claude Skill at `.claude/skills/issue-to-pr-project/SKILL.md`, and the fast-path `/github_kit` slash command (`.claude/commands/github_kit.md`, runbook `.claude/skills/github_kit/SKILL.md`). |
| ChatGPT Codex | Reads `AGENTS.md` directly (the tool-agnostic universal rules file) plus the generic skill at `.agents/skills/issue-to-pr-project/SKILL.md` (and its fast-path counterpart, `.agents/skills/github_kit/SKILL.md`). |
| Cursor agents | Load `.cursor/rules/agent-workflow.mdc`, `git-safety.mdc`, `project-board.mdc`, and `github-kit-command.mdc` (the `/github_kit` fast-path trigger). |
| Antigravity / ChatGPT with repo context / future agents | Read `AGENTS.md` — it is intentionally tool-agnostic and is the fallback entry point for any agent without a dedicated adapter, including recognizing the `/github_kit` trigger. |
| Manual development | Same lifecycle, same Project statuses — `AGENTS.md` and `docs/ai/AGENT_WORKFLOW.md` describe the human-authored path too. |

## Handoff files solve token-limit continuation

When an agent runs out of context/tokens mid-task, it writes its current state to
`docs/ai/handoffs/issue-<number>.md` and updates the Project's `Last Agent Update` and `Validation`
fields before stopping. The next agent (same tool or a different one entirely) reads that file
instead of re-deriving context from scratch, so a task can move from one tool to another
mid-stream. See
[`templates/docs/ai/HANDOFF_INDEX.md`](templates/docs/ai/HANDOFF_INDEX.md).

## Worktree-per-task lifecycle

Because multiple agents work a repo in parallel, every task runs in its own git worktree —
`scripts/project/publish_agent_branch.sh --issue <issue> --slug <short>` fetches and forks a
**real** worktree from `origin/<base branch>` (its own checkout + `.git` file, registered in
`git worktree list`), pushes the branch, and prints the worktree path. It also drops a
`WORKTREE.md` preamble into the worktree — issue number, base branch, a unique per-worktree dev
port, dev-server command, preview/QA route, auth notes, and key paths sourced from
`docs/ai/PROJECT_CONFIG` — so an agent doesn't burn its first dozen calls reverse-engineering the
setup. Configure those facts once per repo in `docs/ai/PROJECT_CONFIG.env` (see "Worktree and
dev-environment facts" in `templates/docs/ai/PROJECT_CONFIG.md`).

Once an agent learns a PR has merged, it runs
`scripts/project/cleanup_merged_branches.sh --branch <branch>` (or with no `--branch` to sweep
every local branch matching the configured agent prefixes — `agent/`, `claude/`, `codex/` by
default — at once). For a merged branch it **removes the worktree,
deletes the local branch, and closes the linked issue** (Project `Status` → `Done` plus
`gh issue close`) — but only when its PR is actually `MERGED`, the local tip matches exactly what
GitHub merged, and the worktree has no unsaved work beyond the kit's own scratch files. Anything
that fails a check is left alone with a `SKIPPED: <reason>` line instead of being force-removed —
the remote branch is never touched. See `templates/AGENTS.md` → "Branch and worktree rules".

## Updating target repos later

### Linux / macOS / WSL / Git Bash

```bash
git switch -c agent/update-github-kit
/path/to/github-kit/scripts/update-github-kit.sh --target .
git status
git diff --stat
```

### Windows (PowerShell)

```powershell
git switch -c agent/update-github-kit
& "C:\path\to\github-kit\scripts\update-github-kit.ps1" -Target .
git status
git diff --stat
```

Both updaters refresh managed files and managed blocks (caller workflows stay pinned to literal
`@main` unless you pass `--ref`/`-Ref` to deliberately repoint them) but never overwrite
`docs/ai/PROJECT_CONFIG.md` or `docs/ai/PROJECT_CONFIG.env` unless you pass `--force-config` /
`-ForceConfig`.

## Pinning to a fixed ref (opt-out of the main channel)

Target repos default to the always-latest `@main` channel (see above) and need no action to stay
current. If you'd rather pin a repo to a fixed tag or commit SHA instead — e.g. to freeze behavior
during a migration, or to review `github-kit` changes before they land — pass `--ref`/`-Ref` to the
installer or updater:

```bash
/path/to/github-kit/scripts/update-github-kit.sh --target . --ref v0.3.0
```

```powershell
& "C:\path\to\github-kit\scripts\update-github-kit.ps1" -Target . -Ref v0.3.0
```

This repoints only the `uses: pzoli6/github-kit/...` lines in caller workflows — it never touches
unrelated occurrences of "main" (e.g. `branches: [main, develop]` triggers). Afterward, update
`docs/ai/PROJECT_CONFIG.md`: set `github-kit ref` to the pinned value and `github-kit update mode`
to `pinned`, so agents and the verifier know not to expect auto-updates. To move a pinned repo to a
newer ref later, re-run the same command with a different `--ref`/`-Ref` value.

## Recommended rollout sequence

For a brand-new repo, in order:

1. Install with the default flags (`--mode merge`, no `--include-project-sync`).
2. Fill in `docs/ai/PROJECT_CONFIG.md` (Project name/number, base branch, validation commands,
   forbidden files).
3. Optional: run `create_standard_labels.sh` once `gh auth login` has repo scope.
4. If the repo's GitHub plan supports it, enable branch protection / required status checks by
   hand — `github-kit` won't do this for you, and most repos start without it (see "Free-tier
   usage and branch protection" above).
5. Once a real GitHub Project and `AGENT_PROJECT_TOKEN` exist, re-run the installer/updater with
   `--include-project-sync` to add automatic field syncing — treat this as a deliberate Phase 2
   step, not part of initial setup.

Run `scripts/doctor-github-kit.sh` (or `.ps1`) inside `github-kit` itself — not a target repo —
before tagging a new release, to catch packaging regressions (CRLF line endings, stale Action
versions, template caller workflows missing literal `@main`, stale `GITHUB_KIT_VERSION`
placeholders, missing required files/phrases).

## Versioning

Tags (`v0.1.0`, `v0.2.0`, ...) remain available as optional pin targets for repos that opt out of
the always-latest `@main` channel (see "Pinning to a fixed ref" above) — they are no longer the
default for new installs. Bump the minor version for additive changes (new optional
scripts/templates, new flags with safe defaults) and the patch version for fixes that don't change
behavior for repos that don't opt in to anything new. See
[`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md) for the exact tagging procedure — tagging
is a human action taken after a hardening/feature PR merges, never something an agent does as part
of implementing that PR, and is now a courtesy for pinned repos rather than a required release step.
