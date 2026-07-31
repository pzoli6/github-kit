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
  inputs), so a repo owner without that subscription loses nothing. The mirror-image rule also
  holds: the kit must never crowd out a human's *manual* use of a subscription tool — Copilot
  coding agent runs share the caller account's Actions budget with kit CI, so every reusable
  workflow job must keep honoring the caller repo's `KIT_ACTIONS_PAUSED` Actions variable
  (skip = zero minutes) and avoid wasting minutes on superseded PR runs.
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

## CI expectations for work on this repo

This repo runs no CI on pull requests — its workflows are reusable (`workflow_call`) definitions
consumed by other repos, plus the fan-out job. A PR here showing **no checks at all is normal and
expected**: don't fetch check runs, wait, poll, subscribe to PR activity, dispatch a workflow, or
report "CI didn't run"/"checks are missing"/"the PR is red". Validate locally instead (YAML parses,
cross-references resolve, phrase lists still satisfied) and report that. This mirrors the rule the
kit installs into target repos — `templates/AGENTS.md` → "CI expectations — don't chase checks" —
so working here dogfoods it.

## Migration notes

### Spec approval by comment (`/approve-spec`)

The design-handoff gate used to accept only an `APPROVED` review. GitHub never lets anyone approve
their own PR, so on a **solo repo** — where an agent opens the spec PR with the owner's token — the
Approve button is never offered and the gate could not fire at all. The gate now also accepts a PR
comment whose first line is exactly `/approve-spec`, which the owner *can* post on their own PR.

Additive on every surface: `reusable-design-handoff-approval.yml` gained `allow_comment_approval`
(**default `false`** — an existing caller keeps review-only behaviour) and `comment_marker`;
`stamp.mjs` still accepts `--review-id` and defaults `--via` to `review`; `verify.mjs` reads a spec
with no `approval-via` key as `review`, so specs stamped before this change keep verifying. New
front-matter keys are `approval-via` and `approval-comment-id`.

**What a target repo must do to get it:** the reusable workflow auto-tracks `@main`, but the caller
`.github/workflows/design-handoff-approval.yml` lives in the target repo and needs the
`issue_comment` trigger plus `allow_comment_approval: true`. Until that file is refreshed — via
`/github_kit_update` or the fan-out — comment approval will not fire there, with no error to
explain why. Repos with a real second reviewer should instead keep `allow_comment_approval: false`,
which preserves GitHub's structural guarantee that the PR author cannot be the approver.

`verify.mjs` additionally re-checks that the approver holds write access, which it did not do
before. A marker naming a login that has since lost write access now fails closed.

### Automatic GitHub Project setup (project-setup workflow + setup script)

The Project board a target repo needs (fields, Status options, repo link) used to be hand-built,
and nothing verified it. Now `templates/scripts/project/setup_github_project.sh` carries the
board contract as code (idempotent ensure/doctor modes, never renames or removes anything), and
`reusable-project-setup.yml` + the caller `templates/.github/workflows/project-setup.yml` run it
automatically: on merge of a kit update (or manual dispatch), with the `AGENT_PROJECT_TOKEN`
secret present, the board is created/completed and a draft PR pins the resolved project number
into the caller files and `PROJECT_CONFIG.md`. Without the secret the job skips green with a
notice. `templates/docs/ai/PROJECT_SETUP.md` is the guide.

**Behavior changes existing repos should know about:**

- `update-github-kit.sh`/`.ps1` now treat `.github/workflows/project-sync.yml` as **create-only**
  (like `pr-policy.yml`) instead of refreshing it. Refreshing used to reset a configured repo's
  `project_number` back to `"TBD"` on every update, silently breaking Project Sync. Repos whose
  sync config was clobbered by an earlier refresh get it restored by the project-setup config PR.
- `create_agent_pr.sh` now writes the metadata fields (plus `Base Branch`/`Branch`) to the
  **PR's own** Project item as well as the linked issue's — they are distinct items, and the
  `check_project_fields` CI gate inspects the PR's item, which previously never received a
  single field from any script.
- All Project-touching scripts now fall back to the **main checkout's**
  `docs/ai/PROJECT_CONFIG.env` when run from a linked worktree (where the gitignored file
  doesn't exist). Previously an agent in a worktree silently behaved as if the Project were
  unconfigured and stopped updating the board.
- `templates/AGENTS.md` now splits the board schema into agent-maintained fields (scripted,
  setup-created) and optional human planning fields (`Priority`, `Size`, `Estimate`,
  `Iteration`, `Start date`, `Target date`) that no script writes — the old doc told agents to
  keep fields updated that the toolchain cannot even set.
- The resume procedure gained an explicit claim step: a resuming agent rewrites `Agent` on the
  card (nothing else ever does), so `check_resume_safety.sh` stops comparing against a stale
  name; the script now prints that reminder when it detects a takeover.
