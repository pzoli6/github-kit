#!/usr/bin/env node
/**
 * Verifies that a spec's approval marker corresponds to a real GitHub event by a
 * real human with write access — before any agent implements it.
 *
 *   node scripts/design-handoffs/verify.mjs docs/ai/design-handoffs/design-001-foo.md
 *
 * Run this first when `/github_kit implement <path>` is invoked. Without it,
 * `status: approved` is just text, and text is exactly what an agent can write.
 * The marker is only worth something because it is re-checkable: this re-fetches
 * the event named in the front matter and confirms it really happened, by the login
 * recorded as `approved-by`, from a non-bot account that can authorize work in this
 * repo, on a PR that actually touches this very file.
 *
 * Two kinds of event count, per `approval-via`:
 *   review  — an APPROVED pull_request_review (`approval-review-id`). GitHub forbids
 *             approving your own PR, so author and approver are different accounts.
 *   comment — a PR comment whose first line is the marker phrase, default
 *             `/approve-spec`, overridable with SPEC_APPROVAL_MARKER
 *             (`approval-comment-id`). The form a solo repo uses, where the person
 *             who opens the spec PR is also the person who approves it.
 *
 * Files stamped before `approval-via` existed carry no such key and are read as
 * `review`, so an older approved spec keeps verifying unchanged.
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

const MARKER = process.env.SPEC_APPROVAL_MARKER || '/approve-spec';

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
      'No human has approved this scope — open it as a spec PR and request approval.',
  );
}

// Absent means a marker written before this key existed, and those were all reviews.
const via = fm['approval-via'] || 'review';
if (via !== 'review' && via !== 'comment') {
  fail(`approval-via is "${via}" — expected "review" or "comment".`);
}
const idKey = via === 'review' ? 'approval-review-id' : 'approval-comment-id';

for (const req of ['approved-by', 'approved-on', 'approval-pr', idKey]) {
  if (!fm[req]) {
    fail(
      `status is "approved" but "${req}" is missing. The marker was not written by the ` +
        'approval workflow, so it cannot be trusted — most likely someone (or something) typed it by hand.',
    );
  }
}

/** Fetch the named event and reduce both kinds to the same handful of facts. */
function loadEvent() {
  if (via === 'review') {
    let review;
    try {
      review = JSON.parse(
        sh(['api', `repos/${repo}/pulls/${fm['approval-pr']}/reviews/${fm[idKey]}`]),
      );
    } catch (e) {
      fail(
        `Could not fetch review ${fm[idKey]} on PR #${fm['approval-pr']} in ${repo}: ` +
          String(e.stderr || e.message).trim(),
      );
    }
    if (review.state !== 'APPROVED') {
      fail(`Review ${fm[idKey]} has state "${review.state}", not APPROVED.`);
    }
    return { user: review.user, at: review.submitted_at, url: review.html_url };
  }

  let comment;
  try {
    comment = JSON.parse(sh(['api', `repos/${repo}/issues/comments/${fm[idKey]}`]));
  } catch (e) {
    fail(
      `Could not fetch comment ${fm[idKey]} in ${repo}: ` + String(e.stderr || e.message).trim(),
    );
  }
  // A comment id is repo-wide, so the comment must be shown to belong to the PR the
  // marker names — otherwise a `/approve-spec` posted on any other PR would validate this one.
  const wantIssue = `/repos/${repo}/issues/${fm['approval-pr']}`;
  if (!String(comment.issue_url || '').endsWith(wantIssue)) {
    fail(
      `Comment ${fm[idKey]} belongs to ${comment.issue_url || 'an unknown issue'}, ` +
        `not PR #${fm['approval-pr']} — the approval belongs to a different thread.`,
    );
  }
  const first = String(comment.body || '')
    .split(/\r?\n/)[0]
    .trim();
  if (first !== MARKER) {
    fail(
      `Comment ${fm[idKey]} does not approve anything — its first line is ` +
        `"${first}", not "${MARKER}".`,
    );
  }
  return { user: comment.user, at: comment.created_at, url: comment.html_url };
}

const ev = loadEvent();

if (ev.user?.login !== fm['approved-by']) {
  fail(`Approval came from "${ev.user?.login}" but the file claims "${fm['approved-by']}".`);
}
if (ev.user?.type === 'Bot') fail(`Approval came from a bot account ("${ev.user.login}").`);

// Anyone can comment on a public repo, and a review can be left by a non-collaborator too,
// so being a human is not enough — the approver has to be someone who can authorize work
// here. The stamping workflow checks this at write time; re-checking it here is what makes
// a hand-written marker pointing at a drive-by comment fail.
let perm;
try {
  perm = JSON.parse(
    sh(['api', `repos/${repo}/collaborators/${ev.user.login}/permission`]),
  ).permission;
} catch (e) {
  fail(
    `Could not confirm "${ev.user.login}" has write access to ${repo}: ` +
      String(e.stderr || e.message).trim(),
  );
}
if (!['admin', 'write', 'maintain'].includes(perm)) {
  fail(`"${ev.user.login}" has "${perm}" access to ${repo} — not enough to authorize work here.`);
}

// The event must belong to the PR that introduced this file — otherwise any
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
    `  by       ${ev.user.login} (${ev.user.type}, ${perm})\n` +
    `  via      ${via}\n` +
    `  on       ${ev.at}\n` +
    `  ${via === 'review' ? 'review  ' : 'comment '} ${ev.url}\n\n` +
    '  Approved scope is this file\'s "Acceptance criteria" section and nothing beyond it.\n',
);
