#!/usr/bin/env bash
# Behaviour test for the per-run job labels of the fan-out (scripts/fanout-registry.sh labels / which).
#
# A fan-out job is named by an opaque label: HMAC-SHA256 of "<run id>:<registry index>" keyed with
# FANOUT_LABEL_KEY (or FANOUT_TOKEN), cut to 12 hex chars. Asserts that:
#   - `labels RUN_ID` prints one 12-hex label per registry entry, unique, deterministic for the
#     same run id and key, and different for another run id or another key
#   - `which RUN_ID LABEL` resolves a label to its entry (repo + index), fails with exit 1 for a
#     label the key does not explain, and fails early without a key in the environment
#   - the label recipe in the workflow and in the script are the same line (anything else would
#     make `which` resolve to the wrong repo)
#
# Usage: scripts/test-fanout-labels.sh    (needs bash, jq, openssl)
set -uo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$KIT_ROOT/scripts/fanout-registry.sh"
EX="$KIT_ROOT/.github/fanout-targets.example.json"
WF="$KIT_ROOT/.github/workflows/github-kit-fanout.yml"
failures=0
pass() { echo "PASS    $1"; }
fail() { echo "FAIL    $1"; failures=$((failures + 1)); }

labels() { FANOUT_LABEL_KEY="$1" bash "$S" labels --registry "$EX" "$2" 2>&1; }
which_() { FANOUT_LABEL_KEY="$1" bash "$S" which --registry "$EX" "$2" "$3" 2>&1; }

# 1. one label per entry, 12 hex chars, unique, sorted; the same key and run id reproduce them.
a="$(labels k1 4242)"; b="$(labels k1 4242)"
n="$(jq '.targets | length' "$EX")"
if [ "$(wc -l <<< "$a")" = "$n" ] && [ "$(grep -cE '^[0-9a-f]{12}  [A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' <<< "$a")" = "$n" ] \
   && [ "$(cut -d' ' -f1 <<< "$a" | sort -u | wc -l)" = "$n" ] && [ "$a" = "$b" ]; then
  pass "labels: one 12-hex label per entry, unique, deterministic"
else fail "labels (n=$n): $a"; fi

# 2. another run id or another key relabels everything.
c="$(labels k1 4243)"; d="$(labels k2 4242)"
if [ -z "$(comm -12 <(cut -d' ' -f1 <<< "$a" | sort) <(cut -d' ' -f1 <<< "$c" | sort))" ] \
   && [ -z "$(comm -12 <(cut -d' ' -f1 <<< "$a" | sort) <(cut -d' ' -f1 <<< "$d" | sort))" ]; then
  pass "labels: another run id or key shares no label with the first run"
else fail "relabel: run 4243: $c / key k2: $d"; fi

# 3. which resolves a label to its entry, with the registry index.
lbl="$(grep ' your-org/service$' <<< "$a" | cut -d' ' -f1)"
out="$(which_ k1 4242 "$lbl")"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(jq -r .repo <<< "$out")" = "your-org/service" ] && [ "$(jq -r .index <<< "$out")" = "2" ]; then
  pass "which: label -> entry (repo and index)"
else fail "which (rc=$rc): $out"; fi

# 4. the wrong key explains no label.
out="$(which_ k2 4242 "$lbl")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'differs from the one the run used' <<< "$out"; then
  pass "which: wrong key -> exit 1 with the reason"
else fail "which wrong key (rc=$rc): $out"; fi

# 5. no key in the environment: fails early, pointing at Step 1c.
out="$(env -u FANOUT_LABEL_KEY -u FANOUT_TOKEN bash "$S" which --registry "$EX" 4242 "$lbl" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'Step 1c' <<< "$out"; then
  pass "which: no key -> exit 1 with a pointer to Step 1c"
else fail "which no key (rc=$rc): $out"; fi

# 6. FANOUT_TOKEN is the fallback key, exactly as in the workflow.
out="$(env -u FANOUT_LABEL_KEY FANOUT_TOKEN=k1 bash "$S" which --registry "$EX" 4242 "$lbl" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(jq -r .repo <<< "$out")" = "your-org/service" ]; then
  pass "which: FANOUT_TOKEN works as the fallback key"
else fail "which token fallback (rc=$rc): $out"; fi

# 7. the recipe is one and the same line in the workflow and the script.
recipe='| openssl dgst -sha256 -hmac "$KEY" | awk '"'"'{print $NF}'"'"' | cut -c1-12'
if [ "$(grep -cF "$recipe" "$WF")" -ge 2 ] && [ "$(grep -cF "$recipe" "$S")" -ge 1 ] \
   && grep -qF "printf '%s:%s' \"\$GITHUB_RUN_ID\" \"\$1\" $recipe" "$WF" \
   && grep -qF "printf '%s:%s' \"\$1\" \"\$2\" $recipe" "$S"; then
  pass "label recipe is identical in github-kit-fanout.yml and fanout-registry.sh"
else fail "label recipe differs between the workflow and the script"; fi

echo
if [ "$failures" -ne 0 ]; then echo "$failures fan-out label test(s) failed"; exit 1; fi
echo "fan-out job labels behave as documented."
