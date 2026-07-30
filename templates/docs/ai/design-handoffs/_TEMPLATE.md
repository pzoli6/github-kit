---
id: design-000
title: <Surface name — what it is>
status: draft            # draft → ready → approved → in-progress → landed
surface: /<route the user lands on>
receiving-code: <path to the file this replaces or extends, or "new">
answers-prompt: <docs/ai/design-prompts/<file>.md, or "none">
i18n-namespace: <messages namespace, if this repo is localized>
approved-by:             # leave blank — written by the approval workflow from a GitHub review
approved-on:             # leave blank — review timestamp, from the event payload
approval-pr:             # leave blank — the spec PR the review was submitted on
approval-review-id:      # leave blank — re-checked by scripts/design-handoffs/verify.mjs
issue:                   # filled by the coding agent
pr:                      # filled by the coding agent on merge
supersedes:              # id of an earlier entry, if any
---

> Copy this file to `design-<nnn>-<slug>.md`. Read `./README.md` first — in particular the rule
> that an agent acts on `approved` and never on `ready`, and that nobody types the approval marker
> by hand. Delete every angle-bracket placeholder and every instruction line like this one before
> setting `status: ready`.

# <Surface name>

## Purpose

<Two or three sentences. What the user is trying to do here and why the product does not let them
today. If this replaces an existing screen, say what that screen does badly — that is usually the
design constraint that matters most.>

## Receiving code

<The file(s) this lands in, and what is already true about them. If a scaffold exists, say what of
it survives — the backend read model usually does, the markup usually does not. Naming the existing
backend contract makes an entry far more actionable than one that does not.>

## Layout

<Structure only — regions, order, what is sticky, what scrolls, what collapses. Reference this
repo's design tokens rather than restating values; where this file and the tokens disagree, the
tokens win. Call out any hard requirement explicitly and say why.>

### Desktop

<...>

### Mobile

<What changes below the breakpoint. Tables usually become cards; primary actions usually move to a
bottom bar. Say which.>

## Behaviour

<One subsection per interactive element. What it does, what it validates, what it disables, what it
confirms before doing. Destructive actions get their confirm copy written out in full.>

## States

Every row is required. "n/a" is an acceptable value; a blank is not.

| State | Trigger | What the user sees | What the user can do |
| --- | --- | --- | --- |
| Empty | <no records yet> | | |
| Loading | <initial fetch> | | |
| Saving | <submit in flight> | | |
| Success | | | |
| Validation error | <which fields, which rules> | | |
| Server error | <action failed> | | |
| Permission denied | <wrong role> | | |
| Blocked / cannot proceed | <e.g. record is referenced and cannot be deleted> | | |

## Copy

One column per language this repo ships. A spec with only the source language hands the coding
agent an invented translation.

| Key | <source lang> | <other lang> |
| --- | --- | --- |
| `title` | | |
| `description` | | |
| | | |

## Data

<What the surface reads and writes, in domain terms. Name existing models and fields where you know
them. Flag anything with no home in the schema today — that is a decision a human has to make
before this can be approved, not something the coding agent should invent.>

**Requires schema change:** <yes / no. If yes, this entry cannot be approved on its own — a
migration is a separate decision under this repo's migration rules.>

## Accessibility

<Anything beyond this repo's baseline: focus order, what receives focus when a dialog opens and
where it returns on close, live regions for async results, keyboard equivalents for anything
drag-based.>

## Guardrails

<Constraints specific to this surface. Repo-wide guardrails live in `AGENTS.md` and apply without
being restated — list only what is specific here.>

## Out of scope

<Required. What this entry deliberately does not cover, especially adjacent work a reader might
assume is included. Each line is something the coding agent must stop and ask about rather than
build.>

- <...>

## Acceptance criteria

**This section is the approval boundary.** `/github_kit implement <this file>` pre-approves exactly
what is listed here and nothing else. Each line must be checkable by looking at the built surface —
if it cannot be verified, it is not a criterion.

- [ ] <...>
- [ ] Every row of the States table is reachable and matches the described behaviour.
- [ ] <this repo's lint / typecheck / i18n gates pass>

## Open questions

<Anything the author could not resolve. A question here does not block `ready`, but it should be
resolved before anyone approves — an unanswered question inside an approved scope is how an agent
ends up inventing the answer.>

- <...>
