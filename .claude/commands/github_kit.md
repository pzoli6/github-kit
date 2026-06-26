---
description: Run the issue-to-PR-Project workflow for a task, pre-approved by this invocation
argument-hint: <task description>
---

Run the `github_kit` skill for this task:

$ARGUMENTS

Treat this `/github_kit` invocation itself as the human's approval for the task described in
`$ARGUMENTS` — do not stop and wait for a separate `approve` reply. Everything
else (plan visibility, issue creation, Project tracking, branch/worktree, implementation,
validation, draft PR, handoff) follows `.claude/skills/github_kit/SKILL.md` exactly, which in turn
follows `AGENTS.md` and `docs/ai/AGENT_WORKFLOW.md`.

If `$ARGUMENTS` is empty, ask the human what task to run before doing anything else — `/github_kit`
with no task description is not itself a task.
