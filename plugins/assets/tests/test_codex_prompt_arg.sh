#!/usr/bin/env bash
# test_codex_prompt_arg.sh — verify Codex-family launchers keep stdin as the TTY/input stream
#
# Codex interactive mode refuses to start if stdin is redirected away from the tmux pane. The
# dispatch shim must pass prompt-file contents as a positional prompt argument for Codex-family
# launchers instead of using stdin redirection.

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

mkdir -p "${TEST_TMPDIR}/repo/.claude/assets" "${TEST_TMPDIR}/signals" "${TEST_TMPDIR}/bin"
cat > "${TEST_TMPDIR}/repo/.claude/assets/config.yaml" <<EOF
paths:
  workdir: ${TEST_TMPDIR}
  signals: ${TEST_TMPDIR}/signals

features:
  rtk_aliases: false
EOF

cat > "${TEST_TMPDIR}/bin/fake-codex" <<'LAUNCHER'
#!/usr/bin/env bash
{
    printf 'argc=%s\n' "$#"
    i=0
    for arg in "$@"; do
        i=$((i + 1))
        printf 'arg%d_sha=%s\n' "$i" "$(printf '%s' "$arg" | sha256sum | awk '{print $1}')"
    done
} > "$(dirname "$0")/fake-codex.args"

if IFS= read -r -t 0.1 line; then
    printf '%s\n' "$line" > "$(dirname "$0")/fake-codex.stdin"
else
    : > "$(dirname "$0")/fake-codex.stdin"
fi
LAUNCHER
chmod +x "${TEST_TMPDIR}/bin/fake-codex"
export PATH="${TEST_TMPDIR}/bin:${PATH}"

PROMPT_CONTENT=$'- first line\nsecond line'
printf '%s\n' "$PROMPT_CONTENT" > "${TEST_TMPDIR}/prompt.txt"

echo "Test 1: codex-family launcher receives prompt as positional argument"

(
    cd "${TEST_TMPDIR}/repo"
    "$DISPATCH" --launcher fake-codex --prompt "${TEST_TMPDIR}/prompt.txt" < /dev/null
)

args="$(cat "${TEST_TMPDIR}/bin/fake-codex.args")"
stdin_seen="$(cat "${TEST_TMPDIR}/bin/fake-codex.stdin")"
expected_bypass_sha="$(printf '%s' "--dangerously-bypass-approvals-and-sandbox" | sha256sum | awk '{print $1}')"
expected_separator_sha="$(printf '%s' "--" | sha256sum | awk '{print $1}')"
expected_prompt_sha="$(printf '%s' "$PROMPT_CONTENT" | sha256sum | awk '{print $1}')"

if echo "$args" | grep -qx -- "arg1_sha=${expected_bypass_sha}"; then
    _pass "fake-codex received approvals/sandbox bypass flag"
else
    _fail "fake-codex missing approvals/sandbox bypass flag: $(echo "$args" | tr '\n' ' ')"
fi

if echo "$args" | grep -qx -- "arg2_sha=${expected_separator_sha}"; then
    _pass "fake-codex received end-of-options separator"
else
    _fail "fake-codex missing end-of-options separator: $(echo "$args" | tr '\n' ' ')"
fi

if echo "$args" | grep -qx -- "arg3_sha=${expected_prompt_sha}"; then
    _pass "fake-codex received leading-dash prompt content as argv"
else
    _fail "fake-codex missing prompt argv: $(echo "$args" | tr '\n' ' ')"
fi

if [[ -z "$stdin_seen" ]]; then
    _pass "fake-codex did not receive prompt on stdin"
else
    _fail "fake-codex unexpectedly received stdin: $stdin_seen"
fi

echo ""
PASS=$(cat "$PASS_FILE")
FAIL=$(cat "$FAIL_FILE")
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
