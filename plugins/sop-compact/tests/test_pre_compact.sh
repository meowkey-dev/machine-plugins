#!/usr/bin/env bash
# test_pre_compact.sh — behavioral tests for pre-compact.sh hardening fixes:
#   * #117 handoff retention: prune_handoffs() keeps the most recent N handoff-*.md
#   * #118 timestamp collision: the -$$ suffix on ${TS} keeps two same-wall-second
#          writes from clobbering each other
#
# Like test_extract_handoff.sh, we lift the prune_handoffs() definition out of the
# hook (which runs top-to-bottom and can't be sourced) and eval it, so the unit tests
# exercise the actually-shipped function. The retention integration test drives the
# whole hook through its NO-SOP stub path (which writes a real handoff and prunes
# without needing a live `claude -p` sidecar).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
HOOK="${PLUGIN_DIR}/hooks/pre-compact.sh"

if [[ ! -f "$HOOK" ]]; then
  echo "FATAL: hook not found at $HOOK" >&2
  exit 1
fi

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# --- lift prune_handoffs() out of the hook --------------------------------------------
FUNC_SRC="$(awk '/^prune_handoffs\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$HOOK")"
if [[ -z "$FUNC_SRC" ]]; then
  echo "FATAL: could not extract prune_handoffs() from $HOOK" >&2
  exit 1
fi
eval "$FUNC_SRC"

count_handoffs() { ls -1 "$1"/handoff-*.md 2>/dev/null | wc -l | tr -d ' '; }

seed_handoffs() { # $1 dir, $2 count — create lexically-increasing dummy handoffs
  # Zero-padded day field (handoff-20260101.. .20260112) so lexical order is stable
  # past 9. Dated in JANUARY so they sort BEFORE any real UTC-now write the hook makes.
  local dir="$1" n="$2" i
  for (( i = 1; i <= n; i++ )); do
    printf 'x\n' > "$(printf '%s/handoff-202601%02dT000000Z-1.md' "$dir" "$i")"
  done
}

run_stub_hook() { # $1 repo dir, $2 hook path, [extra PATH prefix]
  local repo="$1" hook="$2" pathpfx="${3:-}"
  local json
  json="$(printf '{"cwd":"%s","trigger":"manual","transcript_path":"/tmp/nonexistent.jsonl","session_id":"test"}' "$repo")"
  PATH="${pathpfx:+$pathpfx:}$PATH" bash "$hook" <<<"$json" >/dev/null 2>&1
}

# --- 1. retention unit: prune_handoffs keeps the newest N ------------------------------
TD="$(mktemp -d)"
SNAP_DIR="$TD"            # prune_handoffs reads SNAP_DIR from the environment
seed_handoffs "$TD" 12    # handoff-20260101..20260112 (lexical = chronological)
SOP_COMPACT_HANDOFF_RETENTION=10 prune_handoffs
[[ "$(count_handoffs "$TD")" == "10" ]] && ok "keep=10 leaves 10 of 12" || bad "keep=10 count"
# the 2 oldest (…0101, …0102) are gone; the newest (…0112) remains
{ [[ ! -e "$TD/handoff-20260101T000000Z-1.md" ]] && [[ ! -e "$TD/handoff-20260102T000000Z-1.md" ]] \
  && [[ -e "$TD/handoff-20260112T000000Z-1.md" ]]; } \
  && ok "keep=10 removed the 2 OLDEST, kept the newest" || bad "keep=10 removed wrong files"
rm -rf "$TD"

# --- 2. retention unit: env override (default 10) + no-op guards ----------------------
TD="$(mktemp -d)"; SNAP_DIR="$TD"; seed_handoffs "$TD" 5
prune_handoffs    # no env set → default 10 → no prune (5 < 10)
[[ "$(count_handoffs "$TD")" == "5" ]] && ok "default retention (10) keeps all 5" || bad "default retention count"
rm -rf "$TD"

TD="$(mktemp -d)"; SNAP_DIR="$TD"; seed_handoffs "$TD" 5
SOP_COMPACT_HANDOFF_RETENTION=3 prune_handoffs
[[ "$(count_handoffs "$TD")" == "3" ]] && ok "RETENTION=3 leaves 3 of 5" || bad "RETENTION=3 count"
rm -rf "$TD"

TD="$(mktemp -d)"; SNAP_DIR="$TD"; seed_handoffs "$TD" 5
SOP_COMPACT_HANDOFF_RETENTION=999 prune_handoffs
[[ "$(count_handoffs "$TD")" == "5" ]] && ok "RETENTION=999 is a no-op" || bad "RETENTION=999 not no-op"
rm -rf "$TD"

TD="$(mktemp -d)"; SNAP_DIR="$TD"; seed_handoffs "$TD" 5
SOP_COMPACT_HANDOFF_RETENTION=0 prune_handoffs
[[ "$(count_handoffs "$TD")" == "5" ]] && ok "RETENTION=0 is a no-op (never delete the SessionStart file)" || bad "RETENTION=0 deleted files"
rm -rf "$TD"

TD="$(mktemp -d)"; SNAP_DIR="$TD"; seed_handoffs "$TD" 5
SOP_COMPACT_HANDOFF_RETENTION=abc prune_handoffs
[[ "$(count_handoffs "$TD")" == "5" ]] && ok "non-numeric RETENTION is a no-op" || bad "non-numeric RETENTION pruned"
rm -rf "$TD"

# --- 3. retention integration: hook prunes AFTER writing, keeps the just-written ------
TD="$(mktemp -d)"
SNAP="$TD/.claude/sop-compact"
mkdir -p "$SNAP"
seed_handoffs "$SNAP" 5                     # 5 old (January-dated) handoffs already on disk
TODAY="$(date -u +%Y%m%d)"                  # the hook stamps its write with the UTC-now date
SOP_COMPACT_HANDOFF_RETENTION=3 run_stub_hook "$TD" "$HOOK"
shopt -s nullglob; NEWFILES=( "$SNAP"/handoff-"$TODAY"T*.md ); shopt -u nullglob
{ [[ "$(count_handoffs "$SNAP")" == "3" ]] && (( ${#NEWFILES[@]} >= 1 )); } \
  && ok "stub hook writes a handoff then prunes to 3, keeping the just-written file" \
  || bad "retention integration (count=$(count_handoffs "$SNAP"), new=${#NEWFILES[@]})"
rm -rf "$TD"

# --- 4. collision integration (#118): two same-wall-second writes both land -----------
# Shim `date -u +FMT` to a FIXED wall-second so both hook runs share a timestamp prefix;
# the -$$ suffix (two bash processes = two PIDs) is the only thing keeping them distinct.
SHIMDIR="$(mktemp -d)"
cat > "$SHIMDIR/date" <<'SHIM'
#!/usr/bin/env bash
if [[ "$1" == "-u" && "$2" == "+%Y%m%dT%H%M%SZ" ]]; then
  echo "20260524T120000Z"
else
  exec /usr/bin/date "$@"
fi
SHIM
chmod +x "$SHIMDIR/date"

TD="$(mktemp -d)"; mkdir -p "$TD/.claude/sop-compact"
run_stub_hook "$TD" "$HOOK" "$SHIMDIR"
run_stub_hook "$TD" "$HOOK" "$SHIMDIR"
[[ "$(count_handoffs "$TD/.claude/sop-compact")" == "2" ]] \
  && ok "#118 fix: two same-second writes land 2 distinct handoffs (no clobber)" \
  || bad "#118 fix: expected 2 handoffs, got $(count_handoffs "$TD/.claude/sop-compact")"
rm -rf "$TD"

# --- 5. non-tautology: a seconds-only copy of the hook DOES clobber (1 file) -----------
# Strip the -$$ suffix to reconstruct the pre-fix behavior and prove test 4 actually
# depends on the fix (it would fail without it).
OLDHOOK="$(mktemp)"
sed 's/+%Y%m%dT%H%M%SZ)-\$\$"/+%Y%m%dT%H%M%SZ)"/' "$HOOK" > "$OLDHOOK"
if grep -q '%H%M%SZ)-\$\$"' "$OLDHOOK"; then
  bad "non-taut setup: could not strip -\$\$ from hook copy"
else
  TD="$(mktemp -d)"; mkdir -p "$TD/.claude/sop-compact"
  run_stub_hook "$TD" "$OLDHOOK" "$SHIMDIR"
  run_stub_hook "$TD" "$OLDHOOK" "$SHIMDIR"
  [[ "$(count_handoffs "$TD/.claude/sop-compact")" == "1" ]] \
    && ok "non-tautology: seconds-only hook clobbers to 1 file (the bug #118 fixes)" \
    || bad "non-tautology: seconds-only hook gave $(count_handoffs "$TD/.claude/sop-compact"), expected 1"
  rm -rf "$TD"
fi
rm -f "$OLDHOOK"
rm -rf "$SHIMDIR"

echo "---"
echo "pre_compact: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
