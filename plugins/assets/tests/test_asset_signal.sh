#!/usr/bin/env bash
# test_asset_signal.sh — exercise the hook-helper that emits lifecycle signals.
#
# Feeds fixture hook JSON on stdin for each of the 4 events and asserts the
# write contract (JSONL line for boot/turn_end/exit; activity file touch for
# PostToolUse). Also covers the transcript fallback when the Stop hook does not
# include last_assistant_message, malformed-transcript graceful degradation,
# and the exit-0 invariant on a read-only signals dir.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
SIGNAL="${PLUGIN_DIR}/bin/asset-signal"

TEST_TMPDIR="$(mktemp -d)"
trap 'chmod -R u+rwX "$TEST_TMPDIR" 2>/dev/null || true; rm -rf "$TEST_TMPDIR"' EXIT

PASS_FILE="${TEST_TMPDIR}/.pass"
FAIL_FILE="${TEST_TMPDIR}/.fail"
echo 0 > "$PASS_FILE"; echo 0 > "$FAIL_FILE"

_pass() { echo "  PASS: $1"; echo $(( $(cat "$PASS_FILE") + 1 )) > "$PASS_FILE"; }
_fail() { echo "  FAIL: $1"; echo $(( $(cat "$FAIL_FILE") + 1 )) > "$FAIL_FILE"; }

# Validate that a JSONL file contains valid JSON on every non-empty line.
_validate_jsonl() {
    local file="$1"
    python3 - "$file" <<'PY'
import json, sys
ok = True
with open(sys.argv[1], "r", encoding="utf-8") as f:
    for i, line in enumerate(f, 1):
        line = line.rstrip("\n")
        if not line:
            continue
        try:
            json.loads(line)
        except Exception as e:
            print(f"line {i}: {e}", file=sys.stderr)
            ok = False
sys.exit(0 if ok else 1)
PY
}

# Read the field of the LAST JSONL line.
_last_field() {
    local file="$1" field="$2"
    python3 - "$file" "$field" <<'PY'
import json, sys
path, field = sys.argv[1], sys.argv[2]
last = None
with open(path, "r", encoding="utf-8") as f:
    for line in f:
        line = line.rstrip("\n")
        if not line:
            continue
        try:
            last = json.loads(line)
        except Exception:
            pass
if last is None:
    sys.exit(2)
v = last.get(field)
if v is None:
    print("__NONE__")
elif isinstance(v, str):
    print(v)
else:
    print(json.dumps(v))
PY
}

SIGNALS="${TEST_TMPDIR}/signals"
mkdir -p "$SIGNALS"
export ASSET_NAME="t-asset"
export ASSETS_SIGNALS_DIR="$SIGNALS"
JSONL="${SIGNALS}/${ASSET_NAME}.jsonl"
ACTIVITY="${SIGNALS}/${ASSET_NAME}.activity"

# ── Test 1: boot (SessionStart) ──────────────────────────────────────────────

echo "Test 1: boot event"
printf '{"session_id":"sid-123","cwd":"/work/foo","hook_event_name":"SessionStart","source":"startup"}' \
    | "$SIGNAL" boot
[[ -s "$JSONL" ]] && _pass "JSONL written" || _fail "JSONL not written"
_validate_jsonl "$JSONL" 2>/dev/null && _pass "JSONL is valid JSON per line" || _fail "JSONL has invalid lines"
[[ "$(_last_field "$JSONL" event)" == "boot" ]] && _pass "event=boot" || _fail "event != boot"
[[ "$(_last_field "$JSONL" session_id)" == "sid-123" ]] && _pass "session_id captured" || _fail "session_id missing"
[[ "$(_last_field "$JSONL" cwd)" == "/work/foo" ]] && _pass "cwd captured" || _fail "cwd missing"
[[ "$(_last_field "$JSONL" source)" == "startup" ]] && _pass "source captured" || _fail "source missing"

# ── Test 2: activity (PostToolUse) ───────────────────────────────────────────

echo "Test 2: activity (PostToolUse — bare mtime touch)"
PRIOR_JSONL_BYTES=$(stat -c '%s' "$JSONL" 2>/dev/null || echo 0)
echo '{"hook_event_name":"PostToolUse","tool_name":"Bash"}' | "$SIGNAL" activity
[[ -f "$ACTIVITY" ]] && _pass "activity file present" || _fail "activity file missing"
POST_JSONL_BYTES=$(stat -c '%s' "$JSONL" 2>/dev/null || echo 0)
[[ "$POST_JSONL_BYTES" == "$PRIOR_JSONL_BYTES" ]] && _pass "PostToolUse did NOT append to JSONL" || _fail "PostToolUse appended to JSONL (should be touch-only)"

# A second touch must update mtime — sleep 1s so atime/mtime granularity shows the change.
PRIOR_MTIME=$(stat -c '%Y' "$ACTIVITY")
sleep 1
echo '{}' | "$SIGNAL" activity
POST_MTIME=$(stat -c '%Y' "$ACTIVITY")
[[ "$POST_MTIME" -gt "$PRIOR_MTIME" ]] && _pass "activity mtime advanced on second touch" || _fail "activity mtime did not advance"

# ── Test 3: turn_end (Stop) with last_assistant_message in input ─────────────

echo "Test 3: turn_end with last_assistant_message"
printf '%s' '{"hook_event_name":"Stop","last_assistant_message":"PR opened: https://x\nLine 2\nBack: \\done"}' \
    | "$SIGNAL" turn_end
_validate_jsonl "$JSONL" 2>/dev/null && _pass "JSONL still valid" || _fail "JSONL invalid after turn_end"
LAST_MSG="$(_last_field "$JSONL" last_message)"
[[ "$(_last_field "$JSONL" event)" == "turn_end" ]] && _pass "event=turn_end" || _fail "event != turn_end"
# The last_message must round-trip the embedded quotes/newlines/backslashes (we test the python-decoded string).
[[ "$LAST_MSG" == $'PR opened: https://x\nLine 2\nBack: \\done' ]] && _pass "last_message preserved (quotes/newlines/backslashes)" \
    || _fail "last_message corrupted: [$LAST_MSG]"

# ── Test 4: turn_end transcript fallback ─────────────────────────────────────

echo "Test 4: turn_end with transcript fallback (no last_assistant_message)"
TRANSCRIPT="${TEST_TMPDIR}/transcript.jsonl"
cat > "$TRANSCRIPT" <<'JSONL'
{"type":"user","message":{"content":"hi"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"intermediate"}]}}
{"type":"assistant","message":{"content":[{"type":"thinking","text":"hmm"},{"type":"text","text":"final reply text"}]}}
JSONL
printf '{"hook_event_name":"Stop","transcript_path":"%s"}' "$TRANSCRIPT" | "$SIGNAL" turn_end
[[ "$(_last_field "$JSONL" last_message)" == "final reply text" ]] && _pass "transcript fallback grabbed final text block" \
    || _fail "transcript fallback wrong: $(_last_field "$JSONL" last_message)"

# ── Test 5: turn_end with missing/malformed transcript → last_message:null ───

echo "Test 5: turn_end with missing transcript → last_message:null"
printf '{"hook_event_name":"Stop","transcript_path":"/no/such/path"}' | "$SIGNAL" turn_end
[[ "$(_last_field "$JSONL" last_message)" == "__NONE__" ]] && _pass "missing transcript → null" \
    || _fail "expected null, got [$(_last_field "$JSONL" last_message)]"

echo "Test 5b: turn_end with no input → last_message:null"
echo '{}' | "$SIGNAL" turn_end
[[ "$(_last_field "$JSONL" last_message)" == "__NONE__" ]] && _pass "no input → null" \
    || _fail "expected null"

# ── Test 6: exit (SessionEnd) ────────────────────────────────────────────────

echo "Test 6: exit event"
printf '{"hook_event_name":"SessionEnd","reason":"logout"}' | "$SIGNAL" exit
[[ "$(_last_field "$JSONL" event)" == "exit" ]] && _pass "event=exit" || _fail "event != exit"
[[ "$(_last_field "$JSONL" reason)" == "logout" ]] && _pass "reason captured" || _fail "reason missing"

# ── Test 7: exit 0 invariant on read-only signals dir ────────────────────────

echo "Test 7: exit 0 on read-only signals dir"
RO_DIR="${TEST_TMPDIR}/ro-signals"
mkdir -p "$RO_DIR"
chmod 555 "$RO_DIR"
RC=0
ASSETS_SIGNALS_DIR="$RO_DIR" "$SIGNAL" boot < /dev/null || RC=$?
[[ "$RC" -eq 0 ]] && _pass "boot exits 0 on RO dir" || _fail "boot exited $RC on RO dir"
RC=0
ASSETS_SIGNALS_DIR="$RO_DIR" "$SIGNAL" activity < /dev/null || RC=$?
[[ "$RC" -eq 0 ]] && _pass "activity exits 0 on RO dir" || _fail "activity exited $RC on RO dir"
RC=0
ASSETS_SIGNALS_DIR="$RO_DIR" "$SIGNAL" turn_end < /dev/null || RC=$?
[[ "$RC" -eq 0 ]] && _pass "turn_end exits 0 on RO dir" || _fail "turn_end exited $RC on RO dir"
chmod 755 "$RO_DIR"

# ── Test 8: exit 0 invariant on missing ASSETS_SIGNALS_DIR ───────────────────

echo "Test 8: exit 0 when ASSETS_SIGNALS_DIR unset"
RC=0
unset ASSETS_SIGNALS_DIR
"$SIGNAL" boot < /dev/null || RC=$?
[[ "$RC" -eq 0 ]] && _pass "no signals dir → exit 0" || _fail "no signals dir → exit $RC"

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
PASS=$(cat "$PASS_FILE")
FAIL=$(cat "$FAIL_FILE")
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
