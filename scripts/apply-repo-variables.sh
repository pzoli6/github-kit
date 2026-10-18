#!/usr/bin/env bash
# Apply the repository Actions variables declared in the fan-out registry to each target.
#
# The registry is the single place that says how each repo behaves; a target entry may carry
#   "variables": { "KIT_AUTOMERGE_ALLOW_NO_CHECKS": "true", ... }
# and this script makes each repo's Actions variables match. It only creates or updates the
# variables it is given and never deletes one (remove a variable with
# `gh variable delete NAME --repo OWNER/REPO`). Changing repository settings is a human action:
# nothing in CI runs this script, and agents must not run it on their own.
#
# The registry is not a file in this public repository: it is the FANOUT_TARGETS repository
# Actions variable of github-kit (scripts/fanout-registry.sh; schema in
# .github/fanout-targets.example.json). This script reads the live variable unless --registry
# points at a local copy, e.g. the one you are about to `fanout-registry.sh set`.
#
# Usage: scripts/apply-repo-variables.sh [--dry-run] [--repo OWNER/REPO] [--registry FILE]
#   --dry-run          show what would change, change nothing
#   --repo OWNER/REPO  limit to one registry entry
#   --registry FILE    read the registry from FILE instead of the FANOUT_TARGETS variable
#   GITHUB_KIT_REPO    the repo whose variable holds the registry (default: pzoli6/github-kit)
# Needs: gh (authenticated as an account with admin rights on github-kit and the targets), jq.
set -euo pipefail

KIT_REPO="${GITHUB_KIT_REPO:-pzoli6/github-kit}"
REGISTRY_FILE=""
DRY_RUN=0
ONLY=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --repo) [ "$#" -ge 2 ] || { echo "error: --repo needs OWNER/REPO" >&2; exit 2; }; ONLY="$2"; shift 2 ;;
    --registry) [ "$#" -ge 2 ] || { echo "error: --registry needs FILE" >&2; exit 2; }; REGISTRY_FILE="$2"; shift 2 ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

command -v gh > /dev/null || { echo "error: gh is not installed (https://cli.github.com)" >&2; exit 1; }
command -v jq > /dev/null || { echo "error: jq is not installed" >&2; exit 1; }

if [ -n "$REGISTRY_FILE" ]; then
  [ -f "$REGISTRY_FILE" ] || { echo "error: no such file: $REGISTRY_FILE" >&2; exit 1; }
  registry="$(cat "$REGISTRY_FILE")"
elif ! registry="$(gh variable get FANOUT_TARGETS --repo "$KIT_REPO")"; then
  echo "error: could not read the FANOUT_TARGETS variable of $KIT_REPO: it does not exist yet (docs/OWNER_SETUP.md -> Step 1b) or gh is not signed in as its admin. Or pass --registry FILE." >&2
  exit 1
fi
if ! jq -e '(.targets | type) == "array"' <<< "$registry" > /dev/null 2>&1; then
  echo "error: the registry is not JSON with a \"targets\" array (validate it with scripts/fanout-registry.sh check FILE)" >&2
  exit 1
fi

changed=0 failed=0
while IFS=$'\t' read -r repo name value; do
  [ -n "$repo" ] || continue
  [ -z "$ONLY" ] || [ "$repo" = "$ONLY" ] || continue
  if ! current="$(gh variable list --repo "$repo" --json name,value \
        --jq ".[] | select(.name == \"$name\") | .value" 2>/dev/null)"; then
    echo "FAILED  $repo: cannot read Actions variables (does your gh login have admin on it?)"
    failed=1; continue
  fi
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
done < <(jq -r '.targets[] | .repo as $r | (.variables // {}) | to_entries[] | [$r, .key, (.value | tostring)] | @tsv' <<< "$registry")

echo
if [ "$failed" -ne 0 ]; then echo "Some repositories could not be updated - see FAILED above."; exit 1; fi
if [ "$changed" -eq 0 ]; then echo "Every repository already matches the registry."
elif [ "$DRY_RUN" -eq 1 ]; then echo "Dry run: nothing changed. Re-run without --dry-run to apply."
else echo "Done."; fi
