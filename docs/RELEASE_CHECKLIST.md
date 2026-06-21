# RELEASE_CHECKLIST.md — Tagging a github-kit release

Tagging is a **human action**, taken after a hardening/feature PR has been reviewed and merged —
never something an agent does as part of implementing that PR. An agent may prepare this checklist
and point to it from a PR description, but must not run the `git tag` / `git push --tags` commands
below itself.

## Before tagging

- [ ] The PR containing the changes for this release has been reviewed and merged to `main`.
- [ ] `main` is checked out locally and up to date: `git switch main && git pull`.
- [ ] `bash scripts/doctor-github-kit.sh` passes with no `MISSING`/`FAILED` lines.
- [ ] `pwsh -File scripts/doctor-github-kit.ps1` (or `powershell -File ...` on Windows) passes with
      no `MISSING`/`FAILED` lines.
- [ ] `bash -n scripts/*.sh` and `bash -n templates/scripts/project/*.sh` report no syntax errors.
- [ ] Both `scripts/install-github-kit.ps1` and `scripts/update-github-kit.ps1` parse cleanly:
      `[System.Management.Automation.Language.Parser]::ParseFile(...)` reports zero errors.
- [ ] A dry-run install into a fresh temp repo (`install-github-kit.sh` and `install-github-kit.ps1`,
      at least one of the two on this machine) creates the expected files and does **not** install
      `.github/workflows/project-sync.yml` by default.
- [ ] `docs/RELEASE_CHECKLIST.md` (this file) and `README.md`'s "Versioning" section agree on the
      version-bump policy being applied.
- [ ] The new version number has been decided: bump **minor** for additive, backward-compatible
      changes (new optional scripts/templates/flags with safe defaults); bump **patch** for fixes
      that don't change behavior for repos that don't opt in to anything new; bump **major** only
      for a breaking change to an existing default (rare — avoid if at all possible).

## Tagging

Run from `main`, after every box above is checked:

```bash
git tag -a vX.Y.Z -m "vX.Y.Z — <one-line summary of what changed>"
git push origin vX.Y.Z
```

Replace `vX.Y.Z` with the decided version (e.g. `v0.3.0`). The annotated tag message should
summarize the release in one line — detail belongs in the merged PR's description, not the tag.

## After tagging

- [ ] Update any target repo you control to the new ref when convenient (not required
      immediately): `update-github-kit.sh --target . --workflow-ref vX.Y.Z` /
      `update-github-kit.ps1 -Target . -WorkflowRef vX.Y.Z`, then bump the `github-kit version` /
      `Workflow ref` rows in that repo's `docs/ai/PROJECT_CONFIG.md` to match.
- [ ] If this release fixes a regression that affected already-installed repos (e.g. the DancePass
      CRLF/Node-version/`@main` issues this kit was hardened against), consider proactively
      flagging those repos rather than waiting for them to notice on their own.
- [ ] Optionally create a GitHub Release from the tag (`gh release create vX.Y.Z --generate-notes`)
      if you want release notes visible in the repo UI — not required for the kit to function.
