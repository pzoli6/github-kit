---
name: github_kit_update
description: Refresh this repo's local github-kit bootstrap files (AGENTS.md/CLAUDE.md managed block, skills, Cursor rules, copilot-instructions.md, docs/ai/AGENT_WORKFLOW.md, project helper scripts) from pzoli6/github-kit@main by opening a draft PR. Use when a user explicitly invokes /github_kit_update, or asks to refresh/sync this repo's github-kit bootstrap files.
---

# github_kit_update

Unlike `/github_kit`, this command **requires** reaching `pzoli6/github-kit@main` — its entire
purpose is pulling the latest central bootstrap content. If `github-kit@main` isn't reachable
(no local clone, no network, no `gh`/git access), stop and report that explicitly rather than
silently doing nothing.

This command only touches **local bootstrap files** — `AGENTS.md`/`CLAUDE.md` managed block,
`.claude`/`.agents` skills, `.cursor/rules`, `.github/copilot-instructions.md`,
`docs/ai/AGENT_WORKFLOW.md`, `docs/ai/HANDOFF_INDEX.md`, project helper scripts, CODEOWNERS, and
the reusable-workflow *caller* templates (which already auto-track `@main` and rarely need this).
It never touches `docs/ai/PROJECT_CONFIG.md` unless `--force-config` is explicitly requested, and
never installs Project Sync unless `--include-project-sync`/`-IncludeProjectSync` is explicitly
requested.

## Steps

1. **Clean repo check.** Run `git status`. Refuse to continue against a dirty working tree unless
   the human has explicitly said to proceed anyway (mirrors `update-github-kit.sh`'s own
   `--allow-dirty` gate — don't silently pass `--allow-dirty` on the human's behalf).
2. **Locate `github-kit@main`.** In order of preference:
   - If a local clone of `pzoli6/github-kit` is already available at a known path, use it directly.
   - Otherwise, shallow-clone it: `git clone --depth 1 --branch main https://github.com/pzoli6/github-kit.git <tmpdir>`.
   - If neither is possible (no network, no `git`/`gh` access), stop here and report the block —
     do not fall back to local-only behavior; that would silently skip the update this command
     exists to perform.
3. **Run the updater against this repo** from the located/cloned github-kit:
   ```bash
   bash <github-kit>/scripts/update-github-kit.sh --target . --ref main
   ```
   (or `update-github-kit.ps1 -Target . -Ref main` on Windows). Add `--allow-dirty`/`-AllowDirty`
   only if step 1 explicitly cleared it with the human.
4. **Clean up** any temporary clone made in step 2.
5. **Review the diff.** Confirm `docs/ai/PROJECT_CONFIG.md` and any repo-specific content outside
   the `AGENTS.md`/`CLAUDE.md` managed block were left untouched, and that
   `.github/workflows/project-sync.yml` was not created unless it already existed or was
   explicitly requested.
6. **Branch, commit, push, open a draft PR.** Use a branch like `agent/update-github-kit-bootstrap`,
   stage explicit files (never `git add -A` / `git add .`), commit, push, and open a **draft** PR
   describing what refreshed and why. Never merge it — that's a human action.
7. **Stop for human review.** This command never merges automatically, regardless of how clean the
   diff looks.

## Hard rules

- Never run without reaching `github-kit@main` first — report blocked instead of proceeding on
  stale local assumptions.
- Never overwrite `docs/ai/PROJECT_CONFIG.md` unless `--force-config`/`-ForceConfig` was explicitly
  requested.
- Never install `.github/workflows/project-sync.yml` unless explicitly requested.
- Never proceed against a dirty working tree without explicit human sign-off.
- Never merge or tag — open a draft PR and stop.
- This command is optional: central reusable workflows already auto-track `@main` on their own:
  this only matters for *local* bootstrap files, which lag behind until this is run.
