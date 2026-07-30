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
| `pzoli6` | `Modelling_and_Simulations`, `DancePass`, `Space`, `Travel`, `AI_Settings`, `Invoice_Sync`, `agent_os` |
| `pszichocloud` | `Platform` |

A **fine-grained PAT is scoped to exactly one resource owner** — the dropdown offers only your own
account and organisations you belong to. Repos you're an *outside collaborator* on can't be
selected at all. So no single fine-grained PAT can cover both lists.

A **classic PAT reaches every repo its creating account can push to.** `pzoli6` has `write` on
`pszichocloud/Platform`, so one classic PAT from `pzoli6` covers all eight targets.

> Prefer least privilege? See "Alternative: two fine-grained PATs" at the bottom. It needs a
> change to the fan-out workflow, so it isn't the default.

### Do it

1. Sign in to GitHub as **`pzoli6`** (the account that owns `github-kit`).
2. Go to **https://github.com/settings/tokens/new** → *Generate new token (classic)*.
   - **Note:** `github-kit fan-out`
   - **Expiration:** your call. If you set one, put a reminder somewhere — fan-out starts failing
     silently-ish on expiry (it fails loudly in Actions, but only if you look).
   - **Scopes:** tick **`repo`** only. Nothing else. Not `workflow`, not `admin:*`.
3. **Generate token**, then copy it.
4. Store it as a secret on `github-kit`:

```bash
gh secret set GITHUB_KIT_FANOUT_TOKEN --repo pzoli6/github-kit
```

The command prompts for the value — paste it at the prompt.

> **Never paste a token into a chat with an AI agent, a commit, or an issue.** `gh secret set`
> reads it from the prompt and encrypts it client-side; nothing else ever sees it. The browser
> equivalent is **github-kit → Settings → Secrets and variables → Actions → New repository
> secret**, name `GITHUB_KIT_FANOUT_TOKEN`.

5. Confirm it landed:

```bash
gh api repos/pzoli6/github-kit/actions/secrets --jq '[.secrets[].name] | join(", ")'
```

---

## Step 2 — First run, on one repo only

Fan-out has probably never run successfully, so the first success will open draft PRs on **all
eight** targets at once, each carrying however much drift has accumulated. Do one first:

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

## Adding a new target repo

One line, then nothing on the target side:

```jsonc
// .github/fanout-targets.json
{ "repo": "owner/name", "base": "develop" }   // base = that repo's integration branch
```

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
| `scripts/project/*.sh` fail on Windows with `jq: command not found` | `jq` isn't bundled with Git Bash | `winget install jqlang.jq`, or use `gh api --jq` which uses gh's built-in jq and needs no install |

---

## Alternative: two fine-grained PATs (least privilege)

If you'd rather not use a classic PAT, the shape is:

- one fine-grained PAT per resource owner (`pzoli6`, `pszichocloud`), each granting **Contents: RW**
  and **Pull requests: RW** on just that owner's targets;
- stored as two secrets, e.g. `GITHUB_KIT_FANOUT_TOKEN` and `GITHUB_KIT_FANOUT_TOKEN_PSZICHOCLOUD`;
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
