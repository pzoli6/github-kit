#!/usr/bin/env bash
# One command that runs every check on github-kit itself. Free to run locally; the manually
# dispatched .github/workflows/kit-selfcheck.yml runs the same thing on a GitHub runner.
#
#   1. doctor-github-kit.sh           packaging, manifest integrity, pause guards, gates
#   2. actionlint                     workflow syntax, expression types, script-injection sinks
#   3. shellcheck -S error            real errors in every shell script (warnings are not gated)
#   4. JSON                           fan-out registry and Claude settings template parse
#   5. test-auto-merge.sh             auto-merge decisions and its status comment (fake gh)
#   6. test-apply-repo-variables.sh   registry variables script, incl. CRLF from Windows jq.exe
#   7. test-install-update.sh         install/update promises, bash vs PowerShell parity
#
# A missing optional tool (actionlint, shellcheck, pwsh) is reported as SKIP, not as a failure,
# so the script is useful on any machine; CI installs all of them.
set -uo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$KIT_ROOT" || exit 1
failed=0

step() { printf '\n=== %s\n' "$1"; }
result() { if [ "$1" -eq 0 ]; then echo "PASS    $2"; else echo "FAIL    $2"; failed=1; fi; }

step "doctor"
doctor_log="$(mktemp)"
bash scripts/doctor-github-kit.sh > "$doctor_log" 2>&1
rc=$?
grep -vE '^OK|^$' "$doctor_log"
rm -f "$doctor_log"
result "$rc" "doctor-github-kit.sh"

step "actionlint"
if command -v actionlint > /dev/null; then
  actionlint .github/workflows/*.yml templates/.github/workflows/*.yml
  result $? "actionlint"
else
  echo "SKIP    actionlint not installed (https://github.com/rhysd/actionlint)"
fi

step "shellcheck"
if command -v shellcheck > /dev/null; then
  mapfile -t shells < <(git ls-files -- '*.sh')
  shellcheck -S error -x "${shells[@]}"
  result $? "shellcheck -S error (${#shells[@]} files)"
else
  echo "SKIP    shellcheck not installed"
fi

step "JSON"
json_ok=0
for f in .github/fanout-targets.json templates/.claude/settings.json; do
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" || { echo "invalid JSON: $f"; json_ok=1; }
done
result "$json_ok" "JSON files parse"

step "auto-merge behaviour"
if python3 -c 'import yaml' 2>/dev/null; then
  bash scripts/test-auto-merge.sh
  result $? "test-auto-merge.sh"
else
  echo "SKIP    test-auto-merge.sh needs python3 with PyYAML (pip install pyyaml)"
fi

step "apply-repo-variables"
bash scripts/test-apply-repo-variables.sh
result $? "test-apply-repo-variables.sh"

step "install/update"
bash scripts/test-install-update.sh
result $? "test-install-update.sh"

echo
if [ "$failed" -ne 0 ]; then
  echo "github-kit selfcheck FAILED"
  exit 1
fi
echo "github-kit selfcheck passed."
