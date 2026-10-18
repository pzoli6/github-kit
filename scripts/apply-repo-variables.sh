#!/usr/bin/env bash
# Apply the repository Actions variables declared in .github/fanout-targets.json to each target.
#
# The registry is the single place that says how each repo behaves; a target entry may carry
#   "variables": { "KIT_AUTOMERGE_ALLOW_NO_CHECKS": "true", ... }
# and this script makes each repo's Actions variables match. It only creates or updates the
# variables it is given and never deletes one (remove a variable with
# `gh variable delete NAME --repo OWNER/REPO`). Changing repository settings is a human action:
# nothing in CI runs this script, and agents must not run it on their own.
#
# Usage: scripts/apply-repo-variables.sh [--dry-run] [--repo OWNER/REPO]
#   --dry-run          show what would change, change nothing
#   --repo OWNER/REPO  limit to one registry entry
# Needs: gh (authenticated as an account with admin rights on the targets), jq.
# Windows (Git Bash): install jq with `winget install jqlang.jq`. A native jq.exe ends its output
# lines with CRLF; every value read here is stripped of that CR before it is compared or set.
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="$KIT_ROOT/.github/fanout-targets.json"
DRY_RUN=0
ONLY=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --repo) [ "$#" -ge 2 ] || { echo "error: --repo needs OWNER/REPO" >&2; exit 2; }; ONLY="$2"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

command -v gh > /dev/null || { echo "error: gh is not installed (https://cli.github.com)" >&2; exit 1; }
command -v jq > /dev/null || {
  echo "error: jq is not installed (Windows: winget install jqlang.jq, then open a new shell;" \
       "macOS: brew install jq; Debian/Ubuntu: sudo apt-get install jq)" >&2
  exit 1
}

changed=0 failed=0
while IFS=$'\t' read -r repo name value; do
  # A native Windows jq.exe (or gh.exe) writes CRLF; a stray CR would be set as part of the value.
  repo="${repo%$'\r'}" name="${name%$'\r'}" value="${value%$'\r'}"
  [ -n "$repo" ] || continue
  [ -z "$ONLY" ] || [ "$repo" = "$ONLY" ] || continue
  if ! current="$(gh variable list --repo "$repo" --json name,value \
        --jq ".[] | select(.name == \"$name\") | .value" 2>/dev/null)"; then
    echo "FAILED  $repo: cannot read Actions variables (does your gh login have admin on it?)"
    failed=1; continue
  fi
  current="${current%$'\r'}"
  if [ "$current" = "$value" ]; then
    echo "OK      $repo: $name=$value"
    continue
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "WOULD   $repo: $name=${current:-<unset>} -> $value"
    changed=1
  elif gh variable set "$name" --repo "$repo" --body "$value" > /dev/null; then
    echo "SET     $repo: $name=${current:-<unset>} -> $value"
    changed=1
  else
    echo "FAILED  $repo: could not set $name"
    failed=1
  fi
done < <(jq -r '.targets[] | .repo as $r | (.variables // {}) | to_entries[] | [$r, .key, (.value | tostring)] | @tsv' "$REGISTRY")

echo
if [ "$failed" -ne 0 ]; then echo "Some repositories could not be updated - see FAILED above."; exit 1; fi
if [ "$changed" -eq 0 ]; then echo "Every repository already matches the registry."
elif [ "$DRY_RUN" -eq 1 ]; then echo "Dry run: nothing changed. Re-run without --dry-run to apply."
else echo "Done."; fi
