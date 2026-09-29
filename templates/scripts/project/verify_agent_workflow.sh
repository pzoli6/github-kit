#!/usr/bin/env bash
# Verify this repo has the files and key phrases the github-kit agent workflow requires.
# The required files and phrases come from docs/ai/KIT_MANIFEST.tsv (installed by github-kit);
# .github/workflows/reusable-agent-workflow-verify.yml runs this same script in CI.
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT" || exit 1
MANIFEST="docs/ai/KIT_MANIFEST.tsv"

REQUIRE_CLAUDE="${REQUIRE_CLAUDE:-true}"
REQUIRE_CURSOR="${REQUIRE_CURSOR:-true}"
REQUIRE_SKILLS="${REQUIRE_SKILLS:-true}"
REQUIRE_GEMINI="${REQUIRE_GEMINI:-false}"
# REQUIRE_COPILOT is still accepted (older callers pass it) but no longer does anything: the kit
# stopped shipping the Copilot adapter file.

missing=0

check_file() {
  local f="$1"
  if [ ! -e "$f" ]; then
    echo "MISSING file: $f"
    missing=1
  else
    echo "OK      file: $f"
  fi
}

check_phrase() {
  local phrase="$1"
  if grep -RFq \
      --include='*.md' --include='*.yml' --include='*.yaml' \
      --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build \
      -- "$phrase" . 2>/dev/null; then
    echo "OK      phrase: $phrase"
  else
    echo "MISSING phrase: $phrase"
    missing=1
  fi
}

if [ ! -f "$MANIFEST" ]; then
  echo "MISSING file: $MANIFEST (run /github_kit_update or scripts/update-github-kit.sh to install it)"
  echo
  echo "Agent workflow verification FAILED — see MISSING items above."
  exit 1
fi

# Each file row names a group; REQUIRE_<GROUP>=false switches a whole group off. "core" is always
# required and "-" never is.
group_required() {
  case "$1" in
    core) return 0 ;;
    claude) [ "$REQUIRE_CLAUDE" = "true" ] ;;
    cursor) [ "$REQUIRE_CURSOR" = "true" ] ;;
    skills) [ "$REQUIRE_SKILLS" = "true" ] ;;
    gemini) [ "$REQUIRE_GEMINI" = "true" ] ;;
    *) return 1 ;;
  esac
}

# A Windows checkout may hand the manifest over with CRLF line ends; strip the \r from the last
# field so "core\r" is still read as "core".
while IFS=$'\t' read -r kind path _mode group; do
  group="${group%$'\r'}"
  [ "$kind" = "file" ] || continue
  if group_required "$group"; then
    check_file "$path"
  fi
done < "$MANIFEST"

while IFS=$'\t' read -r kind phrase _rest; do
  phrase="${phrase%$'\r'}"
  [ "$kind" = "phrase" ] || continue
  check_phrase "$phrase"
done < "$MANIFEST"

# --- github-kit ref: this repo may auto-track @main (default) or deliberately pin via
# docs/ai/PROJECT_CONFIG.md's "github-kit ref" key. Either is fine; what matters is that the
# caller workflows' uses: lines agree with whatever PROJECT_CONFIG.md says.

PROJECT_REF=""
if [ -f "docs/ai/PROJECT_CONFIG.md" ]; then
  if grep -Fq "github-kit ref" docs/ai/PROJECT_CONFIG.md; then
    echo "OK      docs/ai/PROJECT_CONFIG.md documents github-kit ref"
  else
    echo "MISSING docs/ai/PROJECT_CONFIG.md key: github-kit ref"
    missing=1
  fi
  PROJECT_REF="$(grep -F 'github-kit ref' docs/ai/PROJECT_CONFIG.md | head -1 | sed -E 's/.*`([^`]+)`.*/\1/')"
fi
EXPECTED_REF="${PROJECT_REF:-main}"

ref_ok=1
# Callers the updater refreshes (mode "workflow") always carry the current ref; pr-policy.yml is
# created once but is checked too, since a pinned repo must repoint it by hand.
callers="$(awk -F'\t' '{ sub(/\r$/, "") } $1 == "file" && $3 == "workflow" { print $2 }' "$MANIFEST")"
for wf in $callers .github/workflows/pr-policy.yml; do
  [ -e "$wf" ] || continue
  if ! grep -Eq "uses: pzoli6/github-kit/.*@${EXPECTED_REF}([[:space:]]|\$)" "$wf"; then
    echo "MISMATCH workflow ref in $wf (expected @$EXPECTED_REF per docs/ai/PROJECT_CONFIG.md \"github-kit ref\")"
    ref_ok=0
  fi
done
if [ "$ref_ok" -eq 1 ]; then
  echo "OK      caller workflows reference @$EXPECTED_REF"
else
  missing=1
fi

echo
if [ "$missing" -ne 0 ]; then
  echo "Agent workflow verification FAILED — see MISSING items above."
  exit 1
fi

echo "Agent workflow verification passed."
