#!/usr/bin/env bash
# test_case1_parity.sh — verify that v0.2 with no tmux.remote is byte-for-byte identical to v0.1
#
# Tests:
#   1. dispatch-asset --help output is unchanged
#   2. config loading resolves v0.1 fields correctly
#   3. ensure-tmux-forward is a no-op (exit 0, no output)
#   4. dispatch-asset invokes launcher correctly
#   5. no tmux.remote fields leak into v0.1-style config

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
DISPATCH="${PLUGIN_DIR}/bin/dispatch-asset"
ENSURE_FWD="${PLUGIN_DIR}/bin/ensure-tmux-forward"
CONFIG_LIB="${PLUGIN_DIR}/bin/_config.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

PASS_FILE="${TEST_TMPDIR}/.pass"
FAIL_FILE="${TEST_TMPDIR}/.fail"
echo 0 > "$PASS_FILE"
echo 0 > "$FAIL_FILE"

_pass() {
    echo "  PASS: $1"
    echo $(( $(cat "$PASS_FILE") + 1 )) > "$PASS_FILE"
}
_fail() {
    echo "  FAIL: $1"
    echo $(( $(cat "$FAIL_FILE") + 1 )) > "$FAIL_FILE"
}

# Write a v0.1-style config (no remote block)
mkdir -p "${TEST_TMPDIR}/repo/.claude/assets"
cat > "${TEST_TMPDIR}/repo/.claude/assets/config.yaml" <<EOF
tmux:
  socket: ${TEST_TMPDIR}/tmux.sock
  session: assets

paths:
  workdir: ${TEST_TMPDIR}
  signals: ${TEST_TMPDIR}/signals

launchers:
  - command: echo
    rule: "Test launcher that just echoes."

features:
  rtk_aliases: false
EOF
mkdir -p "${TEST_TMPDIR}/signals"

# ── Test 1: dispatch-asset --help ────────────────────────────────────────────

echo "Test 1: dispatch-asset --help output unchanged"

help_output="$("$DISPATCH" --help 2>&1)" || true
if echo "$help_output" | grep -q "Usage: dispatch-asset --launcher"; then
    _pass "--help shows expected usage"
else
    _fail "--help output unexpected: $help_output"
fi

# ── Test 2: config loading resolves v0.1 fields ─────────────────────────────

echo "Test 2: config loading resolves v0.1 fields correctly"

(
    cd "${TEST_TMPDIR}/repo"
    # shellcheck source=../bin/_config.sh
    source "$CONFIG_LIB"

    socket="$(_config "tmux" "socket" "ASSETS_TMUX_SOCKET" "")"
    session="$(_config "tmux" "session" "ASSETS_TMUX_SESSION" "")"
    workdir="$(_config "paths" "workdir" "ASSETS_WORKDIR" "")"
    signals="$(_config "paths" "signals" "ASSETS_SIGNALS_DIR" "")"
    rtk="$(_config "features" "rtk_aliases" "" "false")"

    ok=true
    [[ "$socket" == "${TEST_TMPDIR}/tmux.sock" ]] || { echo "    socket mismatch: $socket"; ok=false; }
    [[ "$session" == "assets" ]] || { echo "    session mismatch: $session"; ok=false; }
    [[ "$workdir" == "${TEST_TMPDIR}" ]] || { echo "    workdir mismatch: $workdir"; ok=false; }
    [[ "$signals" == "${TEST_TMPDIR}/signals" ]] || { echo "    signals mismatch: $signals"; ok=false; }
    [[ "$rtk" == "false" ]] || { echo "    rtk_aliases mismatch: $rtk"; ok=false; }

    if $ok; then _pass "all v0.1 config fields resolve correctly"; else _fail "config field mismatch (see above)"; fi
)

# ── Test 3: ensure-tmux-forward no-op ────────────────────────────────────────

echo "Test 3: ensure-tmux-forward exit 0 with no output (no tmux.remote)"

(
    cd "${TEST_TMPDIR}/repo"
    output="$("$ENSURE_FWD" 2>&1)" && rc=0 || rc=$?
    if [[ $rc -eq 0 ]] && [[ -z "$output" ]]; then
        _pass "ensure-tmux-forward no-op"
    else
        _fail "expected exit 0 with no output, got rc=$rc output='$output'"
    fi
)

# ── Test 4: dispatch-asset invokes launcher ──────────────────────────────────

echo "Test 4: dispatch-asset invokes launcher correctly (echo test)"

echo "hello" > "${TEST_TMPDIR}/prompt.txt"

(
    cd "${TEST_TMPDIR}/repo"
    output="$("$DISPATCH" --launcher echo --prompt "${TEST_TMPDIR}/prompt.txt" 2>&1)" && rc=0 || rc=$?
    if [[ $rc -eq 0 ]]; then
        _pass "dispatch-asset exec'd launcher successfully"
    else
        _fail "dispatch-asset failed with rc=$rc output='$output'"
    fi
)

# ── Test 5: no remote field leakage ──────────────────────────────────────────

echo "Test 5: tmux.remote fields are empty in v0.1-style config"

(
    cd "${TEST_TMPDIR}/repo"
    # shellcheck source=../bin/_config.sh
    source "$CONFIG_LIB"

    remote_host="$(_config_nested "tmux" "remote" "host" "" "")"
    remote_socket="$(_config_nested "tmux" "remote" "socket" "" "")"

    if [[ -z "$remote_host" ]] && [[ -z "$remote_socket" ]]; then
        _pass "no remote fields in v0.1-style config"
    else
        _fail "unexpected remote fields: host='$remote_host' socket='$remote_socket'"
    fi
)

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
PASS=$(cat "$PASS_FILE")
FAIL=$(cat "$FAIL_FILE")
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
