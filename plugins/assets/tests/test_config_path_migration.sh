#!/usr/bin/env bash
# test_config_path_migration.sh — config-path resolution in _config.sh (issue #127)
#
# Tests the walk-up loop in _config.sh that resolves LOCAL_CONFIG:
#   1. New canonical path .claude/assets/config.yaml resolves.
#   2. Legacy .assets/config.yaml resolves AND emits the stderr deprecation warning.
#   3. When both exist, the new path wins and NO warning is emitted.
#   4. Nested cwd: the loop walks up to find a config in an ancestor dir.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_SH="${PLUGIN_DIR}/bin/_config.sh"

cleanup() {
    if [[ -n "${TEST_TMPDIR:-}" ]] && [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}
trap cleanup EXIT

TEST_TMPDIR="$(mktemp -d)"

PASS_FILE="${TEST_TMPDIR}/.pass"
FAIL_FILE="${TEST_TMPDIR}/.fail"
echo 0 > "$PASS_FILE"; echo 0 > "$FAIL_FILE"

_pass() {
    echo "  PASS: $1"
    echo $(( $(cat "$PASS_FILE") + 1 )) > "$PASS_FILE"
}
_fail() {
    echo "  FAIL: $1"
    echo $(( $(cat "$FAIL_FILE") + 1 )) > "$FAIL_FILE"
}
_summary() {
    echo ""
    echo "Results: $(cat "$PASS_FILE") passed, $(cat "$FAIL_FILE") failed"
    [[ "$(cat "$FAIL_FILE")" -eq 0 ]] && exit 0 || exit 1
}

# Source _config.sh in a clean subshell with a pinned cwd. Echoes
# "LOCAL_CONFIG=<path>" on stdout; the loader's warning goes to stderr.
# We capture stdout and stderr separately so we can assert on each.
_resolve() {
    local cwd="$1" stdout_file="$2" stderr_file="$3"
    (
        # Pin HOME so the global path can't accidentally match anything real.
        export HOME="${TEST_TMPDIR}/fake-home"
        export ASSETS_CONFIG_CWD="$cwd"
        # shellcheck disable=SC1090
        source "$CONFIG_SH"
        echo "LOCAL_CONFIG=${LOCAL_CONFIG}"
    ) >"$stdout_file" 2>"$stderr_file"
}

WARN_RE="using legacy .* move to .* at your leisure"

# ── Test 1: new canonical path resolves ──────────────────────────────────────

echo "Test 1: .claude/assets/config.yaml resolves"
REPO1="${TEST_TMPDIR}/repo1"
mkdir -p "${REPO1}/.claude/assets"
echo "tmux: {}" > "${REPO1}/.claude/assets/config.yaml"

_resolve "$REPO1" "${TEST_TMPDIR}/t1.out" "${TEST_TMPDIR}/t1.err"
if grep -qx "LOCAL_CONFIG=${REPO1}/.claude/assets/config.yaml" "${TEST_TMPDIR}/t1.out"; then
    _pass "resolved to new canonical path"
else
    _fail "expected new path, got: $(cat "${TEST_TMPDIR}/t1.out")"
fi
if [[ -s "${TEST_TMPDIR}/t1.err" ]] && grep -qE "$WARN_RE" "${TEST_TMPDIR}/t1.err"; then
    _fail "unexpected deprecation warning on new path: $(cat "${TEST_TMPDIR}/t1.err")"
else
    _pass "no deprecation warning on new path"
fi

# ── Test 2: legacy path resolves + warns ─────────────────────────────────────

echo ""
echo "Test 2: legacy .assets/config.yaml resolves with deprecation warning"
REPO2="${TEST_TMPDIR}/repo2"
mkdir -p "${REPO2}/.assets"
echo "tmux: {}" > "${REPO2}/.assets/config.yaml"

_resolve "$REPO2" "${TEST_TMPDIR}/t2.out" "${TEST_TMPDIR}/t2.err"
if grep -qx "LOCAL_CONFIG=${REPO2}/.assets/config.yaml" "${TEST_TMPDIR}/t2.out"; then
    _pass "resolved to legacy path"
else
    _fail "expected legacy path, got: $(cat "${TEST_TMPDIR}/t2.out")"
fi
if grep -qE "$WARN_RE" "${TEST_TMPDIR}/t2.err"; then
    _pass "deprecation warning emitted to stderr"
else
    _fail "expected deprecation warning, stderr was: $(cat "${TEST_TMPDIR}/t2.err")"
fi

# ── Test 3: both present → new wins, no warning ──────────────────────────────

echo ""
echo "Test 3: both paths present → new wins, no warning"
REPO3="${TEST_TMPDIR}/repo3"
mkdir -p "${REPO3}/.claude/assets" "${REPO3}/.assets"
echo "tmux: {}" > "${REPO3}/.claude/assets/config.yaml"
echo "tmux: {}" > "${REPO3}/.assets/config.yaml"

_resolve "$REPO3" "${TEST_TMPDIR}/t3.out" "${TEST_TMPDIR}/t3.err"
if grep -qx "LOCAL_CONFIG=${REPO3}/.claude/assets/config.yaml" "${TEST_TMPDIR}/t3.out"; then
    _pass "new path wins over legacy"
else
    _fail "expected new path to win, got: $(cat "${TEST_TMPDIR}/t3.out")"
fi
if grep -qE "$WARN_RE" "${TEST_TMPDIR}/t3.err"; then
    _fail "unexpected deprecation warning when new path present: $(cat "${TEST_TMPDIR}/t3.err")"
else
    _pass "no deprecation warning when new path present"
fi

# ── Test 4: walk up from a nested cwd ────────────────────────────────────────

echo ""
echo "Test 4: nested cwd walks up to ancestor config"
REPO4="${TEST_TMPDIR}/repo4"
mkdir -p "${REPO4}/.claude/assets" "${REPO4}/src/deep/nested"
echo "tmux: {}" > "${REPO4}/.claude/assets/config.yaml"

_resolve "${REPO4}/src/deep/nested" "${TEST_TMPDIR}/t4.out" "${TEST_TMPDIR}/t4.err"
if grep -qx "LOCAL_CONFIG=${REPO4}/.claude/assets/config.yaml" "${TEST_TMPDIR}/t4.out"; then
    _pass "walked up from nested cwd to find config"
else
    _fail "expected ancestor config, got: $(cat "${TEST_TMPDIR}/t4.out")"
fi
if grep -qE "$WARN_RE" "${TEST_TMPDIR}/t4.err"; then
    _fail "unexpected deprecation warning during walk-up: $(cat "${TEST_TMPDIR}/t4.err")"
else
    _pass "no deprecation warning during walk-up"
fi

_summary
