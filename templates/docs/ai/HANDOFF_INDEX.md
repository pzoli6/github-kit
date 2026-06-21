# HANDOFF_INDEX.md

`docs/ai/handoffs/` holds one file per issue: `issue-<number>.md`. A handoff file is how an agent
that's stopping mid-task — out of context, end of session, or switching to a different AI tool —
hands the task to whoever picks it up next, without forcing them to re-derive state from scratch.

## Rules

- **One handoff file per issue** — `handoffs/issue-42.md`, not a single shared log for every task.
  Per-issue files mean two agents working on two different issues never touch the same file.
- **Avoid concurrent edits to any shared index.** This file intentionally does *not* maintain a
  live table of "current handoffs" — that table would itself become a concurrency hazard (two
  agents racing to update one index file). If you need to see what's in flight, list the
  directory or check the Project board's `Handoff` field, don't maintain a second source of truth
  here.
- Each handoff file should be self-contained: current state, what's done, what's left, open
  decisions/blockers, and the exact next step — written so a different agent (or a human) can
  continue without reading the prior conversation.
- Update the Project's `Last Agent Update` and `Validation` fields whenever you update a handoff
  file (see `AGENTS.md` → Handoff rules).
- It's fine to delete or archive a handoff file once its issue is `Done` or `Cancelled`.
