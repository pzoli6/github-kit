#!/usr/bin/env bash
# Regression test for install-github-kit.{sh,ps1} and update-github-kit.{sh,ps1}.
#
# Runs both installers and updaters against throwaway repositories and asserts the promises the
# kit makes to target repos:
#   - every manifest file is installed, and the result passes verify_agent_workflow.sh
#   - repo-owned files (PROJECT_CONFIG.md, .claude/settings.json, pr-policy.yml, ...) survive
#     update and install --mode force untouched
#   - text outside the managed-block markers is never changed
#   - --ref rewrites only `uses:` lines; --tier 2 drops the automatic triggers and sticks
#   - the bash and PowerShell scripts produce byte-identical trees (when pwsh is available)
#
# Usage: scripts/test-install-update.sh    (needs git; pwsh optional)
set -uo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PWSH="$(command -v pwsh || true)"
failures=0

pass() { echo "PASS    $1"; }
fail() { echo "FAIL    $1"; failures=$((failures + 1)); }

new_repo() {
  rm -rf "$1"; mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" -c user.email=t@example.com -c user.name=test commit -q --allow-empty -m init
}
commit_all() {
  git -C "$1" add -A
  git -C "$1" -c user.email=t@example.com -c user.name=test commit -q -m snapshot >/dev/null 2>&1 || true
}
tree_hash() {
  (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do
    printf '%s %s %s\n' "$(cksum < "$f")" "$([ -x "$f" ] && echo x || echo -)" "$f"
  done) | cksum
}

# install <sh|ps1> <repo> [args...]   args use the bash spelling; translated for PowerShell.
install() {
  local impl="$1" repo="$2"; shift 2
  if [ "$impl" = sh ]; then
    bash "$KIT_ROOT/scripts/install-github-kit.sh" --target "$repo" "$@"
  else
    local a=(-Target "$repo")
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --mode) a+=(-Mode "$2"); shift ;;
        --ref) a+=(-Ref "$2"); shift ;;
        --tier) a+=(-Tier "$2"); shift ;;
        --include-project-sync) a+=(-IncludeProjectSync) ;;
        --allow-dirty) a+=(-AllowDirty) ;;
      esac
      shift
    done
    "$PWSH" -NoProfile -File "$KIT_ROOT/scripts/install-github-kit.ps1" "${a[@]}"
  fi
}
update() {
  local impl="$1" repo="$2"; shift 2
  if [ "$impl" = sh ]; then
    bash "$KIT_ROOT/scripts/update-github-kit.sh" --target "$repo" "$@"
  else
    local a=(-Target "$repo")
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --ref) a+=(-Ref "$2"); shift ;;
        --tier) a+=(-Tier "$2"); shift ;;
        --force-config) a+=(-ForceConfig) ;;
        --include-project-sync) a+=(-IncludeProjectSync) ;;
        --allow-dirty) a+=(-AllowDirty) ;;
      esac
      shift
    done
    "$PWSH" -NoProfile -File "$KIT_ROOT/scripts/update-github-kit.ps1" "${a[@]}"
  fi
}

impls="sh"
if [ -n "$PWSH" ]; then impls="sh ps1"; else echo "note: pwsh not found — PowerShell scripts not exercised"; fi

for impl in $impls; do
  echo "--- $impl"
  R="$WORK/$impl"

  # 1. Fresh install: every manifest file lands, verification passes.
  new_repo "$R/fresh"
  install "$impl" "$R/fresh" > "$WORK/$impl-fresh.log" 2>&1
  missing_files=0
  while IFS=$'\t' read -r kind path mode _group; do
    [ "$kind" = file ] || continue
    case "$mode" in workflow-opt|retired) continue ;; esac
    [ -e "$R/fresh/$path" ] || { echo "        not installed: $path"; missing_files=1; }
  done < "$KIT_ROOT/templates/docs/ai/KIT_MANIFEST.tsv"
  [ "$missing_files" -eq 0 ] && pass "$impl install places every manifest file" || fail "$impl install places every manifest file"
  if (cd "$R/fresh" && bash scripts/project/verify_agent_workflow.sh > /dev/null 2>&1); then
    pass "$impl fresh install passes verify_agent_workflow.sh"
  else
    fail "$impl fresh install passes verify_agent_workflow.sh"
  fi
  [ -x "$R/fresh/scripts/project/create_agent_pr.sh" ] && pass "$impl project scripts are executable" || fail "$impl project scripts are executable"

  # 2. Existing repo with its own content: install --mode force keeps repo-owned files and the
  #    text around the managed block.
  new_repo "$R/custom"
  printf '# Team notes\n\nKeep this line.\n' > "$R/custom/AGENTS.md"
  mkdir -p "$R/custom/.claude" "$R/custom/.github/workflows" "$R/custom/docs/ai"
  printf '{"custom": true}\n' > "$R/custom/.claude/settings.json"
  printf 'name: my policy\n' > "$R/custom/.github/workflows/pr-policy.yml"
  printf 'my config\n' > "$R/custom/docs/ai/PROJECT_CONFIG.md"
  commit_all "$R/custom"
  install "$impl" "$R/custom" --mode force --include-project-sync --ref v9 > "$WORK/$impl-custom.log" 2>&1
  preserved=1
  grep -qx '{"custom": true}' "$R/custom/.claude/settings.json" || { echo "        overwritten: .claude/settings.json"; preserved=0; }
  grep -qx 'name: my policy' "$R/custom/.github/workflows/pr-policy.yml" || { echo "        overwritten: pr-policy.yml"; preserved=0; }
  grep -qx 'my config' "$R/custom/docs/ai/PROJECT_CONFIG.md" || { echo "        overwritten: PROJECT_CONFIG.md"; preserved=0; }
  head -3 "$R/custom/AGENTS.md" | grep -qx 'Keep this line.' || { echo "        changed: AGENTS.md text outside the block"; preserved=0; }
  [ "$preserved" -eq 1 ] && pass "$impl install --mode force keeps repo-owned content" || fail "$impl install --mode force keeps repo-owned content"
  if grep -q 'reusable-ci-node.yml@v9' "$R/custom/.github/workflows/ci-node.yml" \
      && grep -q 'branches: \[main\]' "$R/custom/.github/workflows/ci-node.yml"; then
    pass "$impl --ref rewrites uses: lines only"
  else
    fail "$impl --ref rewrites uses: lines only"
  fi

  # 3. Update on a drifted install: kit-owned files refresh, repo-owned ones stay, the managed
  #    block is replaced in place, and a second run is a no-op.
  commit_all "$R/fresh"
  printf 'drift\n' >> "$R/fresh/docs/ai/AGENT_WORKFLOW.md"
  printf 'my config\n' > "$R/fresh/docs/ai/PROJECT_CONFIG.md"
  printf '{"mine": 1}\n' > "$R/fresh/.claude/settings.json"
  printf '\nMy own footer.\n' >> "$R/fresh/CLAUDE.md"
  rm -f "$R/fresh/.cursor/rules/git-safety.mdc"
  commit_all "$R/fresh"
  update "$impl" "$R/fresh" > "$WORK/$impl-update.log" 2>&1
  ok=1
  cmp -s "$R/fresh/docs/ai/AGENT_WORKFLOW.md" "$KIT_ROOT/templates/docs/ai/AGENT_WORKFLOW.md" || { echo "        not refreshed: AGENT_WORKFLOW.md"; ok=0; }
  [ -e "$R/fresh/.cursor/rules/git-safety.mdc" ] || { echo "        not restored: git-safety.mdc"; ok=0; }
  grep -qx 'my config' "$R/fresh/docs/ai/PROJECT_CONFIG.md" || { echo "        overwritten: PROJECT_CONFIG.md"; ok=0; }
  grep -qx '{"mine": 1}' "$R/fresh/.claude/settings.json" || { echo "        overwritten: settings.json"; ok=0; }
  tail -1 "$R/fresh/CLAUDE.md" | grep -qx 'My own footer.' || { echo "        lost: CLAUDE.md text after the block"; ok=0; }
  [ "$ok" -eq 1 ] && pass "$impl update refreshes kit files and keeps repo-owned ones" || fail "$impl update refreshes kit files and keeps repo-owned ones"
  # A repo's own lines between the auto-merge.yml repo-workflows markers survive a refresh.
  am="$R/fresh/.github/workflows/auto-merge.yml"
  if [ -f "$am" ] && grep -qF '# >>> github-kit: repo workflows >>>' "$am"; then
    awk '{ print } index($0, "# >>> github-kit: repo workflows >>>") { print "      - \"My Repo Tests\"" }' "$am" > "$am.tmp" && mv "$am.tmp" "$am"
    update "$impl" "$R/fresh" --allow-dirty > /dev/null 2>&1
    grep -qF -- '- "My Repo Tests"' "$am" && pass "$impl update keeps the repo's auto-merge workflow list" \
      || fail "$impl update keeps the repo's auto-merge workflow list"
  fi
  before="$(tree_hash "$R/fresh")"
  update "$impl" "$R/fresh" --allow-dirty > /dev/null 2>&1
  [ "$before" = "$(tree_hash "$R/fresh")" ] && pass "$impl update is idempotent" || fail "$impl update is idempotent"

  # 4. Retired files: an untouched shipped copy is deleted, an edited copy is kept.
  retired_row="$(awk -F'\t' '$1 == "file" && $3 == "retired" { print $2 "\t" $5; exit }' "$KIT_ROOT/templates/docs/ai/KIT_MANIFEST.tsv")"
  if [ -n "$retired_row" ]; then
    rpath="${retired_row%%$'\t'*}"
    rsha="${retired_row#*$'\t'}"; rsha="${rsha%%,*}"
    mkdir -p "$R/fresh/$(dirname "$rpath")"
    git -C "$KIT_ROOT" cat-file blob "$rsha" > "$R/fresh/$rpath"
    new_repo "$R/edited"; install "$impl" "$R/edited" > /dev/null 2>&1
    mkdir -p "$R/edited/$(dirname "$rpath")"
    { git -C "$KIT_ROOT" cat-file blob "$rsha"; echo "local edit"; } > "$R/edited/$rpath"
    update "$impl" "$R/fresh" --allow-dirty > /dev/null 2>&1
    update "$impl" "$R/edited" --allow-dirty > /dev/null 2>&1
    if [ ! -e "$R/fresh/$rpath" ] && [ -e "$R/edited/$rpath" ]; then
      pass "$impl retired file removed when untouched, kept when edited"
    else
      fail "$impl retired file removed when untouched, kept when edited"
    fi
  fi

  # 5. Tier: 2 drops the automatic triggers, sticks without the flag, and 1 restores them.
  update "$impl" "$R/fresh" --allow-dirty --tier 2 > /dev/null 2>&1
  wf="$R/fresh/.github/workflows/ci-python.yml"
  if grep -qx '# github-kit tier: 2' "$wf" && ! grep -q 'pull_request:' "$wf"; then
    update "$impl" "$R/fresh" --allow-dirty > /dev/null 2>&1
    if grep -qx '# github-kit tier: 2' "$wf" && ! grep -q 'pull_request:' "$wf"; then
      update "$impl" "$R/fresh" --allow-dirty --tier 1 > /dev/null 2>&1
      [ "$before" = "$(tree_hash "$R/fresh")" ] && pass "$impl tier 2 sticks and tier 1 restores the original" || fail "$impl tier 1 restores the original"
    else
      fail "$impl tier 2 is kept by a later update without --tier"
    fi
  else
    fail "$impl --tier 2 drops the automatic triggers"
  fi
done

# 6. Parity: bash and PowerShell produce identical trees for the same steps.
if [ -n "$PWSH" ]; then
  for step in fresh custom; do
    if [ "$(tree_hash "$WORK/sh/$step")" = "$(tree_hash "$WORK/ps1/$step")" ]; then
      pass "bash and PowerShell trees identical ($step)"
    else
      fail "bash and PowerShell trees identical ($step)"
      diff -r -x .git "$WORK/sh/$step" "$WORK/ps1/$step" | head -20
    fi
  done
fi

echo
if [ "$failures" -ne 0 ]; then
  echo "install/update tests FAILED ($failures) — logs were in $WORK"
  trap - EXIT
  exit 1
fi
echo "install/update tests passed."
