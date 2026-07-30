#!/usr/bin/env bash
# Post or update a sticky, marker-tagged handoff comment directly on the PR, so any agent or human
# looking at the PR sees current state without having to open docs/ai/handoffs/issue-<n>.md in the
# repo. Idempotent: re-running with the same PR finds its own prior comment (by marker) and edits
# it in place via updateIssueComment, instead of piling up a new comment every time.
set -euo pipefail

MARKER="<!-- github-kit:handoff -->"

usage() {
  cat >&2 <<'EOF'
Usage: post_handoff_comment.sh --pr <pr-number-or-url> (--file <path> | --body <text>) [--agent <name>]

Exactly one of --file or --body is required. --file reads the handoff content from a file
(e.g. docs/ai/handoffs/issue-<n>.md); --body takes the content inline.
EOF
  exit 1
}

PR=""
FILE=""
BODY_TEXT=""
AGENT_NAME=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pr) PR="${2:-}"; shift 2 ;;
    --file) FILE="${2:-}"; shift 2 ;;
    --body) BODY_TEXT="${2:-}"; shift 2 ;;
    --agent) AGENT_NAME="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

[ -n "$PR" ] || usage
if [ -n "$FILE" ] && [ -n "$BODY_TEXT" ]; then
  echo "error: pass only one of --file or --body, not both." >&2
  exit 1
fi
if [ -z "$FILE" ] && [ -z "$BODY_TEXT" ]; then
  usage
fi

# jq is deliberately NOT required: every JSON read here goes through gh --jq, which uses
# gh's built-in engine. Git Bash on Windows ships no jq, and demanding one made these scripts
# unusable there.
for bin in gh; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: '$bin' is required but not found on PATH." >&2; exit 1; }
done

gh auth status >/dev/null 2>&1 || { echo "error: gh is not authenticated. Run 'gh auth login'." >&2; exit 1; }

if [ -n "$FILE" ]; then
  [ -f "$FILE" ] || { echo "error: file not found: $FILE" >&2; exit 1; }
  CONTENT="$(cat "$FILE")"
else
  CONTENT="$BODY_TEXT"
fi

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
COMMENT_BODY="$MARKER
**Handoff** — updated $TIMESTAMP${AGENT_NAME:+ by $AGENT_NAME}

$CONTENT"

pr_node_id="$(gh pr view "$PR" --json id --jq '.id')"
[ -n "$pr_node_id" ] && [ "$pr_node_id" != "null" ] || { echo "error: could not resolve PR '$PR'." >&2; exit 1; }

# gh's --jq uses gh's built-in jq engine, so no external `jq` binary is needed (Git Bash on
# Windows ships none). It has no --arg, so shell values reach the expression through env.
existing_id="$(MARKER="$MARKER" gh pr view "$PR" --json comments --jq '[.comments[] | select(.body | startswith(env.MARKER))] | .[-1].id // empty')"

if [ -n "$existing_id" ]; then
  gh api graphql -f query='
    mutation($id: ID!, $body: String!) {
      updateIssueComment(input: { id: $id, body: $body }) {
        issueComment { id url }
      }
    }' -f id="$existing_id" -f body="$COMMENT_BODY" >/dev/null
  echo "Updated existing handoff comment on PR $PR."
else
  gh api graphql -f query='
    mutation($id: ID!, $body: String!) {
      addComment(input: { subjectId: $id, body: $body }) {
        commentEdge { node { id url } }
      }
    }' -f id="$pr_node_id" -f body="$COMMENT_BODY" >/dev/null
  echo "Posted new handoff comment on PR $PR."
fi
