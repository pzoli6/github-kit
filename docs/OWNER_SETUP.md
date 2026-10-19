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

# 1b. Is the fan-out registry stored? (prints an error if not)
bash scripts/fanout-registry.sh get > /dev/null && echo "registry present"

# 2. Has fan-out ever succeeded?
gh run list --repo pzoli6/github-kit --workflow github-kit-fanout.yml --limit 5 \
  --json createdAt,conclusion --jq '.[] | "\(.createdAt[0:16])  \(.conclusion)"'
```

If (1) prints `0`, nothing has ever propagated to any repo — start at Step 1.
If (1b) prints an error, the fan-out fails fast at its first job — Step 1b.
If (2) is all `failure`, same conclusion.

> Listing secrets needs **admin** on `github-kit`. If you're signed in as a different account with
> only write access, `total_count` reads `0` whether or not the secret exists — check the Settings
> page in the browser instead.

---

## Step 1 — Create the fan-out token *(required; nothing propagates without it)*

### Why a **classic** PAT, not fine-grained

The README used to say fine-grained. That's wrong as soon as targets span more than one account
(a personal account plus an organisation, say), which they do.

The authoritative list is the fan-out registry — the `FANOUT_TARGETS` repository variable (Step
1b), **not** a file in this public repository. `github-kit` itself is never a target.

A **fine-grained PAT is scoped to exactly one resource owner** — the dropdown offers only your own
account and organisations you belong to. Repos you're an *outside collaborator* on can't be
selected at all. So no single fine-grained PAT can cover both lists.

A **classic PAT reaches every repo its creating account can push to.** As long as the owner
account has `write` on every target in the other accounts, one classic PAT from it covers them all.

> Prefer least privilege? See "Alternative: two fine-grained PATs" at the bottom. It needs a
> change to the fan-out workflow, so it isn't the default.

### Do it

1. Sign in to GitHub as **`pzoli6`** (the account that owns `github-kit`).
2. Go to **https://github.com/settings/tokens/new** → *Generate new token (classic)*.
   - **Note:** `github-kit fan-out`
   - **Expiration:** your call. If you set one, put a reminder somewhere — fan-out starts failing
     silently-ish on expiry (it fails loudly in Actions, but only if you look).
   - **Scopes:** tick **`repo`** *and* **`workflow`**. Nothing else — not `admin:*`. (`repo` also
     lets the fan-out read the `FANOUT_TARGETS` registry variable, Step 1b.)

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

## Step 1b — Store the fan-out registry *(required; the workflow fails fast without it)*

The list of repositories the fan-out maintains is **not committed** to this public repository: it
lives in the repository Actions **variable** `FANOUT_TARGETS` on `github-kit`, as the JSON described
in `.github/fanout-targets.example.json` (one `{ "repo": "owner/name", ... }` entry per target; the
example's `_comment` documents every key). Anyone with collaborator access to `github-kit` can
read it — the public cannot, so mind who you add as a collaborator — and the workflow masks every
target name in its logs and names jobs with per-run opaque labels (Step 1c), so a public run page
shows no repo and no stable position.

Check: `bash scripts/fanout-registry.sh get` prints it (needs `gh` signed in to an account with
write access to `github-kit`; a variable that does not exist prints an error).

Create or update it from a local file, which stays local (`.github/fanout-targets.json` is
gitignored for exactly this purpose):

```bash
cp .github/fanout-targets.example.json .github/fanout-targets.json   # first time: then edit it
bash scripts/fanout-registry.sh check .github/fanout-targets.json    # schema check, changes nothing
bash scripts/fanout-registry.sh set   .github/fanout-targets.json    # stores it as FANOUT_TARGETS
```

`set` refuses an invalid file (unknown keys, a `repo` that is not `owner/name`, a `tier` other than
1 or 2, duplicate repos, non-string `variables`), so a typo can never break the fan-out. Keep the
local file, or re-create it anywhere with `get`. Never commit it, paste it into an issue or a chat,
or put repository names into the workflow, the docs or the example — the doctor fails if the
registry is ever tracked.

Storing the registry triggers nothing by itself — it is a variable, not a push — so after a `set`
that adds or changes a target, dispatch the fan-out (`set` prints the command; Step 2 shows it) or
wait for Monday's cron.

> Migrating from the committed file? Its last version is still in history:
> `git show <last-main-commit-before-the-move>:.github/fanout-targets.json > .github/fanout-targets.json`,
> then `check` and `set` as above, **before** merging the move, so the next fan-out run finds the
> variable. The order of the entries does not matter: job names carry per-run labels (Step 1c),
> never a registry position.

---

## Step 1c — Label key for the fan-out jobs *(recommended; the token is the fallback)*

Every fan-out job is named with a **per-run opaque label**: HMAC-SHA256 of `<run id>:<registry
index>`, cut to 12 hex chars, so a public run page shows `fanout (3f9c2a1b7e0d)` and nothing that
maps back to a repository — not even a stable position, since every run relabels and the jobs are
listed in label order. Mapping a label back needs the key the run used. Store one:

```bash
openssl rand -hex 32                                      # generate once; keep it in your password manager
gh secret set FANOUT_LABEL_KEY --repo pzoli6/github-kit   # paste it at the prompt
```

Without this secret the workflow keys the labels with `FANOUT_TOKEN` itself, which works but means
keeping the PAT at hand just to read a run page. With the key in your environment:

```bash
export FANOUT_LABEL_KEY=<the value you stored>
bash scripts/fanout-registry.sh labels <run id>           # label -> repo for every entry of that run
bash scripts/fanout-registry.sh which  <run id> <label>   # the entry behind one (failed) job
```

The run id is the number in the run's URL. Do not rotate the key while a run is in flight: a job
would then resolve no entry, fail with that message and touch nothing — re-run after the rotation.

---

## Step 2 — First run, on one repo only

Fan-out has probably never run successfully, so the first success will open draft PRs on **every**
installed target at once, each carrying however much drift has accumulated. Do one first:

```bash
# one target: pass its 0-based index in the registry (`bash scripts/fanout-registry.sh get`).
# An owner/name works too, but an index keeps the repo name out of this public run's inputs.
gh workflow run github-kit-fanout.yml --repo pzoli6/github-kit \
  -f only_repo=0

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
for whichever account pays for the repo (your personal account, and every organisation that owns
a target): **Settings → Billing and licensing → Budgets and alerts**. GitHub's default
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
| `KIT_AUTOMERGE_ALLOW_NO_CHECKS` = `true` | Declared per repo in github-kit's fan-out registry (`"variables"` on the entry, Step 1b) and applied with `scripts/apply-repo-variables.sh` (`--dry-run` first). A ready PR whose head commit has no check runs, statuses or workflow runs merges anyway. Off by default because "no checks" cannot be told apart from "CI did not run". With the kit's budget-first triggers a PR into the base branch has no kit checks, so without this (or a third-party check such as Vercel) such PRs are merged by hand. |
| `KIT_ACTIONS_PAUSED` = `true` | Pauses every github-kit job, auto-merge included. Checks the pause left `skipped` are never counted as green: after unpausing, re-run those workflows (or push) and their completion re-evaluates the PR. |

```bash
gh variable set KIT_AUTOMERGE_DISABLED --body true --repo <owner>/<repo>
```

---

## Adding a new target repo

One registry entry, then nothing on the target side. The registry is the `FANOUT_TARGETS` variable
(Step 1b), so edit a local, gitignored copy and store it back:

```bash
bash scripts/fanout-registry.sh get > .github/fanout-targets.json   # local copy, never committed
# add one entry to "targets" (shapes below), then:
bash scripts/fanout-registry.sh set .github/fanout-targets.json
# a stored variable triggers nothing: run the fan-out for the new entry now (N = its 0-based index)
gh workflow run github-kit-fanout.yml --repo pzoli6/github-kit -f only_repo=N
```

```jsonc
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
| Fan-out fails in `discover` naming `FANOUT_TARGETS` | The registry variable is missing, is not valid registry JSON, or the token cannot read it | Step 1b (`scripts/fanout-registry.sh check` / `set`) |
| A fan-out job is red but reads only `fanout (3f9c2a1b7e0d)` and `***` | By design: target names are masked and jobs carry per-run labels on this public repo | `FANOUT_LABEL_KEY=… bash scripts/fanout-registry.sh which <run id> 3f9c2a1b7e0d` names the repo (Step 1c) |
| A fan-out job fails with "resolves to no entry of this run's registry" | `FANOUT_LABEL_KEY` was changed while the run was in flight | Re-run the workflow |
| Fan-out fails only for *some* targets | Token can't reach those repos — usually a fine-grained PAT hitting a different account | Step 1, use a classic PAT |
| Writing `.github/workflows/*` via the API returns **404** | Token lacks the `workflow` scope. It returns 404, **not 403**, and reads still succeed — so it looks like a wrong path | `gh auth refresh -s workflow` |
| `gh project`/field commands fail with "missing required scopes" | Token lacks `project` | `gh auth refresh -s read:project,project` |
| A new `templates/` file never appears in target repos | One of the two registration points above | See "Adding a new file to `templates/`" |
| Fan-out PR is missing a script the workflow calls | Fan-out staging allowlist | Same |
| Fan-out logs `Skipped target N: github-kit is not installed there` and opens no PR | The target has no `docs/ai/PROJECT_CONFIG.md` and its registry entry lacks `"install": true` | Add `"install": true` to that entry (see "Adding a new target repo"), or leave it skipped on purpose |
| A green, ready PR never merges | Read the auto-merge comment on the PR: it names the reason and the next step. No comment means the PR was never handed over (draft; opened non-draft; `no-automerge`; a long-lived head branch; a fork) or no run could start (`KIT_AUTOMERGE_DISABLED`, `KIT_ACTIONS_PAUSED`, Actions budget exhausted, caller not on the default branch yet) | README → "Why hasn't my PR merged?"; Steps 4a and 4c; apply `KIT_AUTOMERGE_ALLOW_NO_CHECKS` with `scripts/apply-repo-variables.sh` |
| Auto-merge logs "GitHub refused the merge because the PR changes .github/workflows/*" | The merge token lacks the workflow permission (always true of `GITHUB_TOKEN`) | Merge that PR by hand, or Step 4b with *Workflows: Read and write* |
| Auto-merge run fails with "could not read ... - not merged" | The token cannot read checks / statuses / workflow runs / the PR timeline, or the API was down | Step 4b permissions; re-trigger by adding and removing `no-automerge` |
| Base-branch workflows don't run after an automatic merge | Merge made with `GITHUB_TOKEN`, which never triggers other workflows | Step 4b (`AUTOMERGE_TOKEN`) |
| `scripts/project/*.sh` fail on Windows with `jq: command not found` | `jq` isn't bundled with Git Bash | `winget install jqlang.jq`, or use `gh api --jq` which uses gh's built-in jq and needs no install |

---

## Alternative: two fine-grained PATs (least privilege)

If you'd rather not use a classic PAT, the shape is:

- one fine-grained PAT per resource owner (your account, each organisation), each granting
  **Contents: RW** and **Pull requests: RW** on just that owner's targets (the one for the account
  that owns `github-kit` also needs **Variables: Read** there, to read the registry);
- stored as one secret per owner, e.g. `FANOUT_TOKEN` and `FANOUT_TOKEN_<ORG>`;
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

**Nothing needs purging, and no history rewrite is required.** Re-audited 2026-10-18 against every
tracked file and every file version in history: still 0 credential hits.

### Target repo names — moved out of the repo (2026-10-18)

The fan-out registry used to be a committed file, `.github/fanout-targets.json`, naming every
repository the kit maintains. It is now the `FANOUT_TARGETS` repository variable (Step 1b): only
accounts with collaborator access to `github-kit` can read it, the workflow reads it inside a step
(never through `env:`/`with:` before masking), masks every target name with `::add-mask::`, and names jobs with per-run opaque labels (Step 1c)
— the masking-plus-opaque-labels design the earlier audit called "harder to operate", made
bearable by `scripts/fanout-registry.sh which <run id> <label>` as the one lookup it costs. The
repo carries only `.github/fanout-targets.example.json` with placeholder names, and the doctor
fails if a registry file is ever tracked.

What this does **not** undo — owner decisions, never an agent's:

- **History.** Every commit of the old file (2026-07-13 → 2026-10-18) still holds the names.
  Removing them needs a history rewrite plus a force-push of `main`, which invalidates every
  clone and open PR. Repo names are low-sensitivity, so the recommended default is to leave
  history alone.
- **Old workflow runs.** Fan-out run logs and job names from before this change show the names
  until they expire (90 days by default), or sooner if you delete those runs (Actions → run →
  ⋯ → *Delete workflow run*).
- **Job labels.** Job names carry per-run opaque labels (Step 1c), so neither a name nor a
  registry position reaches a run page; the number of jobs still shows how many targets exist.
  Mapping a label back needs the label key (or the token) — the one operational cost of this
  design.
- **The other option still stands.** If even a masked, variable-held registry in a public repo
  is too much, move the fan-out (workflow + registry + PAT) into a small **private** repo that
  checks out `github-kit@main` and runs `update-github-kit.sh` against your targets.

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
