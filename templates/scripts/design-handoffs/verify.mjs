#!/usr/bin/env node
/**
 * Verifies that a spec's approval marker corresponds to a real GitHub review by a
 * real human — before any agent implements it.
 *
 *   node scripts/design-handoffs/verify.mjs docs/ai/design-handoffs/design-001-foo.md
 *
 * Run this first when `/github_kit implement <path>` is invoked. Without it,
 * `status: approved` is just text, and text is exactly what an agent can write.
 * The marker is only worth something because it is re-checkable: this re-fetches
 * the review named in the front matter and confirms it is an APPROVED review,
 * submitted by the login recorded as `approved-by`, by a non-bot account, on a PR
 * that actually touches this very file.
 *
 * Fails closed — any doubt is a non-zero exit. Requires an authenticated `gh`.
 */
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const file = process.argv[2];
if (!file) {
  console.error('usage: node scripts/design-handoffs/verify.mjs <spec.md>');
  process.exit(2);
}

const fail = (msg) => {
  console.error(`\n✗ NOT APPROVED — do not implement.\n  ${msg}\n`);
  process.exit(1);
};

const sh = (args) =>
  execFileSync('gh', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });

// Repo is derived, not hardcoded, so this script works unmodified in every repo
// github-kit installs into.
let repo = process.env.GITHUB_REPOSITORY;
if (!repo) {
  try {
    repo = JSON.parse(sh(['repo', 'view', '--json', 'nameWithOwner'])).nameWithOwner;
  } catch (e) {
    fail(`Could not determine the repository: ${String(e.stderr || e.message).trim()}`);
  }
}

const raw = readFileSync(file, 'utf8');
const lines = raw.split(/\r?\n/);
if (lines[0].trim() !== '---') fail('No YAML front matter.');
const end = lines.findIndex((l, i) => i > 0 && l.trim() === '---');
if (end === -1) fail('Unterminated front matter.');

const fm = {};
for (const line of lines.slice(1, end)) {
  const m = /^([a-z-]+):\s*(.*)$/.exec(line);
  if (m) fm[m[1]] = m[2].split('#')[0].trim();
}

if (fm.status !== 'approved') {
  fail(
    `status is "${fm.status || 'unset'}", not "approved". ` +
      'No human has approved this scope — open it as a spec PR and request review.',
  );
}
for (const req of ['approved-by', 'approved-on', 'approval-pr', 'approval-review-id']) {
  if (!fm[req]) {
    fail(
      `status is "approved" but "${req}" is missing. The marker was not written by the ` +
        'approval workflow, so it cannot be trusted — most likely someone (or something) typed it by hand.',
    );
  }
}

let review;
try {
  review = JSON.parse(sh(['api', `repos/${repo}/pulls/${fm['approval-pr']}/reviews/${fm['approval-review-id']}`]));
} catch (e) {
  fail(
    `Could not fetch review ${fm['approval-review-id']} on PR #${fm['approval-pr']} in ${repo}: ` +
      String(e.stderr || e.message).trim(),
  );
}

if (review.state !== 'APPROVED') fail(`Review ${fm['approval-review-id']} has state "${review.state}", not APPROVED.`);
if (review.user?.login !== fm['approved-by']) {
  fail(`Review was submitted by "${review.user?.login}" but the file claims "${fm['approved-by']}".`);
}
if (review.user?.type === 'Bot') fail(`Review was submitted by a bot account ("${review.user.login}").`);

// The review must belong to the PR that introduced this file — otherwise any
// approved PR number in the repo would validate any spec.
let prFiles = [];
try {
  prFiles = JSON.parse(sh(['api', '--paginate', `repos/${repo}/pulls/${fm['approval-pr']}/files`])).map(
    (f) => f.filename,
  );
} catch (e) {
  fail(`Could not list files on PR #${fm['approval-pr']}: ${String(e.stderr || e.message).trim()}`);
}
const wanted = file.split('\\').join('/').replace(/^\.\//, '');
if (!prFiles.includes(wanted)) {
  fail(`PR #${fm['approval-pr']} does not touch ${wanted} — the approval belongs to a different change.`);
}

console.log(
  `\n✓ APPROVED — ${wanted}\n` +
    `  by       ${review.user.login} (${review.user.type})\n` +
    `  on       ${review.submitted_at}\n` +
    `  review   ${review.html_url}\n\n` +
    '  Approved scope is this file\'s "Acceptance criteria" section and nothing beyond it.\n',
);
