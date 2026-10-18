#!/usr/bin/env bash
# One door to the github-kit fan-out registry: which repositories the fan-out maintains.
#
# The registry is NOT a file in this repository. github-kit is public; the list of repositories it
# maintains is not. It lives in the FANOUT_TARGETS repository Actions variable of github-kit, as the
# JSON described in .github/fanout-targets.example.json. A local working copy belongs at
# .github/fanout-targets.json, which is gitignored so it can never be committed by accident.
#
# Usage: scripts/fanout-registry.sh get           print the live registry
#        scripts/fanout-registry.sh check FILE    validate FILE against the schema, change nothing
#        scripts/fanout-registry.sh set FILE      validate FILE, then store it as FANOUT_TARGETS
#   GITHUB_KIT_REPO   the repo whose variable holds the registry (default: pzoli6/github-kit)
# Needs: jq; `get` and `set` also need gh signed in as an admin of that repo. Changing the registry
# is a human action: nothing in CI runs `set`, and agents must not run it on their own.
set -euo pipefail

KIT_REPO="${GITHUB_KIT_REPO:-pzoli6/github-kit}"
VAR_NAME="FANOUT_TARGETS"

usage() { sed -n '2,14p' "$0"; }
need() { command -v "$1" > /dev/null || { echo "error: $1 is not installed" >&2; exit 1; }; }

# Prints one line per schema violation; prints nothing for a valid registry.
schema_errors() {
  jq -r '
    def entry_errors:
      if type != "object" then ["entry is not an object"] else
        [ keys[] | select(. as $k | ["repo", "base", "install", "tier", "variables"] | index($k) | not)
          | "unknown key \"\(.)\"" ]
        + (if (.repo | type) != "string" then ["\"repo\" is required and must be a string"]
           elif (.repo | test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$") | not) then ["\"repo\" must be \"owner/name\""]
           else [] end)
        + (if .base != null and ((.base | type) != "string" or .base == "") then ["\"base\" must be a non-empty string"] else [] end)
        + (if .install != null and (.install | type) != "boolean" then ["\"install\" must be true or false"] else [] end)
        + (if .tier != null and (.tier != 1 and .tier != 2) then ["\"tier\" must be 1 or 2"] else [] end)
        + (if .variables != null and ((.variables | type) != "object" or ([.variables[] | type == "string"] | all | not))
           then ["\"variables\" must be an object whose values are strings"] else [] end)
      end;
    if type != "object" then "top level must be an object"
    elif (.targets | type) != "array" then "\"targets\" must be an array"
    elif (.targets | length) == 0 then "\"targets\" is empty"
    else
      ( [ keys[] | select(. != "targets" and . != "_comment") | "unknown top-level key \"\(.)\"" ]
        + [ .targets | to_entries[] | .key as $i | .value | entry_errors[] | "targets[\($i)]: \(.)" ]
        + ( [ .targets[] | .repo? | select(type == "string") ] | group_by(.) | map(select(length > 1) | .[0])
            | map("duplicate repo \"\(.)\"") )
      )[]
    end' "$1"
}

check_file() {
  local file="$1" errors
  [ -f "$file" ] || { echo "error: no such file: $file" >&2; return 1; }
  if ! jq -e . "$file" > /dev/null 2>&1; then
    echo "INVALID $file: not valid JSON" >&2
    return 1
  fi
  errors="$(schema_errors "$file")"
  if [ -n "$errors" ]; then
    echo "INVALID $file:" >&2
    sed 's/^/  - /' <<< "$errors" >&2
    return 1
  fi
  echo "OK      $file: $(jq '.targets | length' "$file") target(s), schema valid"
}

cmd="${1:-}"
[ "$#" -eq 0 ] || shift
case "$cmd" in
  get)
    need gh; need jq
    if ! value="$(gh variable get "$VAR_NAME" --repo "$KIT_REPO")"; then
      echo "error: could not read $VAR_NAME on $KIT_REPO: it does not exist yet (docs/OWNER_SETUP.md -> Step 1b), or gh is not signed in as an admin of $KIT_REPO." >&2
      exit 1
    fi
    jq . <<< "$value"
    ;;
  check)
    need jq
    [ "$#" -eq 1 ] || { usage >&2; exit 2; }
    check_file "$1"
    ;;
  set)
    need gh; need jq
    [ "$#" -eq 1 ] || { usage >&2; exit 2; }
    check_file "$1"
    gh variable set "$VAR_NAME" --repo "$KIT_REPO" --body "$(jq -c . "$1")"
    echo "SET     $VAR_NAME on $KIT_REPO from $1. Keep that file out of git (it is gitignored at .github/fanout-targets.json)."
    ;;
  -h|--help)
    usage
    ;;
  "")
    usage >&2; exit 2
    ;;
  *)
    echo "error: unknown command '$cmd'" >&2; usage >&2; exit 2
    ;;
esac
