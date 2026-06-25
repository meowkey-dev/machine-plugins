#!/usr/bin/env bash
# test_harness_signals.sh — verify dispatch-asset hook injection for claude-family
# launchers, and the gate on monitoring.harness_signals.
#
# Tests:
#   1. claude-family + harness_signals=true  → settings file generated with the 4
#      hooks, --settings passed to the launcher, ASSET_NAME/ASSETS_SIGNALS_DIR
#      exported to the launched process.
#   2. claude-family + harness_signals=false → no injection.
#   3. codex-family launcher                 → no injection (claude-only path).
#   4. ASSETS_HARNESS_SIGNALS=false env       → no injection (env override beats
#      default true).
#   5. --name override is used as ASSET_NAME and in the settings filename.
#   6. Settings JSON is valid JSON and shell-safely quotes the asset-signal path
#      when SIGNALS_DIR or plugin path contains a space.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
DISPATCH="${PLUGIN_DIR}/bin/dispatch-asset"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

PASS_FILE="${TEST_TMPDIR}/.pass"
FAIL_FILE="${TEST_TMPDIR}/.fail"
echo 0 > "$PASS_FILE"; echo 0 > "$FAIL_FILE"

_pass() { echo "  PASS: $1"; echo $(( $(cat "$PASS_FILE") + 1 )) > "$PASS_FILE"; }
_fail() { echo "  FAIL: $1"; echo $(( $(cat "$FAIL_FILE") + 1 )) > "$FAIL_FILE"; }

# Fake launcher: dumps its own argv AND a snapshot of the relevant env vars to
# files in its own bin dir, then exits 0. dispatch-asset exec's the launcher,
# so we get the post-injection view.
_make_launcher() {
    local name="$1" bin="$2"
    cat > "${bin}/${name}" <<'LAUNCHER'
#!/usr/bin/env bash
self="$0"
printf '%s\n' "$@" > "${self}.args"
{
    echo "ASSET_NAME=${ASSET_NAME-__unset__}"
    echo "ASSETS_SIGNALS_DIR=${ASSETS_SIGNALS_DIR-__unset__}"
} > "${self}.env"
LAUNCHER
    chmod +x "${bin}/${name}"
}

# Base repo with config (harness_signals defaults to true if not set).
_make_repo() {
    local repo="$1" hs="$2"
    mkdir -p "${repo}/.claude/assets"
    cat > "${repo}/.claude/assets/config.yaml" <<EOF
paths:
  workdir: ${TEST_TMPDIR}
  signals: ${TEST_TMPDIR}/signals

launchers:
  - command: fake-claude
    rule: "Claude family fake launcher."

features:
  rtk_aliases: false

monitoring:
  harness_signals: ${hs}
EOF
}

FAKE_BIN="${TEST_TMPDIR}/bin"
mkdir -p "$FAKE_BIN"
_make_launcher fake-claude "$FAKE_BIN"
_make_launcher fake-codex  "$FAKE_BIN"
export PATH="${FAKE_BIN}:${PATH}"

mkdir -p "${TEST_TMPDIR}/signals"
echo "hello" > "${TEST_TMPDIR}/prompt.txt"

# ── Test 1: claude-family + harness_signals=true → full injection ────────────

echo "Test 1: claude-family + harness_signals=true"
REPO1="${TEST_TMPDIR}/repo1"; _make_repo "$REPO1" true
(
    cd "$REPO1"
    rm -f "${FAKE_BIN}/fake-claude.args" "${FAKE_BIN}/fake-claude.env"
    "$DISPATCH" --launcher fake-claude --name pr-test1 --prompt "${TEST_TMPDIR}/prompt.txt" 2>/dev/null || true

    args="$(cat "${FAKE_BIN}/fake-claude.args" 2>/dev/null || true)"
    env_snap="$(cat "${FAKE_BIN}/fake-claude.env" 2>/dev/null || true)"
    settings_file="${TEST_TMPDIR}/signals/.settings/pr-test1.json"

    # 1a: --settings flag was passed
    if echo "$args" | grep -qx -- "--settings"; then
        _pass "--settings passed to launcher"
    else
        _fail "--settings missing from launcher args: $(echo "$args" | tr '\n' ' ')"
    fi

    # 1b: settings file points at the per-name file under signals/.settings
    if echo "$args" | grep -Fqx -- "$settings_file"; then
        _pass "--settings path points at ${settings_file}"
    else
        _fail "--settings path mismatch (expected ${settings_file}); args=$(echo "$args" | tr '\n' ' ')"
    fi

    # 1c: settings file exists and is valid JSON with all 4 hooks
    if [[ -f "$settings_file" ]]; then
        _pass "settings file exists"
        python3 -c "
import json,sys
d=json.load(open('$settings_file'))
hooks=d.get('hooks',{})
assert all(k in hooks for k in ('SessionStart','PostToolUse','Stop','SessionEnd')), hooks.keys()
assert 'asset-signal boot'     in json.dumps(hooks['SessionStart']), 'boot wiring'
assert 'asset-signal activity' in json.dumps(hooks['PostToolUse']),  'activity wiring'
assert 'asset-signal turn_end' in json.dumps(hooks['Stop']),         'turn_end wiring'
assert 'asset-signal exit'     in json.dumps(hooks['SessionEnd']),   'exit wiring'
# Stop does not take a matcher per current schema; the others should.
assert 'matcher' not in hooks['Stop'][0], 'Stop should not carry matcher'
assert 'matcher' in hooks['SessionStart'][0], 'SessionStart needs matcher'
assert 'matcher' in hooks['PostToolUse'][0],  'PostToolUse needs matcher'
assert 'matcher' in hooks['SessionEnd'][0],   'SessionEnd needs matcher'
" 2>/dev/null && _pass "settings JSON wires all 4 hooks to asset-signal with the right matchers" \
            || _fail "settings JSON wiring incorrect"
    else
        _fail "settings file not generated at ${settings_file}"
    fi

    # 1d: env vars exported
    if echo "$env_snap" | grep -qx "ASSET_NAME=pr-test1"; then
        _pass "ASSET_NAME exported to launcher"
    else
        _fail "ASSET_NAME wrong in env: $env_snap"
    fi
    if echo "$env_snap" | grep -qx "ASSETS_SIGNALS_DIR=${TEST_TMPDIR}/signals"; then
        _pass "ASSETS_SIGNALS_DIR exported to launcher"
    else
        _fail "ASSETS_SIGNALS_DIR wrong in env: $env_snap"
    fi
)

# ── Test 2: claude-family + harness_signals=false → no injection ─────────────

echo "Test 2: claude-family + harness_signals=false → no injection"
REPO2="${TEST_TMPDIR}/repo2"; _make_repo "$REPO2" false
(
    cd "$REPO2"
    rm -f "${FAKE_BIN}/fake-claude.args" "${FAKE_BIN}/fake-claude.env"
    "$DISPATCH" --launcher fake-claude --name no-inject --prompt "${TEST_TMPDIR}/prompt.txt" 2>/dev/null || true
    args="$(cat "${FAKE_BIN}/fake-claude.args" 2>/dev/null || true)"

    if echo "$args" | grep -qx -- "--settings"; then
        _fail "--settings unexpectedly present with harness_signals=false: $(echo "$args" | tr '\n' ' ')"
    else
        _pass "no --settings when harness_signals=false"
    fi
    [[ -f "${TEST_TMPDIR}/signals/.settings/no-inject.json" ]] \
        && _fail "settings file generated when harness_signals=false" \
        || _pass "no settings file generated when harness_signals=false"
)

# ── Test 3: codex-family → no injection regardless of harness_signals ────────

echo "Test 3: codex-family → no injection"
REPO3="${TEST_TMPDIR}/repo3"; _make_repo "$REPO3" true
(
    cd "$REPO3"
    rm -f "${FAKE_BIN}/fake-codex.args" "${FAKE_BIN}/fake-codex.env"
    "$DISPATCH" --launcher fake-codex --name codex-test --prompt "${TEST_TMPDIR}/prompt.txt" 2>/dev/null || true
    args="$(cat "${FAKE_BIN}/fake-codex.args" 2>/dev/null || true)"
    if echo "$args" | grep -qx -- "--settings"; then
        _fail "codex unexpectedly received --settings: $(echo "$args" | tr '\n' ' ')"
    else
        _pass "codex did not receive --settings"
    fi
    [[ -f "${TEST_TMPDIR}/signals/.settings/codex-test.json" ]] \
        && _fail "settings file generated for codex" \
        || _pass "no settings file generated for codex"
)

# ── Test 4: env override ASSETS_HARNESS_SIGNALS=false beats default true ─────

echo "Test 4: ASSETS_HARNESS_SIGNALS=false env override"
REPO4="${TEST_TMPDIR}/repo4"
# Config has NO monitoring.harness_signals line — default is true.
mkdir -p "${REPO4}/.claude/assets"
cat > "${REPO4}/.claude/assets/config.yaml" <<EOF
paths:
  workdir: ${TEST_TMPDIR}
  signals: ${TEST_TMPDIR}/signals

launchers:
  - command: fake-claude
    rule: "Claude family fake launcher."

features:
  rtk_aliases: false
EOF
(
    cd "$REPO4"
    rm -f "${FAKE_BIN}/fake-claude.args"
    ASSETS_HARNESS_SIGNALS=false "$DISPATCH" --launcher fake-claude --name env-off --prompt "${TEST_TMPDIR}/prompt.txt" 2>/dev/null || true
    args="$(cat "${FAKE_BIN}/fake-claude.args" 2>/dev/null || true)"
    if echo "$args" | grep -qx -- "--settings"; then
        _fail "env override ignored — --settings still passed"
    else
        _pass "ASSETS_HARNESS_SIGNALS=false suppresses injection"
    fi
)

# ── Test 5: default-on (no monitoring.harness_signals in config) ─────────────

echo "Test 5: default-on (no monitoring.harness_signals in config)"
(
    cd "$REPO4"
    rm -f "${FAKE_BIN}/fake-claude.args"
    "$DISPATCH" --launcher fake-claude --name default-on --prompt "${TEST_TMPDIR}/prompt.txt" 2>/dev/null || true
    args="$(cat "${FAKE_BIN}/fake-claude.args" 2>/dev/null || true)"
    if echo "$args" | grep -qx -- "--settings"; then
        _pass "default-on: --settings passed"
    else
        _fail "default-on: --settings should be passed (got $(echo "$args" | tr '\n' ' '))"
    fi
)

# ── Test 6: settings shell-quotes a path with spaces correctly ───────────────

echo "Test 6: settings file shell-quotes signals path with spaces"
SPACED_SIGNALS="${TEST_TMPDIR}/spaced signals"
REPO6="${TEST_TMPDIR}/repo6"
mkdir -p "${REPO6}/.claude/assets" "$SPACED_SIGNALS"
cat > "${REPO6}/.claude/assets/config.yaml" <<EOF
paths:
  workdir: ${TEST_TMPDIR}
  signals: ${SPACED_SIGNALS}

launchers:
  - command: fake-claude
    rule: "."

features:
  rtk_aliases: false

monitoring:
  harness_signals: true
EOF
(
    cd "$REPO6"
    rm -f "${FAKE_BIN}/fake-claude.args"
    "$DISPATCH" --launcher fake-claude --name spaced-test --prompt "${TEST_TMPDIR}/prompt.txt" 2>/dev/null || true
    settings_file="${SPACED_SIGNALS}/.settings/spaced-test.json"
    if [[ -f "$settings_file" ]]; then
        _pass "settings file written under spaced signals dir"
        # The hook command strings must remain valid JSON (no broken escapes).
        python3 -m json.tool "$settings_file" >/dev/null 2>&1 \
            && _pass "settings JSON valid even with spaces in path" \
            || _fail "settings JSON invalid with spaces in path"
    else
        _fail "settings file missing for spaced-signals path"
    fi
)

# ── Test 7: --name with path separators is sanitized (no traversal) ──────────

echo "Test 7: --name with path separators is sanitized"
(
    cd "$REPO1"
    rm -f "${FAKE_BIN}/fake-claude.args" "${FAKE_BIN}/fake-claude.env"
    # An attacker-controlled name attempting path traversal.
    EVIL_NAME='../../tmp/escape'
    "$DISPATCH" --launcher fake-claude --name "$EVIL_NAME" --prompt "${TEST_TMPDIR}/prompt.txt" 2>/dev/null || true

    # Expected sanitized name: slashes → underscores
    sanitized="${EVIL_NAME//\//_}"
    expected="${TEST_TMPDIR}/signals/.settings/${sanitized}.json"
    escaped_path="${TEST_TMPDIR}/tmp/escape.json"

    if [[ -f "$expected" ]]; then
        _pass "settings written to sanitized path inside signals dir"
    else
        _fail "expected sanitized settings file at $expected"
    fi
    if [[ -f "$escaped_path" ]]; then
        _fail "PATH TRAVERSAL: settings escaped to $escaped_path"
        rm -f "$escaped_path"
    else
        _pass "no settings file escaped to $escaped_path"
    fi

    env_snap="$(cat "${FAKE_BIN}/fake-claude.env" 2>/dev/null || true)"
    if echo "$env_snap" | grep -qx "ASSET_NAME=$sanitized"; then
        _pass "ASSET_NAME exported as sanitized value"
    else
        _fail "ASSET_NAME not sanitized: $env_snap"
    fi
)

# ── Test 8: warn + no inject + still launches when SIGNALS_DIR unresolved ────

# Repro of the controller-pane-boundary trap (#155 manual test): dispatch-asset
# runs in the asset pane with cwd=workdir, so the controller's repo-local
# config is invisible — paths.signals can resolve empty. Without the SKILL's
# env-prefix passthrough, the injection block would silently no-op. The fix:
# warn loudly on stderr, skip injection, still launch.
echo "Test 8: harness_signals=true + empty SIGNALS_DIR → warning, no settings, still launches"
REPO8="${TEST_TMPDIR}/repo8"
mkdir -p "${REPO8}/.claude/assets"
# Config has harness_signals=true but no paths.signals — and we override HOME so
# the global ~/.claude/plugins/assets/config.yaml fallback is also absent.
cat > "${REPO8}/.claude/assets/config.yaml" <<EOF
paths:
  workdir: ${TEST_TMPDIR}

launchers:
  - command: fake-claude
    rule: "Claude family."

features:
  rtk_aliases: false

monitoring:
  harness_signals: true
EOF
(
    cd "$REPO8"
    rm -f "${FAKE_BIN}/fake-claude.args" "${FAKE_BIN}/fake-claude.env"
    # HOME override → no global config; unset env → no env-level signals dir.
    unset ASSETS_SIGNALS_DIR ASSETS_HARNESS_SIGNALS
    stderr_out="$(HOME="${TEST_TMPDIR}/fake-home" "$DISPATCH" --launcher fake-claude --name unresolved --prompt "${TEST_TMPDIR}/prompt.txt" 2>&1 >/dev/null)" || true
    args="$(cat "${FAKE_BIN}/fake-claude.args" 2>/dev/null || true)"

    if echo "$stderr_out" | grep -qi "harness signals enabled but paths.signals unresolved"; then
        _pass "warns on stderr when signals dir unresolved"
    else
        _fail "expected stderr warning, got: $stderr_out"
    fi
    if echo "$args" | grep -qx -- "--settings"; then
        _fail "should NOT have passed --settings when SIGNALS_DIR is empty"
    else
        _pass "no --settings injected when SIGNALS_DIR is empty"
    fi
    if [[ -f "${FAKE_BIN}/fake-claude.args" ]]; then
        _pass "launch still proceeds despite missing signals dir"
    else
        _fail "launcher was not invoked at all"
    fi
)

# ── Test 9: env-prefix passthrough (the SKILL Step 9 contract) ───────────────

# When the controller prefixes the send-keys with ASSETS_SIGNALS_DIR /
# ASSETS_HARNESS_SIGNALS, dispatch-asset must see them and inject normally
# even when no repo-local / global config is reachable from the pane's cwd.
echo "Test 9: env-prefix passthrough lets injection succeed across pane boundary"
(
    cd "$REPO8"
    rm -f "${FAKE_BIN}/fake-claude.args" "${FAKE_BIN}/fake-claude.env"
    ENV_SIGNALS="${TEST_TMPDIR}/env-signals"
    mkdir -p "$ENV_SIGNALS"
    stderr_out="$(HOME="${TEST_TMPDIR}/fake-home" \
        ASSETS_SIGNALS_DIR="$ENV_SIGNALS" \
        ASSETS_HARNESS_SIGNALS=true \
        "$DISPATCH" --launcher fake-claude --name env-passthrough --prompt "${TEST_TMPDIR}/prompt.txt" 2>&1 >/dev/null)" || true

    args="$(cat "${FAKE_BIN}/fake-claude.args" 2>/dev/null || true)"
    settings_file="${ENV_SIGNALS}/.settings/env-passthrough.json"

    if echo "$args" | grep -qx -- "--settings"; then
        _pass "env-prefix passthrough → --settings injected"
    else
        _fail "expected injection via env, args=$(echo "$args" | tr '\n' ' ') stderr=$stderr_out"
    fi
    [[ -f "$settings_file" ]] && _pass "settings file written under env-supplied signals dir" \
        || _fail "settings file missing at $settings_file"
    if echo "$stderr_out" | grep -qi "harness signals enabled but paths.signals unresolved"; then
        _fail "spurious 'unresolved' warning when env-prefix supplied it"
    else
        _pass "no spurious warning when env-prefix supplied SIGNALS_DIR"
    fi
)

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
PASS=$(cat "$PASS_FILE")
FAIL=$(cat "$FAIL_FILE")
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
