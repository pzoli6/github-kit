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

**The transition `ready → approved` is a GitHub review.** Open the spec PR, read the rendered
Acceptance criteria, click **Approve**. `.github/workflows/design-handoff-approval.yml` (a thin
caller for a reusable workflow in `github-kit`, so it auto-updates) transcribes that event into the
front matter. `approved-by`, `approved-on`, `approval-pr` and `approval-review-id` all come from
the event payload.

That makes the marker **re-checkable**, which is the only thing that makes it worth anything:

```bash
node scripts/design-handoffs/verify.mjs docs/ai/design-handoffs/design-001-foo.md
```

It re-fetches the named review and confirms it is an `APPROVED` review, submitted by the login
recorded, by a non-bot account, on a PR that actually touches this file. It **fails closed**. Run
it before implementing, and a forged or hand-typed marker does not survive contact.

An agent that finds `ready` reports the file as awaiting review and does nothing else.

### The spec PR must not be opened by the person who approves it

**GitHub does not allow anyone to approve their own pull request** — the Approve option simply is
not offered, and the Files changed tab only permits a plain comment. A coding agent normally opens
the spec PR using *your* token, which makes you the author, which locks you out of approving it.
The gate then cannot fire at all, and the symptom is a missing button rather than an error message.

So the spec PR author and the approver have to be different accounts. However a repo arranges
that, write access is what the workflow checks, so the approver needs at least write:

- a second human reviewer, on a team; or
- on a solo setup, a second account of your own holding write access — have agents open spec PRs
  as one identity and approve as the other; or
- a bot/app identity that opens every spec PR, leaving all humans free to approve.

Decide this **before** the first real spec, not while hunting for a button that is not there.

**No human hand-edits front matter, and no human commits in order to approve a scope.** The click
is the approval; everything downstream is bookkeeping. A human act that cannot be forged is the
requirement — a human act that is *tedious* was never the point.

### What an agent must never do

Never write `status: approved`, `approved-by`, `approved-on`, `approval-pr` or
`approval-review-id` yourself, and never submit the approving review on a human's behalf — not
even when asked to. `gh pr review --approve` run by an agent holding the human's token produces a
marker that *looks* valid and guarantees nothing. If someone asks you to approve a spec, say that
approval is a click they make, and point them at the PR.

---

## Statuses

| Status | Set by | Meaning |
| --- | --- | --- |
| `draft` | the spec's author | Still being written. Ignore. |
| `ready` | the spec's author | Finished and queued for a human read. **Not actionable.** |
| `approved` | the approval workflow, from a human's review | Scope read and accepted. The only actionable status. |
| `in-progress` | the coding agent | Picked up. No second agent starts it. |
| `landed` | the coding agent | Merged. |
| `superseded` | either | Replaced by a newer entry; the front matter says which. |

Only `ready` is approvable. A `draft` is a moving target, and anything at `approved` or past it is
already claimed — the stamping script skips both rather than overwriting them, so a second review
cannot rewrite an existing marker.

## Lifecycle

**Nothing here requires a human to run `git`.**

1. **The spec is written** as `draft`, then `ready`, using `_TEMPLATE.md`.
2. **It reaches the repo without you committing.** A coding agent commits it as `ready` on a branch
   and opens a **spec PR**. That PR exists to be read, not to ship code.
3. **You approve by reviewing.** Read the Acceptance criteria as rendered markdown (a phone works),
   click **Approve**. The workflow stamps the marker onto the PR branch. Merging stays a human
   action, as it does for every PR.
4. **A coding agent implements it** — `verify.mjs` first, then
   `/github_kit implement docs/ai/design-handoffs/<file>.md`, setting `in-progress` and following
   the normal lifecycle in `docs/ai/AGENT_WORKFLOW.md`.
5. **On merge**, the agent sets `landed` and records the PR number.

If a spec is wrong, **Request changes** instead of approving. The workflow only ever acts on
`approved`, so a change request stamps nothing and the file stays `ready`.

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
