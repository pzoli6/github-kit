# PR_REVIEW_SETUP.md — AI pull-request review, set up once

The kit gives every installed repo one review rulebook, `REVIEW.md`, and points each reviewer at
it. This page is the owner's setup: which reviewer runs where, what it costs, and how to steer it.
Nothing here runs in the kit's CI; every reviewer below is a GitHub App or a local command, so none
of them spends the account's Actions minutes.

## How control works

| Reviewer | Reads | Set up in |
|---|---|---|
| Codex code review | `AGENTS.md` → `## Code Review Rules` (the kit's managed block points it to `REVIEW.md`) | ChatGPT → Codex settings → Code review |
| Claude Code `/code-review` (local) | `CLAUDE.md` (the managed block points it to `REVIEW.md`) | nothing: run it in a session |
| Claude Code Review (managed, Team/Enterprise plans) | `REVIEW.md` directly, plus `CLAUDE.md` | claude.ai admin settings → Claude Code → Code Review |
| Copilot code review | `.github/copilot-instructions.md` (points to `REVIEW.md`) | GitHub → Settings → Copilot → Code review |
| Humans | `REVIEW.md` | nothing |

To change what gets flagged, edit **Repository-specific rules** in that repo's `REVIEW.md`. To
change the rules for every repo, edit the `GITHUB-KIT REVIEW RULES` block in
`templates/REVIEW.md` here; the fan-out carries it everywhere.

Keep `REVIEW.md` short. Every added rule dilutes the others, and linters, formatters, and type
checkers in CI should own anything mechanical.

## Recommended setup per tier

Tiers are recorded in `.github/fanout-targets.json` (see README → "Repository tiers").

| | Tier 1 | Tier 2 |
|---|---|---|
| Codex automatic review | on | off; comment `@codex review` when a PR matters |
| Claude `/code-review high` before marking ready | always | for risky changes |
| Claude `/code-review ultra` (cloud, deeper) | for auth, data, migration, or money changes | rarely |
| Copilot review | off (no subscription) | off |

Why this split: Codex reviews run inside the ChatGPT plan's usage limits, and those limits are
shared with Codex coding work. Automatic review on every repo spends them on PRs nobody is waiting
for. The kit's own fan-out PRs (`agent/github-kit-selfupdate-*`) are listed under "Do not review" in
`REVIEW.md`, but an automatic reviewer still starts on them, which is one more reason to keep
automatic review to Tier 1.

## One-time steps

1. **Codex**: in ChatGPT, open Codex settings, connect GitHub if needed, and enable automatic code
   review for each Tier 1 repository. Codex reports only high-priority (P0/P1) findings.
2. **Claude**: nothing to install. In a Claude Code session on the PR's branch, run
   `/code-review high`. `/code-review ultra` runs a deeper review in the cloud and uses plan usage.
3. **Copilot**: if a subscription is ever active again, turn off "Review draft pull requests" and
   "Review new pushes" in GitHub → Settings → Copilot → Code review. Kit PRs open as drafts and get
   many pushes, and Copilot review may draw on Actions minutes.
4. Refresh each repo (`/github_kit_update` or the fan-out) so it has `REVIEW.md` and the
   `## Code Review Rules` pointer.

## Handling what reviewers post

`REVIEW.md` → "Handling reviewer findings" is the rule for the agent that owns the PR: classify each
finding as fix, dismiss, or ask; reply once; resolve the thread. A 👍/👎 on a Claude Code Review
comment tunes that reviewer; replying to it does not trigger a re-review.
