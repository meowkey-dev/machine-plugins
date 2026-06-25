#!/usr/bin/env bash
# test_pr_completion_monitor.sh — behavioral test for the completion-only CI monitor.
#
# Regression target (machine#135): the monitor must fire on ALL-CHECKS-TERMINAL,
# not block until a named highlight check posts a verdict. Silence (timeout / a
# still-pending check) must stay DISTINGUISHABLE from a fired terminal state, so
# the controller can never read silence as success.
#
# Tests (gh is stubbed on PATH with fixture JSON):
#   1. docs-only / highlight check ABSENT, all others terminal → fires (was the hang)
#   2. a different check RED + terminal → fires with verdict=red + failed names
#   3. highlight check SKIPPING, others pass → fires, verdict=green, hl reported
#   4. a check still PENDING → does NOT fire (times out, no completion line)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
MONITOR="${PLUGIN_DIR}/bin/pr-completion-monitor"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

PASS_FILE="${TEST_TMPDIR}/.pass"
FAIL_FILE="${TEST_TMPDIR}/.fail"
echo 0 > "$PASS_FILE"; echo 0 > "$FAIL_FILE"
_pass() { echo "  PASS: $1"; echo $(( $(cat "$PASS_FILE") + 1 )) > "$PASS_FILE"; }
_fail() { echo "  FAIL: $1"; echo $(( $(cat "$FAIL_FILE") + 1 )) > "$FAIL_FILE"; }

# Stub `gh` on PATH: it ignores all args and prints the fixture pointed to by
# $GH_FIXTURE. The monitor only calls `gh pr checks ... --json name,bucket`.
STUB_BIN="${TEST_TMPDIR}/bin"
mkdir -p "$STUB_BIN"
cat > "${STUB_BIN}/gh" <<'STUB'
#!/usr/bin/env bash
cat "$GH_FIXTURE"
STUB
chmod +x "${STUB_BIN}/gh"
export PATH="${STUB_BIN}:${PATH}"

# Run the monitor against a fixture with a hard timeout, writing combined output
# to $TEST_TMPDIR/out and returning the monitor's exit code (124 == timed out ==
# did not fire). Callers read `rc` + `out` in the PARENT shell (not a subshell —
# a command-substitution capture would discard the exit code).
run_monitor() {
  local fixture="$1"; shift
  GH_FIXTURE="$fixture" timeout 5 "$MONITOR" "$@" > "${TEST_TMPDIR}/out" 2>&1
}

# ── Test 1: highlight ABSENT, all others terminal → must fire ────────────────
echo "Test 1: highlight check absent, others terminal → fires"
cat > "${TEST_TMPDIR}/f1.json" <<'EOF'
[{"name":"build","bucket":"pass"},{"name":"unit","bucket":"pass"}]
EOF
rc=0; run_monitor "${TEST_TMPDIR}/f1.json" 42 "claude-review / claude-review" || rc=$?
out="$(cat "${TEST_TMPDIR}/out")"
if [[ "$rc" -eq 0 ]] && echo "$out" | grep -q "all-checks-complete"; then
  _pass "fires when highlight check never appears (out: $out)"
else
  _fail "expected fire+all-checks-complete, got rc=$rc out='$out'"
fi

# ── Test 2: a different check RED + terminal → fires with verdict=red ─────────
echo "Test 2: red terminal check → fires, surfaces verdict=red + failed names"
cat > "${TEST_TMPDIR}/f2.json" <<'EOF'
[{"name":"pytest","bucket":"fail"},{"name":"build","bucket":"pass"}]
EOF
rc=0; run_monitor "${TEST_TMPDIR}/f2.json" 42 || rc=$?
out="$(cat "${TEST_TMPDIR}/out")"
if [[ "$rc" -eq 0 ]] && echo "$out" | grep -q "all-checks-complete" \
   && echo "$out" | grep -qi "verdict=red" && echo "$out" | grep -q "pytest"; then
  _pass "fires with verdict=red + failed=[pytest] (out: $out)"
else
  _fail "expected fire+verdict=red+pytest, got rc=$rc out='$out'"
fi

# ── Test 3: highlight SKIPPING, others pass → fires, verdict=green ────────────
echo "Test 3: highlight skipping, others pass → fires green, hl reported"
cat > "${TEST_TMPDIR}/f3.json" <<'EOF'
[{"name":"claude-review","bucket":"skipping"},{"name":"build","bucket":"pass"}]
EOF
rc=0; run_monitor "${TEST_TMPDIR}/f3.json" 42 "claude-review" || rc=$?
out="$(cat "${TEST_TMPDIR}/out")"
if [[ "$rc" -eq 0 ]] && echo "$out" | grep -q "all-checks-complete" \
   && echo "$out" | grep -qi "verdict=green" && echo "$out" | grep -q "skipping"; then
  _pass "fires green, reports highlight skipping as detail (out: $out)"
else
  _fail "expected fire+verdict=green+skipping, got rc=$rc out='$out'"
fi

# ── Test 4: a check still PENDING → must NOT fire (silence != success) ────────
echo "Test 4: pending check → does NOT fire (times out, no completion line)"
cat > "${TEST_TMPDIR}/f4.json" <<'EOF'
[{"name":"build","bucket":"pending"},{"name":"unit","bucket":"pass"}]
EOF
rc=0; run_monitor "${TEST_TMPDIR}/f4.json" 42 || rc=$?
out="$(cat "${TEST_TMPDIR}/out")"
if [[ "$rc" -eq 124 ]] && ! echo "$out" | grep -q "all-checks-complete"; then
  _pass "does not fire while pending (timed out, no completion line)"
else
  _fail "expected timeout (rc=124) with no completion line, got rc=$rc out='$out'"
fi

# ── Test 5: failing check name WITH A SPACE → must not word-split ─────────────
# GitHub check names routinely contain spaces (e.g. "build / lint"). The python
# pass emits tab-separated fields, so `read` must split on tabs only — a default
# $IFS would split "build / lint" on its spaces, truncating failed_names and
# spilling the remainder into the highlight field.
echo "Test 5: failing check name with a space → full name preserved, no garble"
cat > "${TEST_TMPDIR}/f5.json" <<'EOF'
[{"name":"build / lint","bucket":"fail"},{"name":"unit","bucket":"pass"}]
EOF
rc=0; run_monitor "${TEST_TMPDIR}/f5.json" 42 || rc=$?
out="$(cat "${TEST_TMPDIR}/out")"
if [[ "$rc" -eq 0 ]] && echo "$out" | grep -qF "failed=[build / lint]" \
   && ! echo "$out" | grep -qF ":/"; then
  _pass "spaced check name preserved, highlight field not garbled (out: $out)"
else
  _fail "expected failed=[build / lint] and no garble, got rc=$rc out='$out'"
fi

echo ""
echo "Results: $(cat "$PASS_FILE") passed, $(cat "$FAIL_FILE") failed"
[[ "$(cat "$FAIL_FILE")" -eq 0 ]] && exit 0 || exit 1
