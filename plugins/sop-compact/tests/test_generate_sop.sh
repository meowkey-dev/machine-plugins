#!/usr/bin/env bash
# test_generate_sop.sh — behavioral tests for the v0.5.0 auto-bootstrap helper.
#
# generate_sop() lives in hooks/lib/generate-sop.sh and is sourced by pre-compact.sh.
# Unlike the other test_*.sh files (which lift functions out of pre-compact.sh because
# that script runs top-to-bottom and can't be sourced cleanly), this helper IS designed
# to be sourced — so we source it directly.
#
# Covered:
#   1. missing template (CLAUDE_PLUGIN_ROOT pointing at a directory with no template) →
#      function returns 1, no SOP file written.
#   2. claude sidecar fails (PATH-shimmed to exit 1) → function returns 1, an error log
#      lands under .claude/sop-compact/, no half-written SOP file appears.
#   3. claude sidecar succeeds (PATH-shimmed to emit canned markdown) → function returns
#      0, .claude/sop-compact.md exists with the canned content, and .gitignore gets the
#      handoff entry appended exactly once even across two successful runs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
HELPER="${PLUGIN_DIR}/hooks/lib/generate-sop.sh"

if [[ ! -f "$HELPER" ]]; then
  echo "FATAL: helper not found at $HELPER" >&2
  exit 1
fi

# shellcheck source=../hooks/lib/generate-sop.sh
source "$HELPER"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# --- 1. missing template → return 1, error log written (PR #152 fix) ------------------
TD="$(mktemp -d)"
EMPTY_ROOT="$(mktemp -d)"   # no templates/ subdir → template path won't exist
CLAUDE_PLUGIN_ROOT="$EMPTY_ROOT" generate_sop "$TD" >/dev/null 2>&1
RC=$?
shopt -s nullglob; LOGS=( "$TD/.claude/sop-compact"/bootstrap-*.error.log ); shopt -u nullglob
{ [[ "$RC" == "1" ]] && [[ ! -f "$TD/.claude/sop-compact.md" ]] && (( ${#LOGS[@]} >= 1 )); } \
  && ok "missing template → return 1, no SOP, error log written (so the stub handoff's pointer is accurate)" \
  || bad "missing template (rc=$RC, sop exists=$([[ -f "$TD/.claude/sop-compact.md" ]] && echo y || echo n), logs=${#LOGS[@]})"
rm -rf "$TD" "$EMPTY_ROOT"

# --- 2. sidecar fails → return 1, error log present, no SOP file ---------------------
SHIMDIR="$(mktemp -d)"
cat > "$SHIMDIR/claude" <<'SHIM'
#!/usr/bin/env bash
exit 1
SHIM
chmod +x "$SHIMDIR/claude"

TD="$(mktemp -d)"
PATH="$SHIMDIR:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" generate_sop "$TD" >/dev/null 2>&1
RC=$?
shopt -s nullglob; LOGS=( "$TD/.claude/sop-compact"/bootstrap-*.error.log ); shopt -u nullglob
{ [[ "$RC" == "1" ]] && (( ${#LOGS[@]} >= 1 )) && [[ ! -f "$TD/.claude/sop-compact.md" ]]; } \
  && ok "sidecar fails → return 1, error log written, no SOP" \
  || bad "sidecar fail (rc=$RC, logs=${#LOGS[@]}, sop exists=$([[ -f "$TD/.claude/sop-compact.md" ]] && echo y || echo n))"
rm -rf "$TD"

# --- 3. sidecar succeeds → SOP written, .gitignore entry appended once ----------------
cat > "$SHIMDIR/claude" <<'SHIM'
#!/usr/bin/env bash
cat <<'BODY'
# SOP: Compaction Survival — test-repo

Canned bootstrap output for the unit test.
BODY
SHIM
chmod +x "$SHIMDIR/claude"

TD="$(mktemp -d)"
PATH="$SHIMDIR:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" generate_sop "$TD" >/dev/null 2>&1
RC=$?
{ [[ "$RC" == "0" ]] \
  && [[ -f "$TD/.claude/sop-compact.md" ]] \
  && grep -q "^# SOP: Compaction Survival — test-repo" "$TD/.claude/sop-compact.md" \
  && grep -qxF '.claude/sop-compact/handoff-*.md' "$TD/.gitignore"; } \
  && ok "sidecar succeeds → SOP written and .gitignore appended" \
  || bad "sidecar success (rc=$RC, sop=$([[ -f "$TD/.claude/sop-compact.md" ]] && echo y || echo n), gitignore=$([[ -f "$TD/.gitignore" ]] && echo y || echo n))"

# Re-run: .gitignore entry must NOT be duplicated.
PATH="$SHIMDIR:$PATH" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" generate_sop "$TD" >/dev/null 2>&1
COUNT=$(grep -cxF '.claude/sop-compact/handoff-*.md' "$TD/.gitignore" 2>/dev/null || echo 0)
[[ "$COUNT" == "1" ]] \
  && ok ".gitignore entry is idempotent across re-runs" \
  || bad ".gitignore entry duplicated (count=$COUNT)"
rm -rf "$TD"
rm -rf "$SHIMDIR"

echo "---"
echo "generate_sop: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
