#!/usr/bin/env bash
# test_yolo_flag.sh — verify per-launcher bypass flag selection in dispatch-asset
#
# Tests:
#   1. claude-family launcher (*laude*) → --dangerously-skip-permissions
#   2. codex-family launcher (*odex*) → --dangerously-bypass-approvals-and-sandbox
#   3. --safe flag → no bypass flag for any launcher
#   4. unknown launcher → no claude flag leaked, warn on stderr

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
DISPATCH="${PLUGIN_DIR}/bin/dispatch-asset"

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

# Write a minimal config so dispatch-asset can load it
mkdir -p "${TEST_TMPDIR}/repo/.claude/assets"
cat > "${TEST_TMPDIR}/repo/.claude/assets/config.yaml" <<EOF
paths:
  workdir: ${TEST_TMPDIR}
  signals: ${TEST_TMPDIR}/signals

launchers:
  - command: fake-claude
    rule: "Claude family fake launcher."

features:
  rtk_aliases: false
EOF
mkdir -p "${TEST_TMPDIR}/signals"

# Create fake launchers that write their argv to a file then exit 0.
# dispatch-asset exec's the launcher, so these must be real executables.
FAKE_BIN="${TEST_TMPDIR}/bin"
mkdir -p "$FAKE_BIN"

# fake-claude — matches *laude*
cat > "${FAKE_BIN}/fake-claude" <<'LAUNCHER'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$(dirname "$0")/fake-claude.args"
LAUNCHER
chmod +x "${FAKE_BIN}/fake-claude"

# rlaude — variant name, still matches *laude*
cat > "${FAKE_BIN}/rlaude" <<'LAUNCHER'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$(dirname "$0")/rlaude.args"
LAUNCHER
chmod +x "${FAKE_BIN}/rlaude"

# fake-codex — matches *odex*
cat > "${FAKE_BIN}/fake-codex" <<'LAUNCHER'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$(dirname "$0")/fake-codex.args"
LAUNCHER
chmod +x "${FAKE_BIN}/fake-codex"

# unknown-launcher — no family match
cat > "${FAKE_BIN}/unknown-launcher" <<'LAUNCHER'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$(dirname "$0")/unknown-launcher.args"
LAUNCHER
chmod +x "${FAKE_BIN}/unknown-launcher"

export PATH="${FAKE_BIN}:${PATH}"

echo "hello" > "${TEST_TMPDIR}/prompt.txt"

# ── Test 1: claude-family launcher → --dangerously-skip-permissions ──────────

echo "Test 1: claude-family launcher (fake-claude) → --dangerously-skip-permissions"

(
    cd "${TEST_TMPDIR}/repo"
    rm -f "${FAKE_BIN}/fake-claude.args"
    "$DISPATCH" --launcher fake-claude --prompt "${TEST_TMPDIR}/prompt.txt" 2>/dev/null || true
    args="$(cat "${FAKE_BIN}/fake-claude.args" 2>/dev/null || true)"
    if echo "$args" | grep -qx -- "--dangerously-skip-permissions"; then
        _pass "fake-claude received --dangerously-skip-permissions"
    else
        _fail "fake-claude args missing --dangerously-skip-permissions: $(echo "$args" | tr '\n' ' ')"
    fi
    if echo "$args" | grep -qx -- "--dangerously-bypass-approvals-and-sandbox"; then
        _fail "fake-claude unexpectedly received codex bypass flag"
    else
        _pass "fake-claude did not receive codex bypass flag"
    fi
)

# ── Test 1b: variant claude-family name (rlaude) ─────────────────────────────

echo "Test 1b: claude-family variant name (rlaude) → --dangerously-skip-permissions"

(
    cd "${TEST_TMPDIR}/repo"
    rm -f "${FAKE_BIN}/rlaude.args"
    "$DISPATCH" --launcher rlaude --prompt "${TEST_TMPDIR}/prompt.txt" 2>/dev/null || true
    args="$(cat "${FAKE_BIN}/rlaude.args" 2>/dev/null || true)"
    if echo "$args" | grep -qx -- "--dangerously-skip-permissions"; then
        _pass "rlaude received --dangerously-skip-permissions"
    else
        _fail "rlaude args missing --dangerously-skip-permissions: $(echo "$args" | tr '\n' ' ')"
    fi
)

# ── Test 2: codex-family launcher → --dangerously-bypass-approvals-and-sandbox

echo "Test 2: codex-family launcher (fake-codex) → --dangerously-bypass-approvals-and-sandbox"

(
    cd "${TEST_TMPDIR}/repo"
    rm -f "${FAKE_BIN}/fake-codex.args"
    "$DISPATCH" --launcher fake-codex --prompt "${TEST_TMPDIR}/prompt.txt" 2>/dev/null || true
    args="$(cat "${FAKE_BIN}/fake-codex.args" 2>/dev/null || true)"
    if echo "$args" | grep -qx -- "--dangerously-bypass-approvals-and-sandbox"; then
        _pass "fake-codex received --dangerously-bypass-approvals-and-sandbox"
    else
        _fail "fake-codex args missing --dangerously-bypass-approvals-and-sandbox: $(echo "$args" | tr '\n' ' ')"
    fi
    if echo "$args" | grep -qx -- "--dangerously-skip-permissions"; then
        _fail "fake-codex unexpectedly received --dangerously-skip-permissions"
    else
        _pass "fake-codex did not receive --dangerously-skip-permissions"
    fi
)

# ── Test 3: --safe → no bypass flag for any launcher ─────────────────────────

echo "Test 3: --safe → no bypass flag for any launcher"

for launcher_name in fake-claude fake-codex; do
    (
        cd "${TEST_TMPDIR}/repo"
        args_file="${FAKE_BIN}/${launcher_name}.args"
        rm -f "$args_file"
        "$DISPATCH" --launcher "$launcher_name" --safe --prompt "${TEST_TMPDIR}/prompt.txt" 2>/dev/null || true
        args="$(cat "$args_file" 2>/dev/null || true)"
        if echo "$args" | grep -qx -- "--dangerously-skip-permissions" || echo "$args" | grep -qx -- "--dangerously-bypass-approvals-and-sandbox"; then
            _fail "$launcher_name with --safe still got a bypass flag: $(echo "$args" | tr '\n' ' ')"
        else
            _pass "$launcher_name with --safe: no bypass flag"
        fi
    )
done

# ── Test 4: unknown launcher → no claude flag leaked, warn on stderr ─────────

echo "Test 4: unknown launcher → no --dangerously-skip-permissions leaked, warn on stderr"

(
    cd "${TEST_TMPDIR}/repo"
    rm -f "${FAKE_BIN}/unknown-launcher.args"
    stderr_out="$("$DISPATCH" --launcher unknown-launcher --prompt "${TEST_TMPDIR}/prompt.txt" 2>&1 >/dev/null)" || true
    args="$(cat "${FAKE_BIN}/unknown-launcher.args" 2>/dev/null || true)"

    if echo "$args" | grep -qx -- "--dangerously-skip-permissions"; then
        _fail "unknown-launcher received --dangerously-skip-permissions (bug: claude flag leaked)"
    else
        _pass "unknown-launcher: no --dangerously-skip-permissions leaked"
    fi
    if echo "$args" | grep -qx -- "--dangerously-bypass-approvals-and-sandbox"; then
        _fail "unknown-launcher received codex bypass flag"
    else
        _pass "unknown-launcher: no codex bypass flag"
    fi
    if echo "$stderr_out" | grep -q "unknown launcher family"; then
        _pass "unknown-launcher: warning emitted on stderr"
    else
        _fail "unknown-launcher: expected stderr warning, got: $stderr_out"
    fi
)

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
PASS=$(cat "$PASS_FILE")
FAIL=$(cat "$FAIL_FILE")
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
