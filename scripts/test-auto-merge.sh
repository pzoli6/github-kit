#!/usr/bin/env bash
# Behaviour test for .github/workflows/reusable-auto-merge.yml ("Evaluate and merge" step).
#
# Runs the step's real bash script against a fake `gh` that serves one scenario's API state from a
# JSON file and records every write (merge, comment post, comment edit). Asserts that a ready PR is
# never held silently: each hold reason lands in exactly one sticky comment, edited in place only
# when its text changes, closed out on merge; and that the merge gates themselves still behave.
#
# Usage: scripts/test-auto-merge.sh    (needs bash, jq, python3 with PyYAML)
set -uo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS    $1"; }
fail() { echo "FAIL    $1"; failures=$((failures + 1)); }

# The step under test, extracted verbatim from the reusable workflow.
python3 - "$KIT_ROOT/.github/workflows/reusable-auto-merge.yml" "$WORK/step.sh" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
steps = wf["jobs"]["auto-merge"]["steps"]
run = next(s["run"] for s in steps if s.get("name") == "Evaluate and merge")
open(sys.argv[2], "w").write(run)
PY

# Fake gh: `gh api [-X METHOD] PATH [-f k=v]... [--paginate] [--jq EXPR]` against $GH_STATE.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'PY'
#!/usr/bin/env python3
import json, os, re, subprocess, sys
args = sys.argv[1:]
assert args and args[0] == "api", args
args = args[1:]
method, path, fields, jq = "GET", None, {}, None
i = 0
while i < len(args):
    a = args[i]
    if a == "-X": method = args[i + 1]; i += 2; continue
    if a == "-f": k, v = args[i + 1].split("=", 1); fields[k] = v; i += 2; continue
    if a == "--jq": jq = args[i + 1]; i += 2; continue
    if a == "--paginate": i += 1; continue
    path = a; i += 1
st_path = os.environ["GH_STATE"]
st = json.load(open(st_path))
path = path.split("?", 1)[0]
def out(obj):
    text = json.dumps(obj)
    if jq is not None:
        text = subprocess.run(["jq", "-r", jq], input=text, capture_output=True, text=True, check=True).stdout
    sys.stdout.write(text if text.endswith("\n") or jq is not None else text + "\n")
def save(): json.dump(st, open(st_path, "w"))
n = str(st["pr"]["number"])
if method == "GET" and re.fullmatch(r"repos/[^/]+/[^/]+/pulls/\d+", path): out(st["pr"])
elif re.search(r"/issues/\d+/timeline$", path): out(st.get("timeline", []))
elif re.search(r"/pulls/\d+/reviews$", path): out(st.get("reviews", []))
elif re.search(r"/actions/runs$", path): out({"workflow_runs": st.get("runs", [])})
elif re.search(r"/check-runs$", path): out({"check_runs": st.get("checks", [])})
elif re.search(r"/commits/[^/]+/status$", path): out(st.get("status", {"state": "pending", "total_count": 0, "statuses": []}))
elif method == "PUT" and path.endswith("/merge"):
    st["log"].append(["merge", fields.get("sha")]); save()
    r = st.get("merge_response", "ok")
    if r == "ok": out({"merged": True, "message": "Pull Request successfully merged"})
    else: sys.stderr.write(r); sys.exit(1)
elif method == "GET" and re.search(r"/pulls$", path): out([])
elif method == "DELETE": st["log"].append(["delete", path]); save()
elif method == "GET" and re.search(r"/issues/\d+/comments$", path): out(st["comments"])
elif method == "GET" and re.search(r"/issues/comments/\d+$", path):
    cid = int(path.rsplit("/", 1)[1]); out(next(c for c in st["comments"] if c["id"] == cid))
elif method == "POST" and path.endswith("/comments"):
    cid = 1000 + len(st["comments"]); st["comments"].append({"id": cid, "body": fields["body"]})
    st["log"].append(["post", cid]); save(); out({"id": cid})
elif method == "PATCH" and re.search(r"/issues/comments/\d+$", path):
    cid = int(path.rsplit("/", 1)[1])
    for c in st["comments"]:
        if c["id"] == cid: c["body"] = fields["body"]
    st["log"].append(["patch", cid]); save(); out({"id": cid})
else:
    sys.stderr.write("fake gh: unhandled %s %s\n" % (method, path)); sys.exit(1)
PY
chmod +x "$WORK/bin/gh"

SHA=0123456789abcdef0123456789abcdef01234567
# new_state <file> [jq filter applied to the base state]
new_state() {
  jq -n --arg sha "$SHA" '{
    pr: {number: 7, state: "open", draft: false, mergeable: true, mergeable_state: "clean",
         head: {sha: $sha, ref: "agent/x", repo: {full_name: "o/r"}},
         base: {repo: {full_name: "o/r", default_branch: "main"}}, labels: []},
    timeline: [{event: "ready_for_review", actor: {login: "owner", type: "User"}}],
    reviews: [], runs: [], checks: [],
    status: {state: "pending", total_count: 0, statuses: []},
    comments: [], log: []
  }' | jq "${2:-.}" > "$1"
}
# evaluate <state file> [VAR=value ...]  runs the step once; prints its log to <file>.out
evaluate() {
  local state="$1"; shift
  env PATH="$WORK/bin:$PATH" GH_STATE="$state" \
    GITHUB_REPOSITORY=o/r GITHUB_WORKFLOW_REF="o/r/.github/workflows/auto-merge.yml@refs/heads/main" \
    GITHUB_RUN_ID=99 HEAD_SHA="$SHA" PR_LIST=7 MERGE_METHOD=merge OPT_OUT_LABEL=no-automerge \
    DELETE_BRANCH=false DELETE_BRANCH_PREFIXES="agent/" SKIP_HEAD_BRANCHES="main,develop" ALLOW_FORKS=false \
    ALLOW_NO_CHECKS=false REQUIRE_HUMAN_READY=true REQUIRE_NO_CHANGES_REQUESTED=true POST_COMMENT=true \
    STATUS_COMMENT=true OWN_JOB_NAME="github-kit auto-merge" USING_PAT=false GRACE_SECONDS=0 \
    "$@" bash "$WORK/step.sh" > "$state.out" 2>&1
}
count() { jq --arg k "$2" '[.log[] | select(.[0] == $k)] | length' "$1"; }
comments() { jq '.comments | length' "$1"; }
body_has() { jq -e --arg t "$2" '.comments | last | .body | contains($t)' "$1" > /dev/null; }

S="$WORK/s.json"
green_check='{name: "CI (Node) / ci", status: "completed", conclusion: "success", app: {slug: "github-actions"}, html_url: "https://x/actions/runs/5/job/1", check_suite: {id: 1}}'

# 1. Ready PR with no checks: held, one sticky comment saying why and what to do.
new_state "$S"; evaluate "$S"
if [ "$(count "$S" merge)" = 0 ] && [ "$(comments "$S")" = 1 ] && body_has "$S" "no check ran" \
   && body_has "$S" "KIT_AUTOMERGE_ALLOW_NO_CHECKS" && body_has "$S" "<!-- github-kit:auto-merge-status -->"; then
  pass "no checks: not merged, one status comment explains how to proceed"
else fail "no checks: not merged, one status comment explains how to proceed"; cat "$S.out"; fi

# 2. Same state again: no new comment and no edit.
evaluate "$S"
if [ "$(comments "$S")" = 1 ] && [ "$(count "$S" patch)" = 0 ] && [ "$(count "$S" post)" = 1 ]; then
  pass "unchanged state: comment neither duplicated nor re-edited"
else fail "unchanged state: comment neither duplicated nor re-edited"; fi

# 3. A failing check appears: the same comment is edited to say so.
jq '.checks = [{name: "CI (Node) / ci", status: "completed", conclusion: "failure", app: {slug: "github-actions"}, html_url: "https://x/actions/runs/5/job/1", check_suite: {id: 1}}]' "$S" > "$S.t" && mv "$S.t" "$S"
evaluate "$S"
if [ "$(comments "$S")" = 1 ] && [ "$(count "$S" patch)" = 1 ] && body_has "$S" "failing check run(s): CI (Node) / ci (failure)"; then
  pass "failing check: the same comment is edited in place"
else fail "failing check: the same comment is edited in place"; cat "$S.out"; fi

# 4. Everything green: merged, and the summary replaces the status comment (no second comment).
jq ".checks = [$green_check]" "$S" > "$S.t" && mv "$S.t" "$S"
evaluate "$S"
if [ "$(count "$S" merge)" = 1 ] && [ "$(comments "$S")" = 1 ] && body_has "$S" "Auto-merged by github-kit"; then
  pass "green: merged, and the status comment becomes the merge summary"
else fail "green: merged, and the status comment becomes the merge summary"; cat "$S.out"; fi

# 5. Never held, green: merged with the usual single summary comment.
new_state "$S" ".checks = [$green_check]"; evaluate "$S"
if [ "$(count "$S" merge)" = 1 ] && [ "$(comments "$S")" = 1 ] && body_has "$S" "Auto-merged by github-kit"; then
  pass "green on first look: merged with one summary comment"
else fail "green on first look: merged with one summary comment"; cat "$S.out"; fi

# 6. No checks but the repo allows it: merged.
new_state "$S"; evaluate "$S" ALLOW_NO_CHECKS=true
if [ "$(count "$S" merge)" = 1 ]; then pass "no checks + KIT_AUTOMERGE_ALLOW_NO_CHECKS: merged"
else fail "no checks + KIT_AUTOMERGE_ALLOW_NO_CHECKS: merged"; cat "$S.out"; fi

# 7. Workflow-file PR the token cannot merge: held with "merge it by hand".
new_state "$S" ".checks = [$green_check] | .merge_response = \"HTTP 403: refusing to allow a GitHub App to create or update workflow\""
evaluate "$S"
if [ "$(count "$S" merge)" = 1 ] && [ "$(comments "$S")" = 1 ] && body_has "$S" "merge it by hand" && body_has "$S" ".github/workflows"; then
  pass "workflow-file PR: GitHub's refusal is explained on the PR"
else fail "workflow-file PR: GitHub's refusal is explained on the PR"; cat "$S.out"; fi

# 8. Checks still running: held as "waiting", merged later by the completion event.
new_state "$S" '.checks = [{name: "CI (Node) / ci", status: "in_progress", conclusion: null, app: {slug: "github-actions"}, html_url: "https://x/actions/runs/5/job/1", check_suite: {id: 1}}]'
evaluate "$S"
if [ "$(count "$S" merge)" = 0 ] && body_has "$S" "waiting for check run(s)"; then pass "running checks: comment says it is waiting"
else fail "running checks: comment says it is waiting"; cat "$S.out"; fi

# 9. Changes requested: held with the reviewer named.
new_state "$S" ".checks = [$green_check] | .reviews = [{state: \"CHANGES_REQUESTED\", user: {login: \"rev\"}}]"
evaluate "$S"
if [ "$(count "$S" merge)" = 0 ] && body_has "$S" "changes requested by rev"; then pass "changes requested: held, reviewer named"
else fail "changes requested: held, reviewer named"; cat "$S.out"; fi

# 10. Not handed over (draft, opened non-draft, long-lived head): no comment, no merge.
for f in '.pr.draft = true' '.timeline = []' '.pr.head.ref = "develop"'; do
  new_state "$S" "$f"; evaluate "$S"
  if [ "$(count "$S" merge)" = 0 ] && [ "$(comments "$S")" = 0 ]; then pass "not handed over ($f): silent, not merged"
  else fail "not handed over ($f): silent, not merged"; cat "$S.out"; fi
done

# 11. status_comment off: held without a comment (old behaviour).
new_state "$S"; evaluate "$S" STATUS_COMMENT=false
if [ "$(comments "$S")" = 0 ] && [ "$(count "$S" merge)" = 0 ]; then pass "status_comment=false: no comment"
else fail "status_comment=false: no comment"; fi

echo
if [ "$failures" -ne 0 ]; then echo "auto-merge tests FAILED ($failures)"; exit 1; fi
echo "auto-merge tests passed."
