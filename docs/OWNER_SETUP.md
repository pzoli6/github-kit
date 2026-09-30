# Owner setup — the steps no agent can do for you

Everything in this file requires **you**, signed in as the account that owns `github-kit`
(`pzoli6`). Agents can't do any of it: creating tokens, storing secrets, and changing account
settings are all outside what they're allowed or able to touch.

Work top to bottom. Each step says how to check whether it's already done, so re-reading this
later is cheap.

---

## Status check — run this first

```bash
# 1. Is the fan-out token set? (expects total_count >= 1)
gh api repos/pzoli6/github-kit/actions/secrets --jq '.total_count'

# 2. Has fan-out ever succeeded?
gh run list --repo pzoli6/github-kit --workflow github-kit-fanout.yml --limit 5 \
  --json createdAt,conclusion --jq '.[] | "\(.createdAt[0:16])  \(.conclusion)"'
```

If (1) prints `0`, nothing has ever propagated to any repo — start at Step 1.
If (2) is all `failure`, same conclusion.

> Listing secrets needs **admin** on `github-kit`. If you're signed in as a different account with
> only write access, `total_count` reads `0` whether or not the secret exists — check the Settings
> page in the browser instead.

---

## Step 1 — Create the fan-out token *(required; nothing propagates without it)*

### Why a **classic** PAT, not fine-grained

The README used to say fine-grained. That's wrong as soon as targets span more than one account,
which they now do:

| Owner | Targets |
| --- | --- |
| `pzoli6` | `ai-company`, `Modelling_and_Simulations`, `app-dance`, `app-career`, `ai-stack`, `app-scrape`, `app-travel`, `app-general-aviation`, `app-space`, `Invoice_Sync` |
| `pszichocloud` | `Platform`, `expenses`, `pszichocloud` |

(`pzoli6/github-kit` itself and `pzoli6/app-investment` are deliberately not targets — the
latter is maintained directly. The authoritative list is `.github/fanout-targets.json`.)

A **fine-grained PAT is scoped to exactly one resource owner** — the dropdown offers only your own
account and organisations you belong to. Repos you're an *outside collaborator* on can't be
selected at all. So no single fine-grained PAT can cover both lists.

A **classic PAT reaches every repo its creating account can push to.** As long as `pzoli6` has
`write` on every `pszichocloud/*` target, one classic PAT from `pzoli6` covers all thirteen.

> Prefer least privilege? See "Alternative: two fine-grained PATs" at the bottom. It needs a
> change to the fan-out workflow, so it isn't the default.

### Do it

1. Sign in to GitHub as **`pzoli6`** (the account that owns `github-kit`).
2. Go to **https://github.com/settings/tokens/new** → *Generate new token (classic)*.
   - **Note:** `github-kit fan-out`
   - **Expiration:** your call. If you set one, put a reminder somewhere — fan-out starts failing
     silently-ish on expiry (it fails loudly in Actions, but only if you look).
   - **Scopes:** tick **`repo`** *and* **`workflow`**. Nothing else — not `admin:*`.

     > `workflow` is not optional. Fan-out refreshes `.github/workflows/*.yml` in the target
     > repos, and git refuses a PAT push that touches a workflow file without it:
     > *"refusing to allow a Personal Access Token to create or update workflow … without
     > `workflow` scope"*. Everything before the push succeeds — token check, both
     > checkouts, the refresh, the commit — so the run fails late and looks like a permissions
     > problem on the target repo rather than a missing scope on the token.
     >
     > Already created the token without it? You do **not** need a new one: open the token,
     > tick `workflow`, press *Update token*. The value is unchanged, so the stored secret
     > stays valid.
3. **Generate token**, then copy it.
4. Store it as a secret on `github-kit`:

Name it exactly **`FANOUT_TOKEN`**.

> **The name must not start with `GITHUB_`.** GitHub reserves that prefix and rejects such secret
> names outright. The kit previously documented `GITHUB_KIT_FANOUT_TOKEN`, which therefore could
> never be created — that, not a missing step, is why fan-out failed on every run before
> 2026-07-30. Do not rename it back.

Use the browser if your local `gh` is signed in as an account that is not an **admin** of
`github-kit` (setting secrets needs admin, not just write):
**github-kit → Settings → Secrets and variables → Actions → New repository secret**.

Otherwise, from a terminal signed in as an admin:

```bash
gh secret set FANOUT_TOKEN --repo pzoli6/github-kit
```

The command prompts for the value — paste it at the prompt.

> **Never paste a token into a chat with an AI agent, a commit, or an issue.** `gh secret set`
> reads it from the prompt and encrypts it client-side; nothing else ever sees it. The browser
> equivalent is **github-kit → Settings → Secrets and variables → Actions → New repository
> secret**, name `FANOUT_TOKEN`.

5. Confirm it landed:

```bash
gh api repos/pzoli6/github-kit/actions/secrets --jq '[.secrets[].name] | join(", ")'
```

---

## Step 2 — First run, on one repo only

Fan-out has probably never run successfully, so the first success will open draft PRs on **every**
installed target at once, each carrying however much drift has accumulated. Do one first:

```bash
gh workflow run github-kit-fanout.yml --repo pzoli6/github-kit \
  -f only_repo=pszichocloud/Platform

# watch it
gh run watch --repo pzoli6/github-kit "$(gh run list --repo pzoli6/github-kit \
  --workflow github-kit-fanout.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
```

Review the draft PR it opens on that repo. When it looks right, run the rest:

```bash
gh workflow run github-kit-fanout.yml --repo pzoli6/github-kit
```

After this, you never trigger it manually again: it fires on every push to `main` touching
`templates/**` or the install/update scripts, plus a weekly cron.

---

## Step 3 — Per-repo Project token *(only if you use Project Sync)*

Separate from fan-out and **not** required for it. `project-sync.yml` needs a token with the
`project` scope, stored **in the target repo** (not in github-kit) as `AGENT_PROJECT_TOKEN`:

```bash
gh secret set AGENT_PROJECT_TOKEN --repo <owner>/<repo>
```

`Project Sync enabled` in that repo's `docs/ai/PROJECT_CONFIG.md` should say `true` once done.

---

## Step 4 — Auto-merge after green: the Actions budget, and an optional token

Every installed repo gets `.github/workflows/auto-merge.yml` (see `README.md` → "Auto-merge
after green"): a PR that a person marked ready for review merges by itself once every check on
it is green, and the `no-automerge` label holds one back. A PR with no checks at all, a PR opened
non-draft, and a PR from a long-lived branch (`develop` → `main`) are never merged
automatically. Three things only you can do:

### 4a. Restore / confirm the Actions spending limit *(required — nothing merges without it)*

Auto-merge is a GitHub Actions run like any other. While the account's Actions budget is
exhausted, **no run starts, so no PR merges** — a green PR simply sits there. Check the budget
for whichever account pays for the repo (personal `pzoli6`, and the `pszichocloud`
organisation): **Settings → Billing and licensing → Budgets and alerts**. GitHub's default
budget for metered products is $0, which hard-stops all Actions once the plan's included minutes
are used. Set a budget you are comfortable with (public repos consume no paid minutes), or raise
it when the kit's `KIT_ACTIONS_PAUSED` pause is lifted. Agents never change billing settings.

Check whether auto-merge runs are starting at all:

```bash
gh run list --repo <owner>/<repo> --workflow auto-merge.yml --limit 5 \
  --json createdAt,conclusion,event --jq '.[] | "\(.createdAt[0:16])  \(.event)  \(.conclusion)"'
```

No rows after a PR was marked ready means either the budget stopped it or the caller file is
not on the repo's default branch yet (its `workflow_run` / `check_suite` / `status` triggers only
fire from the default branch — merge the fan-out PR first). Rows with conclusion `skipped` cost
nothing: they are events filtered out before a runner started (a pending status, a failed run, a
draft PR, an unrelated label), or `KIT_ACTIONS_PAUSED` / `KIT_AUTOMERGE_DISABLED` is `true`.

### 4b. Optional: `AUTOMERGE_TOKEN` per repo *(base-branch workflows after a merge, or merging workflow-file PRs)*

Merges made with the default `GITHUB_TOKEN` do **not** trigger other Actions workflows on the
base branch (a `CI (Node)` push run on `main`, for example). Vercel and other webhook/GitHub-app
integrations are unaffected. GitHub also refuses changes to `.github/workflows/*` from a token
without the workflow permission, which `GITHUB_TOKEN` can never have, so a PR that touches
workflow files — **every github-kit fan-out/update PR does** — is expected to be refused and
left for you to merge by hand (the auto-merge run logs a warning saying so; this follows from
GitHub's documented rules and has not been observed live yet). If a repo needs either, store a
PAT in **that target repo** (not in github-kit) as the secret **`AUTOMERGE_TOKEN`**:

- **Fine-grained PAT (recommended), this one repository only:** *Contents: Read and write*,
  *Pull requests: Read and write*, *Issues: Read*, *Checks: Read*, *Commit statuses: Read*,
  *Actions: Read*, and — only if it should merge PRs that change workflow files — *Workflows:
  Read and write*. Every read permission is required: the workflow fails closed, so a token
  that cannot read checks, statuses, workflow runs or the PR timeline merges **nothing** (each
  run logs which read failed).
- **Classic PAT (fallback):** scopes `repo` (+ `workflow` for workflow-file PRs). Note that a
  classic token reaches **every** repository its account can push to, while being stored in
  just this one — prefer the fine-grained token.
- The account creating it must have push access to the repo; the merge commits and the summary
  comment will be attributed to that account.

```bash
gh secret set AUTOMERGE_TOKEN --repo <owner>/<repo>
```

The caller already passes the secret through (`secrets.AUTOMERGE_TOKEN`); an absent secret means
"use `GITHUB_TOKEN`". Nothing to edit in the repo, which matters because `auto-merge.yml` is
refreshed by every kit update.

### 4c. Per-repo switches *(repository Actions variables)*

Settings → Secrets and variables → Actions → **Variables**, per target repo:

| Variable | Effect |
| --- | --- |
| `KIT_AUTOMERGE_DISABLED` = `true` | Auto-merge off in this repo. This is the durable opt-out — deleting `auto-merge.yml` lasts only until the next kit update or fan-out recreates it. |
| `KIT_AUTOMERGE_ALLOW_NO_CHECKS` = `true` | Declared per repo in github-kit's `.github/fanout-targets.json` (`"variables"`) and applied with `scripts/apply-repo-variables.sh` (`--dry-run` first). A ready PR whose head commit has no check runs, statuses or workflow runs merges anyway. Off by default because "no checks" cannot be told apart from "CI did not run". With the kit's budget-first triggers a PR into the base branch has no kit checks, so without this (or a third-party check such as Vercel) such PRs are merged by hand. |
| `KIT_ACTIONS_PAUSED` = `true` | Pauses every github-kit job, auto-merge included. Checks the pause left `skipped` are never counted as green: after unpausing, re-run those workflows (or push) and their completion re-evaluates the PR. |

```bash
gh variable set KIT_AUTOMERGE_DISABLED --body true --repo <owner>/<repo>
```

---

## Adding a new target repo

One line, then nothing on the target side:

```jsonc
// .github/fanout-targets.json
{ "repo": "owner/name" }                        // base = the repo's default branch, resolved at run time
{ "repo": "owner/name", "base": "develop" }     // base = that repo's integration branch, if not the default
{ "repo": "owner/name", "install": true }       // first install: the kit is not there yet
```

A target that does **not** have the kit installed (no `docs/ai/PROJECT_CONFIG.md` at its base
branch) is **skipped with a log line and no PR** unless its entry says `"install": true` — the
kit is never silently installed into a repo that never had it. With `"install": true` the full
installer runs once and opens a draft PR that says so (fill in `docs/ai/PROJECT_CONFIG.md`
before merging); after that the flag is harmless and can stay or go.

Then confirm the fan-out token can actually reach it — if it's under a **different account**, a
fine-grained PAT will not, and a classic PAT only will if its creating account has push access
there.

---

## Adding a new file to `templates/`

Not a token step, but the same class of trap, and it is **silent**. A new file under `templates/`
propagates to **zero** repos until it is registered in *both* places:

1. **The four installer lists** — `scripts/{update,install}-github-kit.{sh,ps1}`. They copy an
   explicit list, never a glob. Miss this and `/github_kit_update` reports success and installs
   nothing.
2. **The fan-out staging allowlist** — the `for p in AGENTS.md CLAUDE.md … ;do git add` loop in
   `.github/workflows/github-kit-fanout.yml`. Miss this and the file is dropped from the PR *even
   though the updater wrote it* — so the change ships half-applied (e.g. a workflow without the
   script it calls) and only breaks at first use.

Neither file hints at the other. Check both.

---

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Fan-out fails at the first step, `FANOUT_TOKEN:` empty in the log | Secret not set | Step 1 |
| Fan-out fails only for *some* targets | Token can't reach those repos — usually a fine-grained PAT hitting a different account | Step 1, use a classic PAT |
| Writing `.github/workflows/*` via the API returns **404** | Token lacks the `workflow` scope. It returns 404, **not 403**, and reads still succeed — so it looks like a wrong path | `gh auth refresh -s workflow` |
| `gh project`/field commands fail with "missing required scopes" | Token lacks `project` | `gh auth refresh -s read:project,project` |
| A new `templates/` file never appears in target repos | One of the two registration points above | See "Adding a new file to `templates/`" |
| Fan-out PR is missing a script the workflow calls | Fan-out staging allowlist | Same |
| Fan-out logs `Skipped <repo>: github-kit is not installed there` and opens no PR | The target has no `docs/ai/PROJECT_CONFIG.md` and its entry lacks `"install": true` | Add `"install": true` to that entry (see "Adding a new target repo"), or leave it skipped on purpose |
| A green, ready PR never merges | Read the auto-merge comment on the PR: it names the reason and the next step. No comment means the PR was never handed over (draft; opened non-draft; `no-automerge`; a long-lived head branch; a fork) or no run could start (`KIT_AUTOMERGE_DISABLED`, `KIT_ACTIONS_PAUSED`, Actions budget exhausted, caller not on the default branch yet) | README → "Why hasn't my PR merged?"; Steps 4a and 4c; apply `KIT_AUTOMERGE_ALLOW_NO_CHECKS` with `scripts/apply-repo-variables.sh` |
| Auto-merge logs "GitHub refused the merge because the PR changes .github/workflows/*" | The merge token lacks the workflow permission (always true of `GITHUB_TOKEN`) | Merge that PR by hand, or Step 4b with *Workflows: Read and write* |
| Auto-merge run fails with "could not read ... - not merged" | The token cannot read checks / statuses / workflow runs / the PR timeline, or the API was down | Step 4b permissions; re-trigger by adding and removing `no-automerge` |
| Base-branch workflows don't run after an automatic merge | Merge made with `GITHUB_TOKEN`, which never triggers other workflows | Step 4b (`AUTOMERGE_TOKEN`) |
| `scripts/project/*.sh` fail on Windows with `jq: command not found` | `jq` isn't bundled with Git Bash | `winget install jqlang.jq`, or use `gh api --jq` which uses gh's built-in jq and needs no install |

---

## Alternative: two fine-grained PATs (least privilege)

If you'd rather not use a classic PAT, the shape is:

- one fine-grained PAT per resource owner (`pzoli6`, `pszichocloud`), each granting **Contents: RW**
  and **Pull requests: RW** on just that owner's targets;
- stored as two secrets, e.g. `FANOUT_TOKEN` and `FANOUT_TOKEN_PSZICHOCLOUD`;
- a change in `github-kit-fanout.yml` to select the token by the target's owner prefix.

That last part is a code change, so it isn't the default — ask an agent to open a PR for it if you
want this instead.

---

## Making `github-kit` public

**Why you'd do this:** a private repo can only share its reusable workflows with repos owned by the
**same** account. There is no cross-account option. So the moment a target repo lives under a
different account, its `uses: pzoli6/github-kit/...@main` callers fail with `jobs=0` and
"workflow file issue" — they never run at all. Making the kit public is the only fix that keeps one
SSOT.

### Pre-flight audit — already done, 2026-07-30

Going public exposes **all history and all branches**, not just current files. Scanned: 60 unique
commits across every branch, ~32k lines of patch.

| Check | Result |
| --- | --- |
| Credentials in current files (tokens, keys, JWTs, cloud keys) | **0 hits** |
| Credentials anywhere in history | **0 hits** |
| Credential-shaped filenames ever committed | only `PROJECT_CONFIG.env.example` — placeholders |
| Real email addresses | none (only `github-kit-bot@users.noreply.github.com`) |
| Fork-triggerable workflows that could reach a secret | **none** — all six `reusable-*.yml` are `workflow_call` only, and fan-out triggers on push/schedule/dispatch, none of which a stranger's PR can fire |

**Nothing needs purging, and no history rewrite is required.**

### The one judgement call: target repo names

`.github/fanout-targets.json` lists your private repos by name. Going public makes those names
visible. They are not credentials — but they do reveal which projects exist.

Two honest options:

1. **Accept it.** Simplest, and repo names are low-sensitivity. Nothing to change.
2. **Split the orchestration out.** Keep `github-kit` public for what *must* be public — templates
   and `reusable-*.yml` — and move fan-out (workflow + target list + PAT) into a small **private**
   repo that checks out `github-kit@main` and runs `update-github-kit.sh` against your targets.
   You still only ever edit `github-kit`; the private repo is set-and-forget.

Avoid the middle path of hiding the list in a secret inside the public repo: the names still leak
through matrix job titles and `workflow_dispatch` inputs unless you switch to index-based matrices
and masking, which makes the one mechanism you depend on materially harder to operate and debug.

### After flipping to public

1. **No Access setting to change** — public reusable workflows are callable from anywhere. The
   "Enabling private reusable workflow access" step in `README.md` stops applying.
2. **Re-run the previously-broken callers** in each target repo. `pr-policy` and
   `agent-workflow-verify` have been failing with `jobs=0` for as long as the target lived under a
   different account; they should go green on the next PR with no change to the target repo.
3. **Actions minutes become free** for the public repo.
4. **Anyone can now call your reusable workflows.** That is harmless — they run in the caller's
   repo, with the caller's tokens, on the caller's dime.
5. **Delete merged `claude/*` branches** so the public history is tidy:
   ```bash
   gh api repos/pzoli6/github-kit/branches --jq '.[].name' \
     | grep '^claude/' \
     | xargs -I{} gh api -X DELETE repos/pzoli6/github-kit/git/refs/heads/{}
   ```
   Check each is merged first — `gh pr list --state merged --json headRefName`.
