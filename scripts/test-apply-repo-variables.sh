#!/usr/bin/env bash
# Behaviour test for scripts/apply-repo-variables.sh.
#
# Runs the real script from a throwaway kit root (its own .github/fanout-targets.json) against a
# fake `gh` that keeps repository variables as files and logs every write. Asserts that:
#   - --dry-run and a matching value change nothing; a differing or unset value is set
#   - --repo limits the run to one registry entry; a repo gh cannot read is FAILED, exit 1
#   - CRLF output (a native Windows jq.exe or gh.exe) never leaks a CR into the value that is set
#   - a missing jq fails early with an install hint instead of half-running
#
# Usage: scripts/test-apply-repo-variables.sh    (needs bash, jq)
set -uo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS    $1"; }
fail() { echo "FAIL    $1"; failures=$((failures + 1)); }

REAL_JQ="$(command -v jq)" || { echo "FAIL    jq is required to run this test"; exit 1; }

# Throwaway kit root: the script under test plus a small registry.
mkdir -p "$WORK/kit/scripts" "$WORK/kit/.github" "$WORK/bin" "$WORK/crlf-bin"
cp "$KIT_ROOT/scripts/apply-repo-variables.sh" "$WORK/kit/scripts/"
cat > "$WORK/kit/.github/fanout-targets.json" <<'JSON'
{ "targets": [
  { "repo": "o/unset",  "variables": { "KIT_AUTOMERGE_ALLOW_NO_CHECKS": "true" } },
  { "repo": "o/same",   "variables": { "KIT_AUTOMERGE_ALLOW_NO_CHECKS": "true" } },
  { "repo": "o/differ", "variables": { "KIT_AUTOMERGE_ALLOW_NO_CHECKS": "true" } },
  { "repo": "o/none" }
] }
JSON

# Fake gh: `gh variable list --repo R ...` prints the value of the name in the --jq filter;
# `gh variable set NAME --repo R --body V` stores it. State: $GH_STATE/<owner>_<repo>/<NAME>.
# FAKE_GH_DENY=<repo> makes reads of that repo fail; FAKE_GH_CRLF=1 ends output with CRLF.
cat > "$WORK/bin/gh" <<'SH'
#!/usr/bin/env bash
sub="$1 $2"; shift 2
repo="" body="" name="" filter=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --body) body="$2"; shift 2 ;;
    --jq) filter="$2"; shift 2 ;;
    --json) shift 2 ;;
    *) name="$1"; shift ;;
  esac
done
dir="$GH_STATE/${repo//\//_}"
case "$sub" in
  "variable list")
    [ "$repo" != "${FAKE_GH_DENY:-}" ] || { echo "HTTP 403" >&2; exit 1; }
    want="$(printf '%s' "$filter" | sed -n 's/.*\.name == "\([^"]*\)".*/\1/p')"
    if [ -f "$dir/$want" ]; then
      if [ -n "${FAKE_GH_CRLF:-}" ]; then printf '%s\r\n' "$(cat "$dir/$want")"
      else printf '%s\n' "$(cat "$dir/$want")"; fi
    fi ;;
  "variable set")
    mkdir -p "$dir"; printf '%s' "$body" > "$dir/$name"
    printf 'set %s %s\n' "$repo" "$name" >> "$GH_STATE/writes.log" ;;
  *) echo "fake gh: unsupported: $sub" >&2; exit 2 ;;
esac
SH
chmod +x "$WORK/bin/gh"

# CRLF jq: the real jq with every output line ending in CR LF, as a native Windows jq.exe does.
cat > "$WORK/crlf-bin/jq" <<SH
#!/usr/bin/env bash
"$REAL_JQ" "\$@" | sed 's/\$/\r/'
SH
chmod +x "$WORK/crlf-bin/jq"

# reset: o/same already holds "true", o/differ holds "false", o/unset has nothing.
reset() {
  rm -rf "$GH_STATE"; mkdir -p "$GH_STATE/o_same" "$GH_STATE/o_differ"
  printf 'true' > "$GH_STATE/o_same/KIT_AUTOMERGE_ALLOW_NO_CHECKS"
  printf 'false' > "$GH_STATE/o_differ/KIT_AUTOMERGE_ALLOW_NO_CHECKS"
  : > "$GH_STATE/writes.log"
}
value_of() { cat "$GH_STATE/${1//\//_}/KIT_AUTOMERGE_ALLOW_NO_CHECKS" 2>/dev/null || echo "<unset>"; }
writes() { wc -l < "$GH_STATE/writes.log" | tr -d ' '; }
run() { PATH="$WORK/bin:$PATH" bash "$WORK/kit/scripts/apply-repo-variables.sh" "$@" > "$WORK/out" 2>&1; }
export GH_STATE="$WORK/state"

# 1. dry run: reports, writes nothing.
reset; run --dry-run; rc=$?
if [ "$rc" -eq 0 ] && [ "$(writes)" = 0 ] && grep -q '^WOULD   o/unset' "$WORK/out" \
   && grep -q '^WOULD   o/differ' "$WORK/out" && grep -q '^OK      o/same' "$WORK/out"; then
  pass "--dry-run reports WOULD/OK and changes nothing"
else fail "--dry-run (rc=$rc, writes=$(writes)): $(cat "$WORK/out")"; fi

# 2. apply: sets exactly the two that differ, to exactly "true".
reset; run; rc=$?
if [ "$rc" -eq 0 ] && [ "$(writes)" = 2 ] && [ "$(value_of o/unset)" = true ] \
   && [ "$(value_of o/differ)" = true ] && ! grep -q 'o/none' "$WORK/out"; then
  pass "apply sets unset and differing values, skips matches and repos without variables"
else fail "apply (rc=$rc, writes=$(writes)): $(cat "$WORK/out")"; fi

# 3. apply again: idempotent.
run; rc=$?
if [ "$rc" -eq 0 ] && [ "$(writes)" = 2 ] && grep -q 'already matches' "$WORK/out"; then
  pass "second apply is a no-op"
else fail "second apply (rc=$rc, writes=$(writes)): $(cat "$WORK/out")"; fi

# 4. --repo limits the run.
reset; run --repo o/unset; rc=$?
if [ "$rc" -eq 0 ] && [ "$(writes)" = 1 ] && [ "$(value_of o/differ)" = false ]; then
  pass "--repo touches only that repo"
else fail "--repo (rc=$rc, writes=$(writes)): $(cat "$WORK/out")"; fi

# 5. an unreadable repo is FAILED and the exit code says so; the others still apply.
reset; FAKE_GH_DENY=o/differ run; rc=$?
if [ "$rc" -eq 1 ] && grep -q '^FAILED  o/differ' "$WORK/out" && [ "$(value_of o/unset)" = true ]; then
  pass "unreadable repo reported FAILED, exit 1, others applied"
else fail "unreadable repo (rc=$rc): $(cat "$WORK/out")"; fi

# 6. CRLF from jq and gh (Windows): values set without CR, matches still recognised.
reset
PATH="$WORK/crlf-bin:$WORK/bin:$PATH" FAKE_GH_CRLF=1 \
  bash "$WORK/kit/scripts/apply-repo-variables.sh" > "$WORK/out" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ "$(writes)" = 2 ] && [ "$(value_of o/unset)" = true ] \
   && [ "$(value_of o/differ)" = true ] && grep -q '^OK      o/same' "$WORK/out" \
   && ! grep -q $'\r' "$GH_STATE/o_unset/KIT_AUTOMERGE_ALLOW_NO_CHECKS" "$GH_STATE/writes.log"; then
  pass "CRLF output from jq/gh never reaches the value that is set"
else fail "CRLF (rc=$rc, writes=$(writes)): $(cat -A "$WORK/out")"; fi

# 7. no jq: fails before touching anything, with an install hint.
mkdir -p "$WORK/nojq-bin"
for t in dirname sed; do ln -sf "$(command -v "$t")" "$WORK/nojq-bin/$t"; done
reset
PATH="$WORK/bin:$WORK/nojq-bin" "$BASH" "$WORK/kit/scripts/apply-repo-variables.sh" > "$WORK/out" 2>&1; rc=$?
if [ "$rc" -eq 1 ] && [ "$(writes)" = 0 ] && grep -q 'winget install jqlang.jq' "$WORK/out"; then
  pass "missing jq fails early with an install hint"
else fail "missing jq (rc=$rc): $(cat "$WORK/out")"; fi

echo
if [ "$failures" -ne 0 ]; then echo "$failures apply-repo-variables test(s) failed"; exit 1; fi
echo "apply-repo-variables behaves as documented."
