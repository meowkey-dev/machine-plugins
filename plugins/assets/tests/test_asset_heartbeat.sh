#!/usr/bin/env bash
# test_asset_heartbeat.sh — exercises the no-progress detection in asset-heartbeat
#
# Tests the pane-normalization core (the unit-testable bit; the tmux poll loop
# itself isn't): the normalization must collapse a HUNG-but-spinning pane (same
# content, different rotating spinner glyph + ticking timer) to an equal string
# so the freeze check fires, while leaving GENUINE progress (changed content)
# as a different string so it stays silent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
HEARTBEAT="${PLUGIN_DIR}/bin/asset-heartbeat"

fail=0
check() { # check <desc> <expected> <actual>
  if [[ "$2" == "$3" ]]; then echo "ok   - $1"; else echo "FAIL - $1"; echo "       expected: [$2]"; echo "       actual:   [$3]"; fail=1; fi
}

# Mirror the normalization sed from asset-heartbeat (kept in sync with the
# _normalized_pane body). If you change the sed there, change it here.
norm() {
  sed -E 's/[✶✷✸✹✺✻✼✽✦✧⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏⣾⣽⣻⢿⡿⣟⣯⣷]//g; s/\([0-9]+m?[[:space:]]*[0-9]*s?\)//g; s/[0-9]+m[[:space:]]+[0-9]+s//g; s/[0-9]+s\b//g; s/^[[:space:]]*[0-9]+[[:space:]]*//; s/[[:space:]]+/ /g'
}

# 0. The script exists and parses.
bash -n "$HEARTBEAT" && echo "ok   - asset-heartbeat parses"

# 1. Hung-but-spinning: same content, different spinner glyph + timer → EQUAL.
a=$(printf '✻ Coalescing… (17s)\n  ⎿ reading cycle_log_reader.py' | norm)
b=$(printf '✽ Coalescing… (1m 4s)\n  ⎿ reading cycle_log_reader.py' | norm)
check "hung-but-spinning normalizes equal (would fire)" "$a" "$b"

# 2. Genuine progress: content changed → DIFFERENT (stays silent).
c=$(printf '✻ Coalescing… (5s)\n  ⎿ reading file_a.py' | norm)
d=$(printf '✻ Coalescing… (5s)\n  ⎿ editing file_b.py' | norm)
[[ "$c" != "$d" ]] && echo "ok   - genuine progress normalizes different (stays silent)" || { echo "FAIL - progress should differ"; fail=1; }

# 3. Idle parked pane (no spinner) is stable across captures → EQUAL.
e=$(printf '❯ \n  -- INSERT  ⏵⏵ bypass permissions' | norm)
f=$(printf '❯ \n  -- INSERT  ⏵⏵ bypass permissions' | norm)
check "idle parked pane normalizes equal (would fire)" "$e" "$f"

exit "$fail"
