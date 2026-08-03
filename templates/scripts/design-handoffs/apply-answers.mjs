#!/usr/bin/env node
/**
 * Applies a design tool's exported answers to this repository — the write half of
 * the sync loop described in docs/ai/design-handoffs/DESIGN_SYNC.md.
 *
 * Design tools that read a repo directly (Claude Design and its kin) have a
 * read-only GitHub integration: their only write path is the export bundle. Left to
 * hand transcription, the statuses in that bundle and the statuses in the repo fork
 * silently — entries the design round resolved keep reading `open` here forever. So
 * the bundle carries a machine-readable answers file, and this script is the only
 * thing that writes its contents into the repo:
 *
 *   node scripts/design-handoffs/apply-answers.mjs <answers.json> [--dry-run] \
 *     [--sync docs/ai/design-handoffs/DESIGN_SYNC.md]
 *
 * Everything it writes, and all it ever writes:
 *   - the status word on feedback entries named by id — never body text;
 *   - one generated resolution line per entry, directly after the status line;
 *   - decision-log lines in DESIGN_SYNC.md;
 *   - the sync state in DESIGN_SYNC.md front matter (last-synced-commit,
 *     last-round, last-synced-on).
 *
 * Nobody hand-edits any of those. A status a human types is one an agent can type
 * too, and then the record proves nothing — stamp.mjs makes the same argument about
 * approval markers. The answers file is the artifact of record; keep it with the
 * bundle if you want the edit re-checkable later.
 *
 * Fails closed: every answer is validated against the current tree first, and
 * either the whole round applies or nothing does. A round already applied is
 * refused (replay guard); an entry or decision the repo already records with the
 * same text is a counted no-op, not an error — design tools export full state,
 * not deltas, so a later round restating an old answer must cost nothing.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const FORMAT = 'design-sync-answers/v1';
// `open` is the state entries start in and humans set; the bundle can only move an
// entry forward. Reopening is a human act in the repo, not something a bundle does.
const ALLOWED_STATUSES = ['answered', 'resolved-in-design', 'declined', 'superseded'];
const ENTRY_ID_RE = /^[A-Z][A-Z0-9]*-\d+$/;
const DECISION_ID_RE = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

const args = process.argv.slice(2);
let answersPath;
let syncPath = 'docs/ai/design-handoffs/DESIGN_SYNC.md';
let dryRun = false;
for (let i = 0; i < args.length; i += 1) {
  if (args[i] === '--dry-run') dryRun = true;
  else if (args[i] === '--sync') {
    syncPath = args[i + 1];
    i += 1;
  } else if (!answersPath) answersPath = args[i];
  else {
    console.error(`apply-answers: unexpected argument "${args[i]}"`);
    process.exit(2);
  }
}
if (!answersPath || !syncPath) {
  console.error(
    'usage: node scripts/design-handoffs/apply-answers.mjs <answers.json> [--dry-run] [--sync <DESIGN_SYNC.md>]',
  );
  process.exit(2);
}

const fail = (msg) => {
  console.error(`\n✗ NOT APPLIED — nothing was changed.\n  ${msg}\n`);
  process.exit(1);
};

/** One line, always: what keeps "resolution" and "answer" text from becoming body edits. */
const oneLine = (s) => String(s).replace(/\s+/g, ' ').trim();

// ---- read and validate the answers file, before touching anything ------------

let answers;
try {
  // Windows editors and export pipelines love UTF-8 BOMs; a BOM is not a reason
  // to refuse an otherwise valid bundle.
  answers = JSON.parse(readFileSync(answersPath, 'utf8').replace(/^﻿/, ''));
} catch (e) {
  fail(`Could not read ${answersPath} as JSON: ${e.message}`);
}
if (answers.format !== FORMAT) {
  fail(`format is "${answers.format || 'unset'}", not "${FORMAT}" — refusing to guess.`);
}

// Lowercased so every later comparison — and the short SHA embedded in logged
// lines — is case-stable regardless of how the tool printed it.
const sha = String(answers['synced-commit'] || '').toLowerCase();
if (!/^[0-9a-f]{7,40}$/.test(sha)) {
  fail(`synced-commit "${sha || 'unset'}" is not a commit SHA.`);
}
// The SHA must name a commit this repo actually has — otherwise the "record of what
// design read" would record something unverifiable.
try {
  execFileSync('git', ['cat-file', '-e', `${sha}^{commit}`], { stdio: 'ignore' });
} catch {
  fail(`synced-commit ${sha} is not a commit in this repository — wrong repo, or a typo in the bundle.`);
}

const round = answers.round;
if (!Number.isInteger(round) || round < 1) {
  fail(`round is ${JSON.stringify(round)} — expected an integer ≥ 1.`);
}

const entries = answers.entries ?? [];
const decisions = answers.decisions ?? [];
if (!Array.isArray(entries) || !Array.isArray(decisions)) {
  fail('"entries" and "decisions" must be arrays when present.');
}
const seenIds = new Set();
for (const e of entries) {
  if (!e || typeof e !== 'object') fail('"entries" contains a non-object element.');
  if (!ENTRY_ID_RE.test(String(e.id || ''))) {
    fail(`entry id "${e.id || 'unset'}" does not look like an entry id (e.g. DF-042).`);
  }
  if (seenIds.has(e.id)) fail(`entry "${e.id}" appears twice in the answers file.`);
  seenIds.add(e.id);
  if (!ALLOWED_STATUSES.includes(e.status)) {
    fail(
      `entry "${e.id}" has status "${e.status || 'unset'}" — allowed: ${ALLOWED_STATUSES.join(', ')}.`,
    );
  }
}
for (const d of decisions) {
  if (!d || typeof d !== 'object') fail('"decisions" contains a non-object element.');
  if (!DECISION_ID_RE.test(String(d.id || ''))) {
    fail(`decision id "${d.id || 'unset'}" is not a plain token.`);
  }
  if (!d.answer || !oneLine(d.answer)) fail(`decision "${d.id}" has no answer text.`);
}

// ---- load both target files -------------------------------------------------

/** Preserve each file's own line endings and trailing newline — this script edits
 *  single lines, it does not get to reformat the file around them. */
function loadLines(path) {
  let raw;
  try {
    raw = readFileSync(path, 'utf8');
  } catch (e) {
    fail(`Could not read ${path}: ${e.message}`);
  }
  return {
    path,
    raw,
    lines: raw.split(/\r?\n/),
    eol: raw.includes('\r\n') ? '\r\n' : '\n',
    changed: false,
  };
}
const save = (f) => writeFileSync(f.path, f.lines.join(f.eol));

const sync = loadLines(syncPath);
if ((sync.lines[0] || '').trim() !== '---') fail(`${syncPath} has no YAML front matter.`);
const fmEnd = sync.lines.findIndex((l, i) => i > 0 && l.trim() === '---');
if (fmEnd === -1) fail(`${syncPath} has unterminated front matter.`);

const fm = {};
for (const line of sync.lines.slice(1, fmEnd)) {
  const m = /^([a-z-]+):\s*(.*)$/.exec(line);
  if (m) fm[m[1]] = m[2].split('#')[0].trim();
}

const lastRound = fm['last-round'] ? Number(fm['last-round']) : 0;
if (!Number.isFinite(lastRound)) fail(`last-round "${fm['last-round']}" in ${syncPath} is not a number.`);
if (round <= lastRound) {
  fail(
    `round ${round} is not greater than last-round ${lastRound} — this bundle was already applied ` +
      '(or an old bundle is being replayed).',
  );
}

let feedback = null;
if (entries.length > 0) {
  if (!fm['feedback-file']) fail(`${syncPath} names no feedback-file, but the bundle has entries.`);
  feedback = loadLines(fm['feedback-file']);
}

// ---- locate every entry before editing any ----------------------------------

const heading = (line) => /^(#{1,6})\s+(.*)$/.exec(line);

/** True for every line that sits inside (or delimits) a ``` / ~~~ fence. The kit's
 *  own DESIGN_SYNC.md teaches the entry format with a fenced example — a quoted
 *  example must never be matched, counted, or edited as a real heading or status
 *  line. */
function fenceMask(lines) {
  const mask = new Array(lines.length).fill(false);
  let open = null;
  for (let i = 0; i < lines.length; i += 1) {
    const m = /^\s{0,3}(`{3,}|~{3,})/.exec(lines[i]);
    if (m && !open) {
      open = m[1][0];
      mask[i] = true;
    } else if (open) {
      mask[i] = true;
      if (m && m[1][0] === open) open = null;
    }
  }
  return mask;
}

/** A heading "owns" an entry when its text is the id followed by nothing or a
 *  separator (whitespace, ':', ',', ']', ')', en/em dash) — "### DF-42 — title"
 *  matches DF-42 but never DF-4, and a suffixed sibling like "DF-1-b" or "DF-1.2"
 *  is never an answer target for DF-1. */
function findSection(lines, mask, id) {
  const hits = [];
  for (let i = 0; i < lines.length; i += 1) {
    if (mask[i]) continue;
    const h = heading(lines[i]);
    if (!h) continue;
    const text = h[2].replace(/^[[(]\s*/, '');
    const next = text[id.length];
    if (text.startsWith(id) && (next === undefined || /[\s:,\])–—]/.test(next))) {
      hits.push({ start: i, level: h[1].length });
    }
  }
  if (hits.length !== 1) return { hits: hits.length };
  const { start, level } = hits[0];
  let end = lines.length;
  for (let i = start + 1; i < lines.length; i += 1) {
    if (mask[i]) continue;
    const h = heading(lines[i]);
    if (h && h[1].length <= level) {
      end = i;
      break;
    }
  }
  return { hits: 1, start, end };
}

const STATUS_RE = /^(\s*)([-*])(\s+)\*\*status:\*\*\s*([A-Za-z-]+)\s*$/;
const RESOLUTION_RE = /^\s*[-*]\s+\*\*resolution \(round \d+\):\*\*\s*(.*)$/;

const plan = [];
const fbMask = feedback ? fenceMask(feedback.lines) : [];
for (const e of entries) {
  const sec = findSection(feedback.lines, fbMask, e.id);
  if (sec.hits === 0) fail(`entry "${e.id}" not found in ${feedback.path} — the bundle answers something this repo does not have.`);
  if (sec.hits > 1) fail(`entry "${e.id}" matches ${sec.hits} headings in ${feedback.path} — ids must be unique.`);
  const statusAt = [];
  const priorResolutions = [];
  for (let i = sec.start + 1; i < sec.end; i += 1) {
    if (fbMask[i]) continue;
    if (STATUS_RE.test(feedback.lines[i])) statusAt.push(i);
    const r = RESOLUTION_RE.exec(feedback.lines[i]);
    if (r) priorResolutions.push(r[1].trim());
  }
  if (statusAt.length !== 1) {
    fail(
      `entry "${e.id}" has ${statusAt.length} "- **status:**" lines in its section — expected exactly one.`,
    );
  }
  // A later round restating a resolution this section already carries (whatever
  // round said it first) adds nothing — full-state bundles restate constantly.
  const restated = e.resolution ? priorResolutions.includes(oneLine(e.resolution)) : true;
  plan.push({ ...e, line: statusAt[0], restated });
}

// ---- apply ------------------------------------------------------------------

let entriesUpdated = 0;
let entriesCurrent = 0;
// Bottom-up, so inserting a resolution line never shifts a later entry's line number.
for (const p of [...plan].sort((a, b) => b.line - a.line)) {
  const m = STATUS_RE.exec(feedback.lines[p.line]);
  const bullet = `${m[1]}${m[2]}${m[3]}`;
  const resolution = p.restated ? null : `${bullet}**resolution (round ${round}):** ${oneLine(p.resolution)}`;
  if (m[4] === p.status && !resolution) {
    entriesCurrent += 1;
    continue;
  }
  entriesUpdated += 1;
  if (dryRun) {
    console.log(`  would set ${p.id}: ${m[4]} → ${p.status}${resolution ? ' (+ resolution line)' : ''}`);
    continue;
  }
  feedback.lines[p.line] = `${bullet}**status:** ${p.status}`;
  if (resolution) feedback.lines.splice(p.line + 1, 0, resolution);
  feedback.changed = true;
}

// Decisions land in DESIGN_SYNC.md's own "## Decision log", created at the end if a
// repo's copy predates the section.
const syncMask = fenceMask(sync.lines);
let logAt = sync.lines.findIndex((l, i) => !syncMask[i] && /^##\s+Decision log\s*$/.test(l));
if (logAt === -1 && !dryRun) {
  while (sync.lines.length > 0 && sync.lines[sync.lines.length - 1].trim() === '') sync.lines.pop();
  // The final '' is the trailing newline — it stays the last element.
  sync.lines.push('', '## Decision log', '');
  logAt = sync.lines.length - 2;
  sync.changed = true;
}

let decisionsRecorded = 0;
let decisionsCurrent = 0;
const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
for (const d of decisions) {
  // The mask is recomputed per decision because each insertion shifts the lines.
  const mask = fenceMask(sync.lines);
  // Same restatement rule as resolutions: an identical answer already logged in
  // any earlier round is current; only a genuinely new (or changed) answer lands.
  const priorRe = new RegExp(`^- \\*\\*${escapeRe(d.id)}\\*\\* — round \\d+ \\([0-9a-f]+\\): (.*)$`);
  const prior = sync.lines.map((l, i) => (mask[i] ? null : priorRe.exec(l))).filter(Boolean);
  if (prior.some((p) => p[1].trim() === oneLine(d.answer))) {
    decisionsCurrent += 1;
    continue;
  }
  decisionsRecorded += 1;
  if (dryRun) {
    console.log(`  would record decision ${d.id}`);
    continue;
  }
  // Insert at the end of the Decision log section, before any later heading.
  let insertAt = sync.lines.length;
  for (let i = logAt + 1; i < sync.lines.length; i += 1) {
    if (!mask[i] && heading(sync.lines[i])) {
      insertAt = i;
      break;
    }
  }
  while (insertAt > logAt + 1 && sync.lines[insertAt - 1].trim() === '') insertAt -= 1;
  // Keep the log a list of its own: a blank line between the section's prose and
  // the first logged entry.
  const prev = sync.lines[insertAt - 1] ?? '';
  const toInsert = prev.trim() !== '' && !prev.startsWith('- ') ? ['', entryLine(d)] : [entryLine(d)];
  sync.lines.splice(insertAt, 0, ...toInsert);
  sync.changed = true;
}
function entryLine(d) {
  return `- **${d.id}** — round ${round} (${sha.slice(0, 7)}): ${oneLine(d.answer)}`;
}

// The state keys move last — they are the claim that this round is in the repo, so
// nothing may write them until everything above has succeeded.
function setState(key, value) {
  for (let i = 1; i < fmEnd; i += 1) {
    if (sync.lines[i].startsWith(`${key}:`)) {
      sync.lines[i] = `${key}: ${value}`;
      return;
    }
  }
  sync.lines.splice(fmEnd, 0, `${key}: ${value}`);
}
if (!dryRun) {
  setState('last-synced-commit', sha);
  setState('last-round', String(round));
  if (answers['generated-on']) setState('last-synced-on', oneLine(answers['generated-on']));
  sync.changed = true;

  // Two files, one round: if the second write fails the first is rolled back, so a
  // half-applied round — the fork this tool exists to prevent — cannot be left on disk.
  try {
    if (feedback?.changed) save(feedback);
  } catch (e) {
    fail(`Could not write ${feedback.path}: ${e.message}`);
  }
  try {
    save(sync);
  } catch (e) {
    let note = '';
    if (feedback?.changed) {
      try {
        writeFileSync(feedback.path, feedback.raw);
        note = ` — ${feedback.path} was rolled back; fix the problem and re-run this bundle`;
      } catch {
        note =
          ` — WARNING: ${feedback.path} was already written and could not be rolled back;` +
          ' fix the problem and re-run this bundle to converge (restated answers are no-ops)';
      }
    }
    fail(`Could not write ${sync.path}: ${e.message}${note}`);
  }
}

console.log(
  `\n${dryRun ? '○ DRY RUN — nothing was changed' : '✓ APPLIED'} — round ${round} (${sha.slice(0, 7)})\n` +
    `  entries    ${entriesUpdated} updated, ${entriesCurrent} already current\n` +
    `  decisions  ${decisionsRecorded} recorded, ${decisionsCurrent} already recorded\n` +
    `  state      last-synced-commit → ${sha.slice(0, 7)}, last-round → ${round}\n`,
);
