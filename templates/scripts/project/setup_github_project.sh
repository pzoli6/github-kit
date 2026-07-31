#!/usr/bin/env bash
# One-time (idempotent) GitHub Project (v2) bootstrap for the github-kit workflow.
#
# Ensures the Project every other script in this directory writes to actually exists and has
# every field and Status option the kit's checkpoints use — so sync_project_fields.sh never
# fails on a missing field, and no card ever has a blank the board can't even hold.
#
#   scripts/project/setup_github_project.sh                # report what's missing, change nothing
#   scripts/project/setup_github_project.sh --apply        # create/fix whatever the report listed
#
# Options:
#   --owner <login>     Project owner (user or org). Default: AGENT_PROJECT_OWNER from
#                       docs/ai/PROJECT_CONFIG.env, else the repo owner.
#   --number <n>        Adopt an existing Project by number. Default: AGENT_PROJECT_NUMBER from
#                       the env file. "TBD"/empty means: find by title, create if absent.
#   --title <name>      Title used to find/create the Project when no number is configured.
#                       Default: AGENT_PROJECT_NAME, else "<repo-name> Agent Board".
#   --repo <owner/name> Repository to link to the Project. Default: the current repo.
#   --apply             Actually create/modify. Without it this is a read-only doctor run.
#   --write-config      With --apply: write the resolved owner/number/name back into
#                       docs/ai/PROJECT_CONFIG.env (created from .env.example if absent).
#
# Exit codes: 0 = board fully ready (or --apply just made it so); 1 = gaps found in doctor
# mode, or an operation failed; 2 = usage/config error.
#
# Idempotent by construction: everything is "ensure", nothing is "reset". Re-running against a
# healthy board changes nothing and exits 0 — which is what makes it safe to run from a
# workflow on every trigger. It NEVER renames or removes an existing field or Status option,
# and never touches item values: on a board that spells a status differently (a default GitHub
# board ships "In progress"), the kit spelling is ADDED alongside rather than renamed —
# renaming rewrites the option list and can drop values from existing cards, which violates
# this repo's non-destructive-scripts rule.
#
# Needs: gh, authenticated with the 'project' scope (gh auth refresh -s project, or GH_TOKEN
# set to a PAT that has it — the same AGENT_PROJECT_TOKEN Project Sync uses). The default
# GITHUB_TOKEN in Actions cannot touch Projects (v2).
set -euo pipefail

# --- the kit's board contract ---------------------------------------------------------------
# Single source of truth for what the board must hold: the text fields the checkpoint script
# (sync_project_fields.sh) and the create_* scripts write, and the Status values the
# checkpoints set. If a checkpoint gains a field or status, add it here and re-run.
REQUIRED_TEXT_FIELDS=(
  "Agent" "Area" "Risk" "Environment"
  "Base Branch" "Branch" "PR URL"
  "Validation" "Handoff" "Last Agent Update" "Agent Run"
)
# name|color pairs; color must be a GitHub single-select option color enum value
REQUIRED_STATUSES=(
  "Backlog|GRAY" "Ready|BLUE" "Plan Review|PURPLE" "In Progress|YELLOW" "Blocked|RED"
  "In Review|ORANGE" "Changes Requested|PINK" "Done|GREEN" "Cancelled|GRAY"
)

usage() {
  sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

APPLY=0
WRITE_CONFIG=0
OWNER=""
NUMBER=""
TITLE=""
REPO=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --owner)  OWNER="${2:?--owner needs a value}"; shift 2 ;;
    --number) NUMBER="${2:?--number needs a value}"; shift 2 ;;
    --title)  TITLE="${2:?--title needs a value}"; shift 2 ;;
    --repo)   REPO="${2:?--repo needs a value}"; shift 2 ;;
    --apply)  APPLY=1; shift ;;
    --write-config) WRITE_CONFIG=1; shift ;;
    -h|--help) usage ;;
    *) echo "error: unknown argument '$1'" >&2; usage ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
# PROJECT_CONFIG.env is gitignored, so a linked worktree doesn't have it — fall back to the
# main checkout's copy (the same anchor publish_agent_branch.sh uses). Without this, an agent
# working in a worktree would silently treat the Project as unconfigured and stop updating the
# board, while the same command from the main checkout works.
ENV_FILE="$REPO_ROOT/docs/ai/PROJECT_CONFIG.env"
if [ ! -f "$ENV_FILE" ]; then
  GIT_COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  [ -n "$GIT_COMMON_DIR" ] && ENV_FILE="$(dirname "$GIT_COMMON_DIR")/docs/ai/PROJECT_CONFIG.env"
fi
# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

# jq is deliberately NOT required: every JSON read here goes through gh --jq, which uses gh's
# built-in engine. Git Bash on Windows ships no jq, and demanding one made these scripts
# unusable there. Values that could contain anything (field/option names, descriptions) travel
# base64-encoded through the shell so no content can break the parsing.
command -v gh >/dev/null 2>&1 || { echo "error: 'gh' is required but not found on PATH." >&2; exit 2; }

# Escape a string for inlining into a GraphQL document.
gql_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'; }

[ -n "$REPO" ] || REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
[ -n "$REPO" ] || { echo "error: could not determine the repository — pass --repo <owner/name>." >&2; exit 2; }

[ -n "$OWNER" ] || OWNER="${AGENT_PROJECT_OWNER:-}"
[ -n "$OWNER" ] || OWNER="${REPO%%/*}"
[ -n "$NUMBER" ] || NUMBER="${AGENT_PROJECT_NUMBER:-}"
[ "$NUMBER" != "TBD" ] || NUMBER=""
[ -n "$TITLE" ] || TITLE="${AGENT_PROJECT_NAME:-}"
[ "$TITLE" != "TBD" ] || TITLE=""
[ -n "$TITLE" ] || TITLE="${REPO#*/} Agent Board"

GAPS=0
CHANGED=0
note() { printf '%s\n' "$*"; }
gap()  { GAPS=$((GAPS+1)); printf 'MISSING %s\n' "$*"; }
did()  { CHANGED=$((CHANGED+1)); printf 'CREATED %s\n' "$*"; }

# Fail early, and helpfully, if the token can't see Projects at all — every later call would
# otherwise produce the same confusing "not resolvable" error.
if ! gh project list --owner "$OWNER" --limit 1 >/dev/null 2>&1; then
  echo "error: cannot list Projects for owner '$OWNER'." >&2
  echo "       The token needs the 'project' scope: run 'gh auth refresh -s project'," >&2
  echo "       or set GH_TOKEN to a PAT that has it (the same AGENT_PROJECT_TOKEN Project Sync uses)." >&2
  exit 1
fi

# --- 1. resolve or create the Project -------------------------------------------------------
if [ -n "$NUMBER" ]; then
  title_now="$(gh project view "$NUMBER" --owner "$OWNER" --format json --jq .title 2>/dev/null || true)"
  if [ -z "$title_now" ]; then
    echo "error: Project #$NUMBER does not exist for owner '$OWNER' — it is configured but gone." >&2
    echo "       Clear AGENT_PROJECT_NUMBER (or pass no --number) to have one found by title or created." >&2
    exit 1
  fi
  TITLE="$title_now"
  note "OK      Project #$NUMBER ('$TITLE') exists for $OWNER"
else
  # No number configured: adopt a same-titled Project if one exists (a previous run created it
  # and the config write-back never landed), otherwise create it. Exact-title matching keeps
  # re-runs idempotent instead of minting a new board each time.
  NUMBER="$(TITLE="$TITLE" gh project list --owner "$OWNER" --format json --limit 100 \
    --jq '.projects[] | select(.title==env.TITLE) | .number' | head -n1)"
  if [ -n "$NUMBER" ]; then
    note "OK      Project '$TITLE' already exists as #$NUMBER (adopting it)"
  elif [ "$APPLY" -eq 1 ]; then
    NUMBER="$(gh project create --owner "$OWNER" --title "$TITLE" --format json --jq .number)"
    [ -n "$NUMBER" ] || { echo "error: 'gh project create' returned no project number." >&2; exit 1; }
    did "Project '$TITLE' as #$NUMBER for $OWNER"
  else
    gap "Project: no number configured and no Project titled '$TITLE' exists for $OWNER (would create)"
  fi
fi

if [ -z "$NUMBER" ]; then
  # Doctor mode with nothing to inspect: report the remaining contract as pending and stop.
  for f in "${REQUIRED_TEXT_FIELDS[@]}"; do gap "field '$f' (TEXT) — pending Project creation"; done
  for entry in "${REQUIRED_STATUSES[@]}"; do gap "Status option '${entry%%|*}' — pending Project creation"; done
  gap "link to repository $REPO — pending Project creation"
  printf '\n%d gap(s). Run again with --apply to create all of the above.\n' "$GAPS"
  exit 1
fi

project_id="$(gh project view "$NUMBER" --owner "$OWNER" --format json --jq '.id')"
[ -n "$project_id" ] && [ "$project_id" != "null" ] || { echo "error: could not resolve Project #$NUMBER for $OWNER." >&2; exit 1; }

# --- 2. ensure every text field exists ------------------------------------------------------
# One fetch; names travel base64-encoded so spaces or any other content survive the shell.
fields_tsv="$(gh project field-list "$NUMBER" --owner "$OWNER" --format json --limit 100 \
  --jq '.fields[] | [(.name|@base64), .type, .id] | @tsv')"

field_type_of() { # $1 = field name -> echoes type, empty if absent
  local want="$1" b64 name type id
  while IFS=$'\t' read -r b64 type id; do
    [ -n "$b64" ] || continue
    name="$(printf '%s' "$b64" | base64 -d)"
    if [ "$name" = "$want" ]; then printf '%s' "$type"; return 0; fi
  done <<< "$fields_tsv"
  return 0
}

for field in "${REQUIRED_TEXT_FIELDS[@]}"; do
  existing_type="$(field_type_of "$field")"
  if [ -n "$existing_type" ]; then
    if [ "$existing_type" = "ProjectV2Field" ]; then
      note "OK      field '$field' exists"
    else
      # Wrong type is reported, never "fixed": converting a field would destroy its values.
      note "WARN    field '$field' exists but is $existing_type, not a text field — the kit's scripts write it as text; review it on the board"
    fi
  elif [ "$APPLY" -eq 1 ]; then
    gh project field-create "$NUMBER" --owner "$OWNER" --name "$field" --data-type TEXT >/dev/null
    did "field '$field' (TEXT)"
  else
    gap "field '$field' (TEXT)"
  fi
done

# --- 3. ensure every kit Status option exists -----------------------------------------------
# The Status field is built into every Project; only its OPTIONS vary. Existing options are
# never renamed or removed (see header) — missing kit statuses are APPENDED via GraphQL,
# because gh project field-create cannot edit the built-in field and no per-option add
# mutation exists: updateProjectV2Field replaces the whole option list, so every existing
# option is re-sent verbatim with the new ones appended.
status_field_id=""
while IFS=$'\t' read -r b64 type id; do
  [ -n "$b64" ] || continue
  if [ "$(printf '%s' "$b64" | base64 -d)" = "Status" ]; then status_field_id="$id"; break; fi
done <<< "$fields_tsv"
if [ -z "$status_field_id" ]; then
  echo "error: Project #$NUMBER has no 'Status' field — that field is built into every GitHub Project, so this Project is in an unexpected state." >&2
  exit 1
fi

options_tsv="$(gh api graphql \
  -f query='query($id:ID!){ node(id:$id){ ... on ProjectV2SingleSelectField { options { name color description } } } }' \
  -F id="$status_field_id" \
  --jq '.data.node.options[] | [(.name|@base64), .color, ((.description // "")|@base64)] | @tsv')"

status_exists() { # $1 = wanted name, $2 = "exact"|"fold" -> echoes matched name, empty if none
  local want="$1" mode="$2" b64 color desc name
  while IFS=$'\t' read -r b64 color desc; do
    [ -n "$b64" ] || continue
    name="$(printf '%s' "$b64" | base64 -d)"
    if [ "$mode" = "exact" ] && [ "$name" = "$want" ]; then printf '%s' "$name"; return 0; fi
    if [ "$mode" = "fold" ] && [ "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')" ]; then
      printf '%s' "$name"; return 0
    fi
  done <<< "$options_tsv"
  return 0
}

missing_statuses=()
for entry in "${REQUIRED_STATUSES[@]}"; do
  s="${entry%%|*}"
  if [ -n "$(status_exists "$s" exact)" ]; then
    note "OK      Status option '$s' exists"
    continue
  fi
  # The checkpoint scripts match case-sensitively, so "In progress" on a default board does NOT
  # satisfy "In Progress" — the kit spelling is added alongside and the near-miss called out, so
  # a human can consolidate on the board later (existing cards keep their value untouched).
  near="$(status_exists "$s" fold)"
  [ -z "$near" ] || note "WARN    Status option '$s' missing but '$near' exists — adding the kit spelling alongside; consider consolidating on the board"
  if [ "$APPLY" -eq 1 ]; then
    missing_statuses+=("$entry")
  else
    gap "Status option '$s'"
  fi
done

if [ "$APPLY" -eq 1 ] && [ "${#missing_statuses[@]}" -gt 0 ]; then
  # Rebuild the full option list: every existing option verbatim, then the missing kit ones.
  # Node ids are API-safe by construction; names/descriptions are GraphQL-escaped.
  options_gql=""
  sep=""
  while IFS=$'\t' read -r b64 color desc_b64; do
    [ -n "$b64" ] || continue
    name="$(printf '%s' "$b64" | base64 -d)"
    desc="$(printf '%s' "$desc_b64" | base64 -d)"
    case "$color" in GRAY|BLUE|GREEN|YELLOW|ORANGE|RED|PINK|PURPLE) : ;; *) color="GRAY" ;; esac
    options_gql="$options_gql$sep{name:\"$(gql_escape "$name")\",color:$color,description:\"$(gql_escape "$desc")\"}"
    sep=","
  done <<< "$options_tsv"
  for entry in "${missing_statuses[@]}"; do
    s="${entry%%|*}"; c="${entry##*|}"
    options_gql="$options_gql$sep{name:\"$(gql_escape "$s")\",color:$c,description:\"\"}"
    sep=","
  done
  gh api graphql -f query="mutation {
    updateProjectV2Field(input:{
      projectId:\"$project_id\", fieldId:\"$status_field_id\",
      singleSelectOptions:[$options_gql]
    }) { projectV2Field { ... on ProjectV2SingleSelectField { id } } }
  }" >/dev/null
  for entry in "${missing_statuses[@]}"; do did "Status option '${entry%%|*}'"; done
fi

# --- 4. ensure the Project is linked to the repository --------------------------------------
repo_owner="${REPO%%/*}"
repo_name="${REPO#*/}"
linked="$(gh api graphql \
  -f query='query($o:String!,$n:String!){ repository(owner:$o,name:$n){ projectsV2(first:100){ nodes { number } } } }' \
  -F o="$repo_owner" -F n="$repo_name" \
  --jq ".data.repository.projectsV2.nodes[] | select(.number == $NUMBER) | .number" 2>/dev/null || true)"
if [ -n "$linked" ]; then
  note "OK      Project #$NUMBER is linked to $REPO"
elif [ "$APPLY" -eq 1 ]; then
  gh project link "$NUMBER" --owner "$OWNER" --repo "$REPO" >/dev/null
  did "link: Project #$NUMBER ↔ $REPO"
else
  gap "link: Project #$NUMBER is not linked to repository $REPO"
fi

# --- 5. optionally write the result back into the local config ------------------------------
if [ "$APPLY" -eq 1 ] && [ "$WRITE_CONFIG" -eq 1 ]; then
  if [ ! -f "$ENV_FILE" ] && [ -f "$ENV_FILE.example" ]; then
    cp "$ENV_FILE.example" "$ENV_FILE"
    note "created docs/ai/PROJECT_CONFIG.env from .env.example"
  fi
  if [ -f "$ENV_FILE" ]; then
    for kv in "AGENT_PROJECT_OWNER=$OWNER" "AGENT_PROJECT_NUMBER=$NUMBER" "AGENT_PROJECT_NAME=$TITLE"; do
      k="${kv%%=*}"; v="${kv#*=}"
      if grep -q "^$k=" "$ENV_FILE"; then
        # sed -i differs between GNU and BSD; a temp-file rewrite works on both.
        tmp="$(mktemp)"; sed "s|^$k=.*|$k=\"$v\"|" "$ENV_FILE" > "$tmp" && mv "$tmp" "$ENV_FILE"
      else
        printf '%s="%s"\n' "$k" "$v" >> "$ENV_FILE"
      fi
    done
    note "wrote owner=$OWNER number=$NUMBER name='$TITLE' into docs/ai/PROJECT_CONFIG.env"
    note "REMINDER: docs/ai/PROJECT_CONFIG.md's table and .github/workflows/project-sync.yml / pr-policy.yml carry these values too — update them together (the project-setup workflow opens that PR for you)."
  fi
fi

# --- summary --------------------------------------------------------------------------------
# In GitHub Actions, hand the resolved coordinates to later steps (the project-setup workflow
# uses them to open the config PR that pins the number into the caller files).
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    printf 'project_owner=%s\n' "$OWNER"
    printf 'project_number=%s\n' "$NUMBER"
    printf 'project_title=%s\n' "$TITLE"
  } >> "$GITHUB_OUTPUT"
fi

echo
if [ "$APPLY" -eq 1 ]; then
  printf 'Project #%s (%s) ready for %s — %d change(s) made.\n' "$NUMBER" "$OWNER" "$REPO" "$CHANGED"
  exit 0
elif [ "$GAPS" -eq 0 ]; then
  printf 'Project #%s (%s) is fully set up for %s — nothing to do.\n' "$NUMBER" "$OWNER" "$REPO"
  exit 0
else
  printf '%d gap(s). Run again with --apply to fix all of the above.\n' "$GAPS"
  exit 1
fi
