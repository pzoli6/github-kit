# shellcheck shell=bash
# Shared helpers for install-github-kit.sh and update-github-kit.sh. Sourced, never executed.
#
# The list of files, and how each is treated, lives in templates/docs/ai/KIT_MANIFEST.tsv. This
# library only knows the *modes* (see the manifest header); it never names a template file itself.
#
# Callers set before calling kit_sync_manifest:
#   TEMPLATES             path to github-kit's templates/ directory
#   KIT_OP                install | update
#   KIT_FORCE             true = install --mode force (refresh kit-owned files that already exist)
#   FORCE_CONFIG          true = update --force-config (reset `config` files to the template)
#   INCLUDE_PROJECT_SYNC  1 = install `workflow-opt` files even when absent
#   WORKFLOW_REF          ref written into `uses: pzoli6/github-kit/...@<ref>` lines
#   KIT_TIER              1 | 2 | "" (empty = keep each caller's current tier, default 1)
# and read back CREATED_COUNT, UPDATED_COUNT, SKIPPED_COUNT afterwards.

CREATED_COUNT=0
UPDATED_COUNT=0
SKIPPED_COUNT=0

KIT_TIER_BEGIN='# >>> github-kit tier-1 triggers'
KIT_TIER_END='# <<< github-kit tier-1 triggers'

kit_manifest_path() {
  printf '%s\n' "$TEMPLATES/docs/ai/KIT_MANIFEST.tsv"
}

# Print "<path>\t<mode>\t<verify>" for every file row of the kit's manifest.
kit_manifest_files() {
  awk -F'\t' '{ sub(/\r$/, "") } $1 == "file" && NF >= 4 { print $2 "\t" $3 "\t" $4 }' "$(kit_manifest_path)"
}

kit_log() {
  # $1 = action label, $2 = path. Fixed-width label keeps the output scannable.
  printf '%-26s %s\n' "$1:" "$2"
}

# Tier of an existing caller workflow, from its "# github-kit tier: N" line. Empty if none.
kit_existing_tier() {
  [ -f "$1" ] || return 0
  sed -nE 's/^# github-kit tier: ([0-9]+)[[:space:]]*$/\1/p' "$1" | head -n1
}

# Render a caller workflow template ($1) to a destination ($2): point `uses:` lines at
# $WORKFLOW_REF and apply the tier. Only the `uses: pzoli6/github-kit/...` line's ref changes;
# other occurrences of "main" (branch filters) are left alone.
kit_render_workflow() {
  local src="$1" dst="$2" tier="$KIT_TIER"
  [ -n "$tier" ] || tier="$(kit_existing_tier "$dst")"
  [ -n "$tier" ] || tier=1
  local tmp
  tmp="$(mktemp)"
  sed -E "s#(uses: pzoli6/github-kit/[^@[:space:]]+)@main#\1@$WORKFLOW_REF#" "$src" |
    awk -v tier="$tier" -v b="$KIT_TIER_BEGIN" -v e="$KIT_TIER_END" '
      /^# github-kit tier: [0-9]+[[:space:]]*$/ { print "# github-kit tier: " tier; next }
      tier != 1 && index($0, b) { skip = 1; next }
      tier != 1 && index($0, e) { skip = 0; next }
      skip { next }
      { print }
    ' > "$tmp"
  mkdir -p "$(dirname "$dst")"
  mv "$tmp" "$dst"
}

kit_copy() {
  # $1 = mode, $2 = template path, $3 = destination
  mkdir -p "$(dirname "$3")"
  case "$1" in
    workflow*) kit_render_workflow "$2" "$3" ;;
    *) cp "$2" "$3" ;;
  esac
}

# Extract the managed block (BEGIN line through END line) from a template file.
kit_template_block() {
  awk '/^<!-- BEGIN GITHUB-KIT [A-Z -]+ -->$/ { p = 1 } p { print } p && /^<!-- END GITHUB-KIT [A-Z -]+ -->$/ { exit }' "$1"
}

# Refresh only the text between the template's own markers inside $2; create $2 from the whole
# template if it doesn't exist; append the block if $2 exists without markers.
kit_apply_block() {
  local src="$1" dst="$2" block_tmp begin end
  block_tmp="$(mktemp)"
  kit_template_block "$src" > "$block_tmp"
  begin="$(head -n1 "$block_tmp")"
  end="$(tail -n1 "$block_tmp")"
  if [ -z "$begin" ] || [ "$begin" = "$end" ]; then
    echo "error: $src has no <!-- BEGIN/END GITHUB-KIT ... --> managed block" >&2
    rm -f "$block_tmp"
    return 1
  fi

  if [ ! -e "$dst" ]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    kit_log "created" "$dst"
    CREATED_COUNT=$((CREATED_COUNT + 1))
  elif grep -qxF "$begin" "$dst"; then
    awk -v begin="$begin" -v end="$end" -v blockfile="$block_tmp" '
      BEGIN { while ((getline line < blockfile) > 0) block = block line "\n" }
      $0 == begin { printf "%s", block; skip = 1; next }
      $0 == end { skip = 0; next }
      skip { next }
      { print }
    ' "$dst" > "$dst.gktmp"
    mv "$dst.gktmp" "$dst"
    kit_log "updated managed block" "$dst"
    UPDATED_COUNT=$((UPDATED_COUNT + 1))
  else
    { cat "$dst"; echo; cat "$block_tmp"; } > "$dst.gktmp"
    mv "$dst.gktmp" "$dst"
    kit_log "appended managed block" "$dst"
    UPDATED_COUNT=$((UPDATED_COUNT + 1))
  fi
  rm -f "$block_tmp"
}

# Apply one manifest row.
kit_sync_file() {
  local path="$1" mode="$2" src="$TEMPLATES/$1"
  if [ ! -e "$src" ]; then
    echo "error: manifest lists $path but $src does not exist" >&2
    return 1
  fi

  case "$mode" in
    block)
      kit_apply_block "$src" "$path"
      return
      ;;
    workflow-opt)
      if [ "$INCLUDE_PROJECT_SYNC" -ne 1 ] && { [ "$KIT_OP" = "install" ] || [ ! -e "$path" ]; }; then
        kit_log "skip (default)" "$path (pass --include-project-sync to install it)"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return
      fi
      ;;
  esac

  local overwrite=false
  case "$mode" in
    refresh|refresh-exec|workflow)
      if [ "$KIT_OP" = "update" ] || [ "$KIT_FORCE" = "true" ]; then overwrite=true; fi ;;
    config)
      if [ "$KIT_OP" = "update" ] && [ "$FORCE_CONFIG" = "true" ]; then overwrite=true; fi ;;
    create|workflow-create|workflow-opt) ;;
    *)
      echo "error: unknown manifest mode '$mode' for $path" >&2
      return 1 ;;
  esac

  if [ ! -e "$path" ]; then
    kit_copy "$mode" "$src" "$path"
    kit_log "created" "$path"
    CREATED_COUNT=$((CREATED_COUNT + 1))
  elif [ "$overwrite" = "true" ]; then
    kit_copy "$mode" "$src" "$path"
    kit_log "refreshed" "$path"
    UPDATED_COUNT=$((UPDATED_COUNT + 1))
  else
    case "$mode" in
      refresh|refresh-exec|workflow) kit_log "skip (exists)" "$path" ;;
      *) kit_log "skip (repo-owned, kept)" "$path" ;;
    esac
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
  fi

  if [ "$mode" = "refresh-exec" ]; then
    chmod +x "$path" 2>/dev/null || true
  fi
}

kit_sync_manifest() {
  local path mode _verify
  while IFS=$'\t' read -r path mode _verify; do
    kit_sync_file "$path" "$mode" || return 1
  done < <(kit_manifest_files)
}

# Legacy hygiene: only SKILL.md-based skill directories belong under .claude/skills/. Warn about
# stray workflow YAMLs or STATUS_BADGES.md there; never delete automatically.
kit_warn_stray_skills() {
  local stray
  stray="$(find .claude/skills -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' -o -name 'STATUS_BADGES.md' \) 2>/dev/null || true)"
  if [ -n "$stray" ]; then
    echo "warning: non-skill files found directly under .claude/skills/ — they aren't skills;"
    echo "move workflow YAMLs to .github/workflows/ (or delete them):"
    printf '  %s\n' $stray
  fi
}

kit_ensure_gitignore() {
  local line="docs/ai/PROJECT_CONFIG.env"
  if [ -f .gitignore ]; then
    if ! grep -qxF "$line" .gitignore; then
      printf '\n%s\n' "$line" >> .gitignore
      kit_log "updated" ".gitignore (added $line)"
    else
      kit_log "skip (exists)" ".gitignore already ignores $line"
    fi
  else
    printf '%s\n' "$line" > .gitignore
    kit_log "created" ".gitignore"
  fi
}
