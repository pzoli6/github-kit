# AGENTS.md — github-kit (this repository)

> **Scope note:** this file governs work *on* `github-kit` itself. The files under
> [`templates/`](templates/) (including `templates/AGENTS.md` and `templates/CLAUDE.md`) are
> **payload** — they get copied into *other* repositories by `scripts/install-github-kit.sh`. Do
> not follow `templates/AGENTS.md` as if it were this repo's rules; it isn't. If you're an agent
> working inside `github-kit`, this file is your instruction file.

## What this repo is

`github-kit` is the **canonical source** of the reusable issue-to-PR-to-Project workflow used by
every other repo that installs it. It is tool-agnostic (Claude Code, Codex, Copilot, Cursor,
Antigravity, Gemini, ChatGPT, manual dev) and repo-agnostic — nothing repo-specific belongs here. Anything
that varies per target repo (Project number, base branch, validation commands, forbidden files)
must live in the target repo's `docs/ai/PROJECT_CONFIG.md`, never hardcoded into a template or
reusable workflow here.

## Review bar for this repo

Because a single change here can silently propagate to every repo that calls
`@main`/`@<tag>` of a reusable workflow or re-runs the installer, changes are held to a higher bar
than a typical app repo:

- **Changes to `templates/`, `.github/workflows/reusable-*.yml`, and
  `.github/workflows/github-kit-fanout.yml` must be carefully reviewed** — treat them as a public
  API surface for other repos, not internal implementation detail. The fan-out workflow (with its
  `.github/fanout-targets.json` list) has the widest blast radius of anything here: it can open a
  PR in every target repo, so review it as the highest-stakes file in the repo.
- **Never break backward compatibility without documenting a migration.** If an input, required
  file, key phrase, Project field name/status, or script CLI flag changes in a breaking way, add a
  note to this file (or a `CHANGELOG.md` if one exists) explaining what changed and what target
  repos need to do. Prefer additive changes (new optional input with a default) over breaking ones.
- **CI/CD must stay subscription-free.** Nothing under `templates/` or `.github/workflows/` may
  require a paid plan or subscription to run — no GitHub Copilot invocation or Copilot-review
  dependency, no GitHub Advanced Security/CodeQL requirement, no paid Marketplace actions, apps,
  or runners. Adapter files for subscription tools (e.g. the Copilot adapter
  `templates/.github/copilot-instructions.md`) stay inert payload that CI never invokes, and
  their presence must be individually opt-outable in verification (`require_copilot`-style
  inputs), so a repo owner without that subscription loses nothing.
- **Managed blocks must preserve target-repo custom content.** Anything `install-github-kit.sh` /
  `update-github-kit.sh` writes into an existing `AGENTS.md`/`CLAUDE.md` must be confined to the
  `<!-- BEGIN GITHUB-KIT UNIVERSAL WORKFLOW -->` / `<!-- END ... -->` markers. Never rewrite content
  outside those markers, and never assume the file doesn't already have unrelated content above or
  below the block.
- **Scripts must be safe and non-destructive by default.** No script in this repo may delete or
  overwrite a file in a target repo without an explicit existence/ownership check first (see the
  managed-block / "create only if missing" rules in `scripts/install-github-kit.sh`). Prefer
  failing loudly over guessing.
- **No secrets should be committed.** `AGENT_PROJECT_TOKEN` and any `PROJECT_CONFIG.env` file are
  supplied by the target repo's own secrets/local env — never hardcode a token, and never add a
  real `docs/ai/PROJECT_CONFIG.env` (only the `.env.example` template) anywhere in this repo or its
  templates.

## Working on this repo

This repo follows the same lifecycle it defines for everyone else: plan → human approval → branch
→ implementation → validation → draft PR → human review/merge. The approval phrase for routine
feature work on `github-kit` is `approve`, same as any other repo using this kit. (The one-off
setup of this repository's initial structure used the separate phrase
`APPROVED: setup github-kit`, scoped to that single bootstrap task; later one-off structural tasks
used `APPROVED: update github-kit` and `APPROVED: implement universal github-kit trigger`, each
scoped to its own task.)

This repo also carries its own root copies of the `/github_kit` fast-path adapters (`.claude/
commands/github_kit.md`, `.claude/skills/github_kit/SKILL.md`, `.agents/skills/github_kit/
SKILL.md`, `.cursor/rules/github-kit-command.mdc`) and the `/github_kit_update` skill (`.claude/
skills/github_kit_update/SKILL.md`, `.agents/skills/github_kit_update/SKILL.md`) so that working on
`github-kit` itself dogfoods the same triggers every target repo gets — see
`templates/docs/ai/AGENT_WORKFLOW.md` → "Fast-path trigger: /github_kit" and "Local bootstrap
refresh: /github_kit_update" for the spec. Note that `github-kit`'s own root `AGENTS.md`/`CLAUDE.md`
are this repo's *own* instruction files, not copies installed from `templates/` — `/github_kit_update`
would have nothing meaningful to refresh against them, since this repo doesn't install itself.

Agents must not push to `main`, merge PRs, modify Actions access settings, or commit secrets.
