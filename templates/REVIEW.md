# REVIEW.md — review rules for this repository

This file tells every reviewer of a pull request what to flag, at what severity, and what to leave
alone: human reviewers, Codex code review, and Claude (Code Review and `/code-review`).
It is the single rulebook; each tool's own instruction file only points here.

The block between the `GITHUB-KIT REVIEW RULES` markers is maintained by `pzoli6/github-kit` and is
refreshed by `/github_kit_update` or the fan-out. Put this repository's own rules in
**Repository-specific rules** below the block; the updater never touches text outside the markers.

<!-- BEGIN GITHUB-KIT REVIEW RULES -->
## Review rules (github-kit)

### Severity

- **Blocking** (Codex P0/P1, Claude 🔴 Important): a defect that breaks behavior, loses or leaks
  data, exposes a secret, weakens auth or a permission, breaks a migration or rollback, or breaks
  the contract of a reusable workflow, script CLI flag, or config file other repositories consume.
- **Nit** (Claude 🟡, human "optional"): naming, structure, comments, docs wording. Never blocking.
- Anything a linter, formatter, or type checker in CI already enforces: do not report.

### Always check

- No secrets, tokens, or real `docs/ai/PROJECT_CONFIG.env` values in the diff.
- GitHub Actions: no `${{ github.event.* }}` or `github.head_ref` expanded directly inside a `run:`
  script (pass it through `env:` and quote it); `permissions:` no wider than the job needs; every
  reusable-workflow job keeps its `vars.KIT_ACTIONS_PAUSED != 'true'` guard.
- Scripts that write into a repository check existence/ownership before overwriting, and never
  touch text outside `<!-- BEGIN GITHUB-KIT ... -->` / `<!-- END GITHUB-KIT ... -->` markers.
- A behavior change comes with a test, or the PR says how it was validated.

### Evidence bar

- A behavior claim needs a `file:line` citation from the source, not an inference from a name.
- Trace a suspected bug to the call path that triggers it before reporting it as blocking.

### Volume and re-reviews

- Report at most five nits per review; summarize the rest as a count.
- Open the summary with a one-line tally, for example `1 blocking, 3 nits`, or `No blocking issues`.
- After the first review of a PR, report new blocking findings only.

### Do not review

- Lockfiles, generated or vendored files, and minified assets.
- Draft PRs on branches named `agent/github-kit-selfupdate-*`: these are automated github-kit
  updates whose content was already reviewed in `pzoli6/github-kit`. Check only that the diff stays
  inside github-kit-owned paths (listed in `docs/ai/KIT_MANIFEST.tsv`).

### Handling reviewer findings (for the agent that owns the PR)

Classify every bot finding before acting on it:

- **fix**: a plausible correctness, security, data, auth, migration, idempotency, or race issue.
  Fix it, reply with the commit, resolve the thread.
- **dismiss**: the current code proves no change is needed. Reply with the one-line reason,
  resolve the thread.
- **ask**: novel, high-severity, security-related, or ambiguous. Ask the human instead of guessing.

When unsure, ask. Skipping a noisy style comment is cheap; skipping a real data or security bug is
not. (Adapted from pstack's Bugbot triage rubric, MIT.)
<!-- END GITHUB-KIT REVIEW RULES -->

## Repository-specific rules

<!-- Add this repository's own review rules here: what counts as blocking in this codebase, paths
     that need extra scrutiny, and paths to skip. Keep it short; long rule files dilute the rules
     that matter. -->
