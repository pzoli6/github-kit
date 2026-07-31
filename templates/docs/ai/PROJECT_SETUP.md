# PROJECT_SETUP.md — the GitHub Project board, from zero to automatic

How this repo's GitHub Project (v2) board gets created, what must be on it, and how it stays in
sync while agents work. Written for coding agents first (a human can follow it too): after the
one-time setup below, **no one configures anything again** — re-running any step is a green no-op.

The one thing automation cannot do is mint a credential. Everything else — creating the Project,
adding every field, adding every Status option, linking it to the repo, pinning the number into
config, and all day-to-day updates — is scripted, and this file says which script owns what.

---

## What the board must hold (the contract)

`scripts/project/setup_github_project.sh` is the executable form of this contract — the tables
below document it; the script enforces it. If they ever disagree, the script wins, and this file
has a bug to fix.

**Custom fields** (all TEXT — free text keeps them writable by every agent without option
maintenance; `Status` is the one single-select, and it's built into every Project):

| Field | Written at | By |
| --- | --- | --- |
| `Agent` | issue creation / PR open | `create_agent_issue.sh` / `create_agent_pr.sh` (`--agent`) |
| `Area` | issue creation / PR open | same (`--area`) |
| `Risk` | issue creation / PR open | same (`--risk`) |
| `Environment` | issue creation / PR open | same (`--environment`) |
| `Base Branch` | PR open | `create_agent_pr.sh` |
| `Branch` | branch published | `sync_project_fields.sh branch_published` |
| `PR URL` | PR opened | `sync_project_fields.sh pr_opened` |
| `Validation` | every validation run | `sync_project_fields.sh validation_*` |
| `Handoff` | handoff file updated | `sync_project_fields.sh handoff_updated` |
| `Last Agent Update` | every checkpoint that changes state | `sync_project_fields.sh` (timestamp-prefixed) |
| `Agent Run` | when a hosted-agent session URL exists | the agent, via `project_set_text.sh` |

**Status options** (the kit's lifecycle vocabulary — `sync_project_fields.sh` sets these exact
case-sensitive spellings):

| Status | Meaning | Set by checkpoint |
| --- | --- | --- |
| `Backlog` | Filed, not claimed | Project Sync workflow (issue opened) |
| `Ready` | Issue created for an approved task | `issue_created` |
| `Plan Review` | Plan posted, awaiting `approve` | `plan_ready` |
| `In Progress` | Branch published, implementation running | `branch_published` |
| `Blocked` | Stopped on a stop-and-ask gate | `blocked` |
| `In Review` | Draft PR open | `pr_opened` / Project Sync (PR opened) |
| `Changes Requested` | Human asked for changes | `changes_requested` |
| `Done` | PR merged | `done` / Project Sync (closed) |
| `Cancelled` | Task abandoned | `cancelled` |

A default GitHub board ships `Todo` / `In progress` / `Done` — note the lowercase `p`. The setup
script **adds** the kit spellings alongside and never renames or deletes existing options (that
could drop values from existing cards). Consolidate on the board later if the near-duplicates
bother you.

---

## One-time setup

### The single human step

Create a PAT with the **`project` scope** and save it as the repository secret
**`AGENT_PROJECT_TOKEN`** (Settings → Secrets and variables → Actions → New repository secret).
The default `GITHUB_TOKEN` cannot read or write Projects (v2) — this is a GitHub limitation, not
a kit choice, and it is why this one step exists at all. A classic PAT with `project` (plus
`repo` for private repos) works for both user- and org-owned boards; the same token also serves
Project Sync and the field-completeness gate — one token, all three consumers.

### Path A — fully automatic (the default)

Nothing to invoke. `.github/workflows/project-setup.yml` fires when a github-kit update touching
it or the setup script lands on a main/master/develop branch — which is exactly what merging the
kit's fan-out PR does — and on manual dispatch (Actions → **Project Setup** → Run workflow, for
when you add the secret *after* the merge).

What one run does, in order:

1. **Skips green with a notice** if `AGENT_PROJECT_TOKEN` doesn't exist yet — no red check, and
   the notice says exactly what to do.
2. **Ensures the board**: runs `setup_github_project.sh --apply`, which creates the Project (or
   adopts one by configured number, or by title match from a previous run), creates every missing
   field, appends every missing Status option, and links the Project to the repo. All
   ensure-only; a healthy board means zero changes.
3. **Opens the config PR** (draft) if the caller still says `project_number: "TBD"`: it pins the
   real owner/number/title into `.github/workflows/project-setup.yml`,
   `.github/workflows/project-sync.yml` (if installed), and `docs/ai/PROJECT_CONFIG.md` —
   flipping `Project Sync enabled` to `true`. Automation never pushes to the base branch;
   **merging that PR is the human's last setup action.**

After that PR merges, solo mode (`auto`) turns itself off — a real Project number is configured —
and the full board lifecycle applies. Re-runs of the workflow find nothing to do.

### Path B — agent-driven, local

For an agent asked to "set up the project board" in a repo where the human runs with a
`project`-scoped `gh` login (or `GH_TOKEN`). This is normal implementation work: plan → `approve`
→ run. Then:

```bash
scripts/project/setup_github_project.sh                    # doctor: report gaps, change nothing
scripts/project/setup_github_project.sh --apply --write-config   # create/fix + write PROJECT_CONFIG.env
```

Then update `docs/ai/PROJECT_CONFIG.md`'s table (owner, number, name, `Project Sync enabled:
true`) and the `project_owner`/`project_number` inputs in `.github/workflows/project-sync.yml`
and `project-setup.yml`, and put it all in the task's draft PR. The script printed every value
you need. Optionally run `scripts/project/create_standard_labels.sh` for the label set.

### Path C — by hand

Create a Project, add every field from the contract table as **Text**, add every Status option
with the exact spellings above, link the Project to the repo, fill `PROJECT_CONFIG.md` and the
two workflow callers. The script exists because nobody gets this list right by hand twice —
run `setup_github_project.sh` (no flags) afterwards to verify you did.

---

## How it stays updated while you work

Two independent mechanisms keep the board truthful; they deliberately overlap:

- **Agents at checkpoints** (the fine-grained record): `create_agent_issue.sh` /
  `create_agent_pr.sh` write the metadata fields at creation time so nothing starts blank, and
  `sync_project_fields.sh <checkpoint>` moves Status and the text fields at every lifecycle
  moment listed in the contract table — that's what makes a card answer "who's on this, which
  branch, does validation pass, when did anything last happen" without opening the PR.
- **The Project Sync workflow** (the safety net): on issue/PR open, ready-for-review, and close,
  `.github/workflows/project-sync.yml` sets Status server-side — so even a session that died
  mid-task, or a PR opened outside the kit's scripts, still lands on the board and still flips to
  `Done` when merged.

The opt-in **field-completeness gate** (`check_project_fields` in
`.github/workflows/pr-policy.yml`, documented in `PROJECT_CONFIG.md`) closes the loop: once the
board is set up, it fails any PR whose card still has blank required fields — turning "agents are
supposed to fill the card" into something CI enforces.

**Solo mode note** (`PROJECT_CONFIG.md` → "Solo mode"): while `auto` solo mode is active — i.e.
before this setup has run — agents skip all Project-field steps by design. Setting up the board
is precisely what ends that: with a configured Project number and Project Sync enabled, the
full-mode bookkeeping above applies from the next task on.

## Verifying, any time

```bash
scripts/project/setup_github_project.sh    # exit 0 + "fully set up" = the contract holds
```

Run it in doctor mode whenever the board feels off (a field deleted by hand, a status renamed) —
it lists exactly what's missing, and `--apply` restores it without touching anything that exists.
