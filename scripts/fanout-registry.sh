#!/usr/bin/env bash
# One door to the github-kit fan-out registry: which repositories the fan-out maintains.
#
# The registry is NOT a file in this repository. github-kit is public; the list of repositories it
# maintains is not. It lives in the FANOUT_TARGETS repository Actions variable of github-kit, as the
# JSON described in .github/fanout-targets.example.json. A local working copy belongs at
# .github/fanout-targets.json, which is gitignored so it can never be committed by accident.
#
# Usage: scripts/fanout-registry.sh get                   print the live registry
#        scripts/fanout-registry.sh check FILE            validate FILE against the schema, change nothing
#        scripts/fanout-registry.sh set FILE              validate FILE, then store it as FANOUT_TARGETS
#        scripts/fanout-registry.sh labels [--registry FILE] RUN_ID
#                                                         label -> repo for every entry, as a fan-out run
#                                                         with that run id (the number in its URL) named its jobs
#        scripts/fanout-registry.sh which  [--registry FILE] RUN_ID LABEL
#                                                         the registry entry behind one job label of that run
#   `labels` and `which` need the key the run used, in the environment: FANOUT_LABEL_KEY (the value
#   of the secret of that name, docs/OWNER_SETUP.md -> Step 1c), or FANOUT_TOKEN while no label
#   key is stored. --registry FILE reads a local copy instead of the live variable.
#   GITHUB_KIT_REPO   the repo whose variable holds the registry (default: pzoli6/github-kit)
# Needs: jq, openssl; `get`, `set` and (without --registry) `labels`/`which` also need gh signed in
# to an account with write access to that repo (any collaborator can read or write repository
# variables; the public cannot). Changing the registry is a human action: nothing in CI runs `set`,
# and agents must not run it on their own.
set -euo pipefail

KIT_REPO="${GITHUB_KIT_REPO:-pzoli6/github-kit}"
VAR_NAME="FANOUT_TARGETS"
REGISTRY_FILE=""

usage() { sed -n '2,24p' "$0"; }
need() { command -v "$1" > /dev/null || { echo "error: $1 is not installed" >&2; exit 1; }; }

# The job label of registry entry $2 in fan-out run $1, keyed with $KEY. Must stay identical to
# label_for() in .github/workflows/github-kit-fanout.yml (the doctor checks the recipe).
label_for() { printf '%s:%s' "$1" "$2" | openssl dgst -sha256 -hmac "$KEY" | awk '{print $NF}' | cut -c1-12; }

# Sets $KEY from the environment, or fails with the reason.
load_key() {
  if [ -n "${FANOUT_LABEL_KEY:-}" ]; then KEY="$FANOUT_LABEL_KEY"
  elif [ -n "${FANOUT_TOKEN:-}" ]; then KEY="$FANOUT_TOKEN"
  else
    echo "error: a job label can only be resolved with the key the run used. Export FANOUT_LABEL_KEY (the value stored as that secret on $KIT_REPO; docs/OWNER_SETUP.md -> Step 1c), or FANOUT_TOKEN while no label key is stored." >&2
    return 1
  fi
}

# Sets $registry from --registry FILE or the live variable, or fails with the reason.
load_registry() {
  if [ -n "$REGISTRY_FILE" ]; then
    [ -f "$REGISTRY_FILE" ] || { echo "error: no such file: $REGISTRY_FILE" >&2; return 1; }
    registry="$(< "$REGISTRY_FILE")"
  else
    need gh
    if ! registry="$(gh variable get "$VAR_NAME" --repo "$KIT_REPO")"; then
      echo "error: could not read $VAR_NAME on $KIT_REPO: it does not exist yet (docs/OWNER_SETUP.md -> Step 1b), or gh is not signed in to an account with access to $KIT_REPO." >&2
      return 1
    fi
  fi
  if ! jq -e '(.targets | type) == "array"' <<< "$registry" > /dev/null 2>&1; then
    echo "error: the registry is not JSON with a \"targets\" array (validate a file with: $0 check FILE)" >&2
    return 1
  fi
}

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
# `labels` and `which` take --registry FILE before their positional arguments.
while [ "$#" -gt 0 ] && [ "$1" = "--registry" ]; do
  [ "$#" -ge 2 ] || { echo "error: --registry needs FILE" >&2; exit 2; }
  REGISTRY_FILE="$2"; shift 2
done
case "$cmd" in
  get)
    need gh; need jq
    load_registry || exit 1
    jq . <<< "$registry"
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
    echo "NEXT    a stored registry triggers nothing by itself. Run the fan-out now, or wait for Monday's cron:"
    echo "          gh workflow run github-kit-fanout.yml --repo $KIT_REPO                   # every target"
    echo "          gh workflow run github-kit-fanout.yml --repo $KIT_REPO -f only_repo=N    # one entry, N = its 0-based index"
    ;;
  labels)
    need jq; need openssl
    [ "$#" -eq 1 ] && [[ "$1" =~ ^[0-9]+$ ]] || { usage >&2; exit 2; }
    load_key || exit 1
    load_registry || exit 1
    run_id="$1"
    total="$(jq '.targets | length' <<< "$registry")"
    for ((i = 0; i < total; i++)); do
      printf '%s  %s\n' "$(label_for "$run_id" "$i")" "$(jq -r ".targets[$i].repo" <<< "$registry")"
    done | sort
    ;;
  which)
    need jq; need openssl
    [ "$#" -eq 2 ] && [[ "$1" =~ ^[0-9]+$ ]] || { usage >&2; exit 2; }
    load_key || exit 1
    load_registry || exit 1
    run_id="$1" label="$2"
    total="$(jq '.targets | length' <<< "$registry")"
    for ((i = 0; i < total; i++)); do
      if [ "$(label_for "$run_id" "$i")" = "$label" ]; then
        jq -c --argjson i "$i" '.targets[$i] + {index: $i}' <<< "$registry"
        exit 0
      fi
    done
    echo "error: no entry of this registry carries label $label in run $run_id: the key in the environment differs from the one the run used, or the registry changed since that run." >&2
    exit 1
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
