#!/usr/bin/env bash
# test_extract_handoff.sh — verify the sentinel extraction in pre-compact.sh
#
# v0.3.1 wraps the sidecar's handoff in ===HANDOFF=== / ===END=== sentinels so the
# sidecar's promotion-decision narration stays out of the saved handoff file. The
# extract_handoff() function pulls only the between-sentinel body. These tests cover:
#   1. happy path: leading narration + trailing commentary stripped, leading blank removed
#   2. no leading blank after the opening sentinel
#   3. trailing commentary after ===END=== dropped
#   4. missing sentinels → failure (caller falls back to raw output)
#   5. opening sentinel with no closing ===END=== → failure
#   6. sentinels present but empty body → failure
#   7. blank lines *inside* the body are preserved
#
# extract_handoff lives inside pre-compact.sh (which runs top-to-bottom and can't be
# sourced), so we lift the function definition out of the hook and eval it. That way the
# test exercises the actually-shipped code rather than a copy that could drift.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
HOOK="${PLUGIN_DIR}/hooks/pre-compact.sh"

if [[ ! -f "$HOOK" ]]; then
  echo "FATAL: hook not found at $HOOK" >&2
  exit 1
fi

# Lift `extract_handoff() { ... }` out of the hook (from its definition line to the closing
# brace that sits in column 0) and define it in this shell.
FUNC_SRC="$(awk '/^extract_handoff\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$HOOK")"
if [[ -z "$FUNC_SRC" ]]; then
  echo "FATAL: could not extract extract_handoff() from $HOOK" >&2
  exit 1
fi
eval "$FUNC_SRC"

PASS=0
FAIL=0

check() { # $1 desc, $2 expected_rc, $3 expected_out  (uses globals RC, OUT)
  local desc="$1" exp_rc="$2" exp_out="$3"
  if [[ "$RC" == "$exp_rc" && "$OUT" == "$exp_out" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    rc:  got=$RC want=$exp_rc"
    printf '    out: got=[%s]\n         want=[%s]\n' "$OUT" "$exp_out"
    FAIL=$((FAIL + 1))
  fi
}

# 1. happy path — narration before, commentary after, blank line after the sentinel.
OUT="$(printf '%s' $'Nothing new to promote — already on disk.\n\n===HANDOFF===\n\n# Pre-compact handoff\n\n## What this session was\nstuff\n===END===\nHope that helps!\n' | extract_handoff)"; RC=$?
check "happy path strips narration, commentary, and leading blank" 0 $'# Pre-compact handoff\n\n## What this session was\nstuff'

# 2. no leading blank after the opening sentinel.
OUT="$(printf '%s' $'===HANDOFF===\n# Pre-compact handoff\nbody\n===END===\n' | extract_handoff)"; RC=$?
check "no leading blank to strip" 0 $'# Pre-compact handoff\nbody'

# 3. trailing commentary after ===END=== is dropped.
OUT="$(printf '%s' $'===HANDOFF===\n# H\nx\n===END===\nHope that helps!\nmore noise\n' | extract_handoff)"; RC=$?
check "trailing commentary dropped" 0 $'# H\nx'

# 4. no sentinels at all → failure (caller writes raw output as fallback).
OUT="$(printf '%s' $'# Pre-compact handoff\nraw output, no sentinels\n' | extract_handoff)"; RC=$?
check "missing sentinels → failure" 1 ""

# 5. opening sentinel but never closed → failure.
OUT="$(printf '%s' $'===HANDOFF===\n# H\nnever closed\n' | extract_handoff)"; RC=$?
check "unclosed sentinel → failure" 1 ""

# 6. sentinels present but body is empty/blank → failure.
OUT="$(printf '%s' $'===HANDOFF===\n\n===END===\n' | extract_handoff)"; RC=$?
check "empty body → failure" 1 ""

# 7. blank lines inside the body are preserved.
OUT="$(printf '%s' $'===HANDOFF===\n# H\n\npara1\n\npara2\n===END===\n' | extract_handoff)"; RC=$?
check "internal blank lines preserved" 0 $'# H\n\npara1\n\npara2'

echo "---"
echo "extract_handoff: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
