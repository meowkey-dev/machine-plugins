#!/usr/bin/env bash
# test_ensure_forward.sh — exercises ensure-tmux-forward against ssh localhost as loopback remote
#
# Tests:
#   1. No tmux.remote configured → exit 0 (no-op, Case 1 parity)
#   2. Idempotent: 10 calls → exactly 1 SSH process
#   3. Stale pidfile reap: dead pidfile is cleaned up, new forward spawns
#   4. Clean error on bogus host
#
# Requires: ssh localhost working (key-based auth, no password prompt).
# Skips gracefully if ssh localhost is unavailable.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
ENSURE_FWD="${PLUGIN_DIR}/bin/ensure-tmux-forward"

cleanup() {
    if [[ -n "${TEST_TMPDIR:-}" ]] && [[ -d "$TEST_TMPDIR" ]]; then
        if [[ -f "${TEST_TMPDIR}/fwd.sock.pid" ]]; then
            kill "$(cat "${TEST_TMPDIR}/fwd.sock.pid")" 2>/dev/null || true
        fi
        tmux -S "${TEST_TMPDIR}/tmux.sock" kill-server 2>/dev/null || true
        rm -rf "$TEST_TMPDIR"
    fi
}
trap cleanup EXIT

TEST_TMPDIR="$(mktemp -d)"

PASS_FILE="${TEST_TMPDIR}/.pass"
FAIL_FILE="${TEST_TMPDIR}/.fail"
SKIP_FILE="${TEST_TMPDIR}/.skip"
echo 0 > "$PASS_FILE"; echo 0 > "$FAIL_FILE"; echo 0 > "$SKIP_FILE"

_pass() {
    echo "  PASS: $1"
    echo $(( $(cat "$PASS_FILE") + 1 )) > "$PASS_FILE"
}
_fail() {
    echo "  FAIL: $1"
    echo $(( $(cat "$FAIL_FILE") + 1 )) > "$FAIL_FILE"
}
_skip() {
    echo "  SKIP: $1"
    echo $(( $(cat "$SKIP_FILE") + 1 )) > "$SKIP_FILE"
}
_summary() {
    echo ""
    echo "Results: $(cat "$PASS_FILE") passed, $(cat "$FAIL_FILE") failed, $(cat "$SKIP_FILE") skipped"
    [[ "$(cat "$FAIL_FILE")" -eq 0 ]] && exit 0 || exit 1
}

# ── Test 1: no remote configured → no-op ────────────────────────────────────

echo "Test 1: no tmux.remote → exit 0 (Case 1 parity)"

mkdir -p "${TEST_TMPDIR}/test1-repo/.claude/assets"
cat > "${TEST_TMPDIR}/test1-repo/.claude/assets/config.yaml" <<'EOF'
tmux:
  socket: /tmp/test-no-remote.sock
  session: assets

paths:
  workdir: /tmp
  signals: /tmp/signals
EOF

(
    cd "${TEST_TMPDIR}/test1-repo"
    output="$("$ENSURE_FWD" 2>&1)" && rc=0 || rc=$?
    if [[ $rc -eq 0 ]] && [[ -z "$output" ]]; then
        _pass "no-op exit 0 with no output"
    else
        _fail "expected exit 0 with no output, got rc=$rc output='$output'"
    fi
)

# ── Check ssh localhost availability for remaining tests ─────────────────────

echo ""
echo "Checking ssh localhost availability..."
if ! ssh -o BatchMode=yes -o ConnectTimeout=3 localhost true 2>/dev/null; then
    echo "ssh localhost unavailable — skipping Case 2 tests"
    _skip "idempotent forward (ssh localhost unavailable)"
    _skip "stale pidfile reap (ssh localhost unavailable)"

    echo ""
    echo "Test 4: bogus host → clean error"
    mkdir -p "${TEST_TMPDIR}/test4-repo/.claude/assets"
    cat > "${TEST_TMPDIR}/test4-repo/.claude/assets/config.yaml" <<EOF
tmux:
  socket: ${TEST_TMPDIR}/bogus-fwd.sock
  session: assets
  remote:
    host: this-host-does-not-exist-12345.invalid
    socket: /tmp/tmux.sock

paths:
  workdir: /tmp
  signals: /tmp/signals
EOF

    (
        cd "${TEST_TMPDIR}/test4-repo"
        output="$("$ENSURE_FWD" 2>&1)" && rc=0 || rc=$?
        if [[ $rc -ne 0 ]] && echo "$output" | grep -q "ensure-tmux-forward: error:"; then
            if ! echo "$output" | grep -qE '(Traceback|line [0-9]+)'; then
                _pass "clean one-line error on bogus host"
            else
                _fail "error contains stack trace: $output"
            fi
        else
            _fail "expected non-zero exit with clean error, got rc=$rc output='$output'"
        fi
    )

    _summary
fi

echo "ssh localhost OK"

# ── Set up loopback tmux server ──────────────────────────────────────────────

REMOTE_SOCKET="${TEST_TMPDIR}/tmux.sock"
tmux -S "$REMOTE_SOCKET" new-session -d -s assets 2>/dev/null || {
    echo "Cannot start tmux server — skipping Case 2 tests"
    _skip "idempotent forward"
    _skip "stale pidfile reap"
    _summary
}

FWD_SOCKET="${TEST_TMPDIR}/fwd.sock"

mkdir -p "${TEST_TMPDIR}/test2-repo/.claude/assets"
cat > "${TEST_TMPDIR}/test2-repo/.claude/assets/config.yaml" <<EOF
tmux:
  socket: ${FWD_SOCKET}
  session: assets
  remote:
    host: localhost
    socket: ${REMOTE_SOCKET}

paths:
  workdir: /tmp
  signals: /tmp/signals
EOF

# ── Test 2: idempotent — 10 calls → 1 SSH process ───────────────────────────

echo ""
echo "Test 2: idempotent — 10 calls → 1 SSH process"

(
    cd "${TEST_TMPDIR}/test2-repo"
    for i in $(seq 1 10); do
        "$ENSURE_FWD" 2>&1 || { _fail "ensure-tmux-forward failed on call $i"; exit 1; }
    done

    ssh_count="$(pgrep -fc "ssh.*-L.*${FWD_SOCKET}:${REMOTE_SOCKET}.*localhost" 2>/dev/null)" || ssh_count=0
    if [[ "$ssh_count" -eq 1 ]]; then
        _pass "10 calls → exactly 1 SSH process"
    else
        _fail "expected 1 SSH process, found $ssh_count"
    fi
)

# ── Test 3: stale pidfile reap ───────────────────────────────────────────────

echo ""
echo "Test 3: stale pidfile reap"

(
    cd "${TEST_TMPDIR}/test2-repo"

    if [[ -f "${FWD_SOCKET}.pid" ]]; then
        kill "$(cat "${FWD_SOCKET}.pid")" 2>/dev/null || true
        sleep 0.5
    fi

    "$ENSURE_FWD" 2>&1 || { _fail "ensure-tmux-forward failed after killing SSH"; exit 1; }

    new_count="$(pgrep -fc "ssh.*-L.*${FWD_SOCKET}:${REMOTE_SOCKET}.*localhost" 2>/dev/null)" || new_count=0
    if [[ "$new_count" -eq 1 ]]; then
        _pass "stale pidfile reaped, new forward spawned (1 process)"
    else
        _fail "expected 1 SSH process after reap, found $new_count"
    fi
)

# ── Test 4: clean error on bogus host ────────────────────────────────────────

echo ""
echo "Test 4: bogus host → clean error"

if [[ -f "${FWD_SOCKET}.pid" ]]; then
    kill "$(cat "${FWD_SOCKET}.pid")" 2>/dev/null || true
fi

mkdir -p "${TEST_TMPDIR}/test4-repo/.claude/assets"
cat > "${TEST_TMPDIR}/test4-repo/.claude/assets/config.yaml" <<EOF
tmux:
  socket: ${TEST_TMPDIR}/bogus-fwd.sock
  session: assets
  remote:
    host: this-host-does-not-exist-12345.invalid
    socket: /tmp/tmux.sock

paths:
  workdir: /tmp
  signals: /tmp/signals
EOF

(
    cd "${TEST_TMPDIR}/test4-repo"
    output="$("$ENSURE_FWD" 2>&1)" && rc=0 || rc=$?
    if [[ $rc -ne 0 ]] && echo "$output" | grep -q "ensure-tmux-forward: error:"; then
        if ! echo "$output" | grep -qE '(Traceback|line [0-9]+)'; then
            _pass "clean one-line error on bogus host"
        else
            _fail "error contains stack trace: $output"
        fi
    else
        _fail "expected non-zero exit with clean error, got rc=$rc output='$output'"
    fi
)

_summary
