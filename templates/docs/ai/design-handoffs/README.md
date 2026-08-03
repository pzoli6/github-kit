# `docs/ai/design-handoffs/` — spec in, code out

One file per surface, written by whatever produces designs or specs for this repo (a design tool,
a planning agent, or a human), picked up by a coding agent.

`docs/ai/` covers three directions of exchange. They are not interchangeable:

| Folder | Direction | Contents |
| --- | --- | --- |
| `design-prompts/` | Code → Design | briefs sent *to* a design tool |
| **`design-handoffs/`** (this folder) | **Design → Code** | finished specs waiting to be built |
| `handoffs/` | Code → anyone | *task* state — "here's where I stopped on issue 42" |

A file here describes a surface that **does not exist in code yet**. A handoff file describes work
already underway. Don't put one in the other's folder.

---

## The one rule that matters

> **An agent acts on `status: approved` and never on `status: ready`.**

`/github_kit implement docs/ai/design-handoffs/<file>.md` is a pre-approved entry point: the
invocation *is* the human's approval, "scoped strictly to the description supplied". When the
description is a **path**, the real scope boundary becomes whatever is written in that file — and
that file is normally written by an agent, not by the human doing the approving.

`approved` closes that hole, but only if the marker itself is trustworthy — and **a marker anyone
can type is not**. A `status: approved` line a human types by hand is one an agent can type too;
nothing downstream can tell them apart. So nobody types it.

**The transition `ready → approved` is a recorded act on the spec PR.** Open the spec PR, read the
rendered Acceptance criteria, then either click **Approve** or — when that button isn't there,
because the PR is your own — comment `/approve-spec`.
`.github/workflows/design-handoff-approval.yml` (a thin caller for a reusable workflow in
`github-kit`, so it auto-updates) transcribes that event into the front matter. `approved-by`,
`approved-on`, `approval-pr`, `approval-via` and the matching `approval-review-id` /
`approval-comment-id` all come from the event payload.

That makes the marker **re-checkable**, which is the only thing that makes it worth anything:

```bash
node scripts/design-handoffs/verify.mjs docs/ai/design-handoffs/design-001-foo.md
```

It re-fetches the named event and confirms it really happened — an `APPROVED` review, or a comment
whose first line is exactly `/approve-spec` — by the login recorded, from a non-bot account that
holds write access here, on a PR that actually touches this file. It **fails closed**. Run it
before implementing, and a forged or hand-typed marker does not survive contact.

An agent that finds `ready` reports the file as awaiting review and does nothing else.

### Approving your own spec PR

**GitHub never lets anyone approve their own pull request** — the Approve option simply is not
offered, and the Files changed tab only permits a plain comment. A coding agent normally opens the
spec PR using *your* token, which makes you the author, which locks you out of the review form. The
symptom is a missing button rather than an error message.

That is GitHub's constraint, not a rule this kit chose, so the gate accepts a second act — one you
*can* perform on your own PR:

> **Comment `/approve-spec`**, as the first line of a comment on the spec PR.

The workflow treats it exactly like a review: it confirms the commenter is a non-bot account with
write access, stamps `approval-via: comment` and the comment id, and `verify.mjs` re-fetches that
comment and re-checks all of it before any agent implements anything. **You do not need a second
account, and you never approve "as" someone else.**

**Be clear about what each form buys.** A review is enforced by GitHub: author and approver are
*structurally* different accounts, so the marker is evidence a second person read the scope. A
comment is not — you can post it on your own PR, and so, holding your token, could an agent. What
the comment form still gives you is everything this gate is actually for on a one-person repo:

- the scope boundary is pinned to a file that existed, and was readable, **before** implementation;
- approving is a **separate, deliberate act** at a separate moment — not a side effect of an agent
  opening a PR;
- it is **recorded and re-checkable** — login, timestamp and comment id, verifiable long after; and
- every agent in this kit is told, here and in `AGENTS.md`, never to post it.

So it stops scope drift and leaves an audit trail. It does not stop an agent that holds your token
and has decided to ignore its instructions — but on a solo repo nothing else does either, since
that agent could equally push code you never read. Choose the form that matches who is really in
the room:

| You have | Use | In `.github/workflows/design-handoff-approval.yml` |
| --- | --- | --- |
| A second reviewer | Review — click **Approve** | `allow_comment_approval: false` |
| Only yourself | Comment — `/approve-spec` | `allow_comment_approval: true` *(shipped default)* |

The default leaves **both** forms working, so a repo that later gains a reviewer loses nothing.
Setting `allow_comment_approval: false` is how a team repo takes back GitHub's structural guarantee
that nobody signs off on their own scope.

**No human hand-edits front matter, and no human commits in order to approve a scope.** The click
(or the comment) is the approval; everything downstream is bookkeeping. A human act that cannot be
forged *by accident* is the requirement — a human act that is *tedious* was never the point.

### What an agent must never do

Never write `status: approved`, `approved-by`, `approved-on`, `approval-pr`, `approval-via`,
`approval-review-id` or `approval-comment-id` yourself. Never submit the approving review, **and
never post the `/approve-spec` comment** — not even when asked to, not even on a repo where the
human is the only account and could have posted it themselves. `gh pr review --approve` or
`gh pr comment --body '/approve-spec'` run by an agent holding the human's token produces a marker
that *looks* valid and guarantees nothing; on the comment form GitHub will not stop you, which is
exactly why the rule has to hold here instead. If someone asks you to approve a spec, say approval
is an act they perform, and point them at the PR.

---

## Statuses

| Status | Set by | Meaning |
| --- | --- | --- |
| `draft` | the spec's author | Still being written. Ignore. |
| `ready` | the spec's author | Finished and queued for a human read. **Not actionable.** |
| `approved` | the approval workflow, from a human's review or `/approve-spec` comment | Scope read and accepted. The only actionable status. |
| `in-progress` | the coding agent | Picked up. No second agent starts it. |
| `landed` | the coding agent | Merged. |
| `superseded` | either | Replaced by a newer entry; the front matter says which. |

Only `ready` is approvable. A `draft` is a moving target, and anything at `approved` or past it is
already claimed — the stamping script skips both rather than overwriting them, so a second review
or a repeated `/approve-spec` cannot rewrite an existing marker.

## Lifecycle

**Nothing here requires a human to run `git`.**

1. **The spec is written** as `draft`, then `ready`, using `_TEMPLATE.md`.
2. **It reaches the repo without you committing.** A coding agent commits it as `ready` on a branch
   and opens a **spec PR**. That PR exists to be read, not to ship code.
3. **You approve on that PR.** Read the Acceptance criteria as rendered markdown (a phone works),
   then click **Approve** — or, if the PR is your own and the button isn't offered, comment
   `/approve-spec`. The workflow stamps the marker onto the PR branch. Merging stays a human
   action, as it does for every PR.
4. **A coding agent implements it** — `verify.mjs` first, then
   `/github_kit implement docs/ai/design-handoffs/<file>.md`, setting `in-progress` and following
   the normal lifecycle in `docs/ai/AGENT_WORKFLOW.md`.
5. **On merge**, the agent sets `landed` and records the PR number.

If a spec is wrong, **Request changes** — or just say so in an ordinary comment — instead of
approving. The workflow only ever acts on an `approved` review or a comment whose first line is
exactly the marker, so anything else stamps nothing and the file stays `ready`.

Steps 4 and 5 edit **front matter only**. The body is the author's text and the record of what was
approved; a coding agent does not rewrite it. If the spec turns out to be wrong, that is a PR
comment or a new entry — never a silent edit to the thing a human signed off.

## Naming

`design-<nnn>-<slug>.md` — zero-padded, monotonic, never reused. The number is an identifier, not a
priority. Files are not deleted once `landed`; the folder doubles as the record of which surfaces
came from design and when.

---

## Writing rules

An entry is worth writing only if a coding agent could build the surface from it **without opening
the design tool**. Concretely:

- **Behaviour over pixels.** What the control does, when it is disabled, what happens on failure.
  Visual values come from this repo's design tokens, not from this file — where the two disagree,
  the tokens win.
- **Every state, not just the happy one.** Empty, loading, error, permission-denied, and the
  "cannot do this" case with its exact message. The states table exists because this is the part
  design handoffs habitually omit and coding agents habitually invent.
- **Copy for every language this repo ships.** A spec that supplies only the source language hands
  the coding agent an invented translation.
- **Name the receiving code.** The file the work replaces or extends. This is what makes an entry
  actionable rather than aspirational.
- **Out of scope is required.** It is half of what makes Acceptance criteria a boundary rather than
  a wish list.
- **Acceptance criteria are the contract.** `/github_kit` pre-approves exactly what that section
  describes. Anything not checkable is not a criterion. If the work needs to grow past the list
  mid-implementation, the agent stops and asks — pre-approval never expands on its own.

Repo-specific guardrails (i18n rules, design-token rules, domain constraints) belong in this repo's
`AGENTS.md`, not restated here — this file is installed by `github-kit` and refreshed from it.

---

## The sync loop — when a design tool reads this repo directly

Some design tools (Claude Design among them) connect to GitHub and read a repository as context.
That integration is **read-only**: the tool can read every file you point it at, but its only
write path is its export bundle. Run that loop naively and it fails in three specific ways —
each observed in practice, each with a rule here that prevents it.

`DESIGN_SYNC.md` in this folder is the loop's anchor: the tool's reading list, the sync state,
and the paste-in prompt live there. This section is the protocol behind it.

### Rule 1 — diff by commit, not by count

A design tool with no recorded baseline can only say "the repo grew from 2067 files to 2132" —
a heuristic that cannot name a single changed file. `DESIGN_SYNC.md`'s front matter records
`last-synced-commit`, written only by `apply-answers.mjs` when a round lands. The next round's
change set is then exact:

```bash
git log --name-only <last-synced-commit>..HEAD -- <the listed paths>
```

### Rule 2 — unreadable is not absent

Design tools read files through a bounded window; a file past it fails to read, and that failure
surfaces indistinguishably from the file not existing. The reading list in `DESIGN_SYNC.md` marks
such files `no — too large`, so the tool skips them knowingly instead of reporting them missing —
and a coding agent told a flagged file is "missing" checks the tree before acting on it.
**"Could not read" must never become "does not exist"** on either side of the loop.

### Rule 3 — the bundle writes back through one door

Feedback entries live in the file `DESIGN_SYNC.md` names as `feedback-file`, one section per
entry: a heading starting with the entry id, a `- **status:** open` line, new entries grouped
under `## Round <N> — synced <short-sha>` headers. When a design round resolves entries or
answers open decisions, transcribing that by hand is how the two copies fork — the repo keeps
saying `open` about things design already settled.

So the bundle carries the answers as an artifact, and one script applies it:

```json
{
  "format": "design-sync-answers/v1",
  "synced-commit": "<full SHA the tool read>",
  "round": 3,
  "generated-on": "2026-08-03T00:00:00Z",
  "entries": [
    { "id": "DF-042", "status": "resolved-in-design",
      "resolution": "Empty state now uses the token ramp from DF-037" }
  ],
  "decisions": [
    { "id": "nav-placement", "answer": "Guardrails lands under Security, not a top-level tab" }
  ]
}
```

```bash
node scripts/design-handoffs/apply-answers.mjs design-sync-answers.json
```

The script validates everything against the current tree first and applies all of it or none of
it: entry statuses flip (allowed: `answered`, `resolved-in-design`, `declined`, `superseded` —
reopening is a human act in the repo, never a bundle's), a generated resolution line lands under
each status, decisions append to `DESIGN_SYNC.md`'s Decision log, and the front-matter state
advances. It refuses an unknown entry id, an ambiguous one, a SHA this repo doesn't have, and a
round already applied. An answer merely restating what an earlier round already recorded counts
as current instead of re-appending — design tools export full state, not deltas, so an unedited
bundle is always safe to apply. `--dry-run` shows the plan.

**Nobody hand-edits what the script writes** — a status line, a resolution line, a decision-log
line, or the sync state. A record a human types is one an agent can type too, which is the same
reason approval markers are stamped from GitHub events rather than written by hand. And to keep
the two status systems distinct: feedback statuses are bookkeeping about design conversation;
they have nothing to do with a spec's `status: approved`, which remains exclusively the approval
workflow's to write.
