---
last-synced-commit:
last-synced-on:
last-round: 0
feedback-file: docs/ai/DESIGN_FEEDBACK.md
---

# DESIGN_SYNC.md — the design tool's reading list, and the record of what it has read

This file exists for repos where a design tool (Claude Design or its kin) reads the repository
directly through a read-only GitHub integration. It is the tool's single entry point: what to
read, what changed since it last read, and how its answers get back into the repo — because the
tool cannot write here. Its only write path is its export bundle, and the bundle's answers file is
applied by `scripts/design-handoffs/apply-answers.mjs`, nothing else. The protocol behind all of
this is `README.md` → "The sync loop".

If no design tool reads this repo directly, this file stays as installed and costs nothing.

## State (the front matter above)

| Key | Meaning | Written by |
| --- | --- | --- |
| `last-synced-commit` | The commit the design tool last read. Unset until the first applied round. | `apply-answers.mjs` only |
| `last-synced-on` | Timestamp copied from the answers file's `generated-on`. | `apply-answers.mjs` only |
| `last-round` | Monotonic round counter. A bundle whose `round` is not greater than this is refused — the replay guard. | `apply-answers.mjs` only |
| `feedback-file` | Where design-feedback entries live (see "Feedback entries" below). | a human, once |

No human and no agent edits the first three by hand. A sync record someone can type is one an
agent can type too, and then it proves nothing — the same argument that keeps approval markers out
of human hands (`README.md` → "The one rule that matters").

## The reading list

Every design-facing document lives on this list. A document not listed here does not exist as far
as the design tool is concerned — which is why the list must be complete, and why adding a design
doc anywhere else without listing it is exactly the bug this file prevents.

Replace the placeholder rows with this repo's real design surface:

| Path | What it is | Design-readable |
| --- | --- | --- |
| `docs/ai/design-handoffs/` | Specs waiting to be built, and this file | yes |
| `docs/ai/design-prompts/` | Briefs written for the design tool | yes |
| `<the feedback file named in the front matter>` | Implementation feedback to design | yes |
| `<large generated artifact, e.g. a 1 MB preview html>` | `<what it is>` | **no — too large** |

**Too large means unreadable, not absent.** Design tools have a per-file read window; a file past
it fails to read, and that failure surfaces as "the file isn't there." Mark such files
`no — too large` so the tool skips them knowingly. The rule, for both sides of the loop:
**"could not read" must never be reported — or acted on — as "does not exist."** A coding agent
told that a flagged file is missing checks the tree before believing it.

The coding agent that applies each round keeps this table current — a new design-facing doc gets
its row in the same PR that adds the doc.

## The sync prompt

Paste this into the design tool to run a round, with the placeholder filled from the front matter
(on the first round `last-synced-commit` is still unset — the prompt itself says what to do
instead):

> Sync this project with its GitHub source. Read `docs/ai/design-handoffs/DESIGN_SYNC.md` first —
> it is the reading list. What changed since your last sync is exactly
> `git log --name-only <last-synced-commit>..HEAD` restricted to the listed paths; go by commits,
> never by file counts. If `last-synced-commit` is unset, this is the first round: read the full
> reading list instead. Either way, note the `HEAD` commit you actually read — it becomes
> `synced-commit` in your answers file. Treat files the list marks not design-readable as present
> but unreadable — never as missing. Rebuild what the changes affect and answer the open
> decisions. You cannot write to this repository: put a `design-sync-answers.json` (format
> `design-sync-answers/v1`, spec in `docs/ai/design-handoffs/README.md` → "The sync loop") in
> your export bundle, and a coding agent will apply it.

## Feedback entries and round headers

The file named by `feedback-file` holds implementation → design feedback as one section per
entry: a heading whose text starts with the entry id, containing a bold status list item —

```markdown
### DF-042 — empty state renders under the wrong token

- **status:** open
- <whatever else the entry needs>
```

New entries from each round go under a round header, so the design tool reads rounds instead of a
moving wall of text:

```markdown
## Round <N> — synced <short-sha>
```

`apply-answers.mjs` flips entry statuses and appends the resolution lines from the answers file.
Nobody edits those lines by hand — see "State" above for why.

## Decision log

Appended by `apply-answers.mjs` from each round's `decisions`. Do not edit by hand.
