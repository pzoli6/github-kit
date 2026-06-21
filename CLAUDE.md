# CLAUDE.md — github-kit (this repository)

Read [`AGENTS.md`](AGENTS.md) first — it is the source of truth for working on this repo.

This file exists only to tell Claude Code two things AGENTS.md can't say on its own:

1. **`templates/CLAUDE.md` is not your instruction file.** It's payload that gets installed into
   *other* repositories. If you're editing `github-kit` itself, follow the root `AGENTS.md`, not
   anything under `templates/`.
2. **Plan first, wait for approval, never merge.** For routine work on this repo, wait for
   `approve issue-to-pr-project` before branching/implementing, same as any repo using this kit.
   The one exception is `/github_kit <task>` (see `.claude/commands/github_kit.md` and
   `.claude/skills/github_kit/SKILL.md`) — that invocation is itself the approval for `<task>`.
   Before stopping or running low on context, update the relevant `docs/ai/handoffs/issue-<n>.md`
   in whichever target repo you're tracking the task against — `github-kit` itself doesn't carry
   its own Project/issue tracking beyond standard GitHub issues/PRs. Never merge a PR; that's a
   human action.
3. **`/github_kit_update` doesn't apply to this repo's own root files.** `.claude/skills/
   github_kit_update/SKILL.md` exists here only for dogfooding the skill's *content*; it would have
   nothing meaningful to refresh against `github-kit`'s own root `AGENTS.md`/`CLAUDE.md`, since
   those are this repo's own instruction files, not an install of `templates/`.
