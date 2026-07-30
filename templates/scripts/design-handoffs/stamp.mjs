#!/usr/bin/env node
/**
 * Writes the human-approval marker onto a spec file.
 *
 * Installed by github-kit. Run ONLY by
 * .github/workflows/design-handoff-approval.yml, from a `pull_request_review`
 * event whose state is `approved`. Every value it writes comes from that event
 * payload — never from a human typing it, never from an agent inventing it.
 *
 * That is the whole design. A marker a human types by hand is one an agent can
 * type too, so it proves nothing to whoever reads the file next. Deriving it
 * from a recorded review makes it re-checkable — see verify.mjs.
 *
 *   node scripts/design-handoffs/stamp.mjs --dir <spec-dir> \
 *     --by <login> --on <iso8601> --pr <number> --review-id <id> <file>...
 *
 * Exits 0 having changed nothing when there is nothing legitimate to stamp, so a
 * review on an unrelated PR is a no-op rather than a failure.
 */
import { readFileSync, writeFileSync } from 'node:fs';

const args = process.argv.slice(2);
const opts = {};
const files = [];
for (let i = 0; i < args.length; i += 1) {
  if (args[i].startsWith('--')) {
    opts[args[i].slice(2)] = args[i + 1];
    i += 1;
  } else {
    files.push(args[i]);
  }
}

for (const req of ['by', 'on', 'pr', 'review-id']) {
  if (!opts[req]) {
    console.error(`stamp: missing --${req}`);
    process.exit(2);
  }
}

const dir = (opts.dir || 'docs/ai/design-handoffs').replace(/\/+$/, '') + '/';

/** Replace `key: ...` inside the front matter block only, or append it there. */
function setKey(lines, endIdx, key, value) {
  const idx = lines.findIndex((l, i) => i > 0 && i < endIdx && new RegExp(`^${key}:`).test(l));
  if (idx === -1) {
    lines.splice(endIdx, 0, `${key}: ${value}`);
    return endIdx + 1;
  }
  lines[idx] = `${key}: ${value}`;
  return endIdx;
}

let changed = 0;
for (const file of files) {
  const posix = file.split('\\').join('/');

  // Path containment: never touch anything outside the governed directory, even
  // if the workflow hands us a surprising list.
  if (!posix.startsWith(dir) || !posix.endsWith('.md')) {
    console.log(`skip (outside ${dir}): ${posix}`);
    continue;
  }
  const base = posix.slice(posix.lastIndexOf('/') + 1);
  if (base === 'README.md' || base.startsWith('_')) {
    console.log(`skip (not a spec): ${posix}`);
    continue;
  }

  const raw = readFileSync(file, 'utf8');
  const eol = raw.includes('\r\n') ? '\r\n' : '\n';
  const lines = raw.split(/\r?\n/);
  if (lines[0].trim() !== '---') {
    console.log(`skip (no front matter): ${posix}`);
    continue;
  }
  const endIdx = lines.findIndex((l, i) => i > 0 && l.trim() === '---');
  if (endIdx === -1) {
    console.log(`skip (unterminated front matter): ${posix}`);
    continue;
  }

  const statusLine = lines.findIndex((l, i) => i > 0 && i < endIdx && /^status:/.test(l));
  const status =
    statusLine === -1 ? '' : lines[statusLine].replace(/^status:\s*/, '').split('#')[0].trim();

  // Only `ready` is approvable. A `draft` is a moving target, so approving one
  // would approve something still being written; anything at `approved` or past
  // it is already claimed. Both are left alone rather than silently overwritten —
  // in particular this means a second review cannot rewrite an existing marker.
  if (status !== 'ready') {
    console.log(`skip (status is "${status || 'unset'}", only "ready" is approvable): ${posix}`);
    continue;
  }

  lines[statusLine] = 'status: approved';
  let end = endIdx;
  end = setKey(lines, end, 'approved-by', opts.by);
  end = setKey(lines, end, 'approved-on', opts.on);
  end = setKey(lines, end, 'approval-pr', opts.pr);
  setKey(lines, end, 'approval-review-id', opts['review-id']);

  writeFileSync(file, lines.join(eol));
  console.log(`stamped approved (${opts.by}, ${opts.on}): ${posix}`);
  changed += 1;
}

console.log(`stamp: ${changed} file(s) changed.`);
