#!/usr/bin/env bash
# Smoke test for mesh-channel send + watch.
#
# Verifies:
#   1. send writes a JSONL line that watch emits for the OTHER name
#   2. send writes a line that watch FILTERS OUT for its own name (self-filter)
#   3. cursor advances correctly across multiple sends
#   4. truncating the channel file resets the cursor
#   5. markdown body with quotes/newlines survives a round trip

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SEND="$PLUGIN_DIR/bin/mesh-channel-send"
WATCH="$PLUGIN_DIR/bin/mesh-channel-watch"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"; kill %1 2>/dev/null || true' EXIT

CHANNEL="$WORK/test.jsonl"
OUT="$WORK/watch.out"

# Start watcher as alice, capture stdout
"$WATCH" "$CHANNEL" alice --poll 0.05 > "$OUT" 2>&1 &
WATCHER_PID=$!

# Brief settle
sleep 0.2

# Test 1: bob sends -> alice should see it
"$SEND" "$CHANNEL" bob "hello from bob"
sleep 0.3
if ! grep -q '"from": "bob"' "$OUT"; then
  echo "FAIL: alice did not see bob's message" >&2
  cat "$OUT" >&2
  exit 1
fi
echo "PASS test 1: bob -> alice delivered"

# Test 2: alice sends -> alice should NOT see it (self-filter)
"$SEND" "$CHANNEL" alice "hello from alice"
sleep 0.3
if grep -q '"from": "alice"' "$OUT"; then
  echo "FAIL: alice saw her own message (self-filter broken)" >&2
  cat "$OUT" >&2
  exit 1
fi
echo "PASS test 2: alice self-filter works"

# Test 3: markdown body with quotes/newlines/backticks
"$SEND" "$CHANNEL" bob "with \"quote\" and
newline and \`code\` — does it survive?"
sleep 0.3
LINES_FROM_BOB=$(grep -c '"from": "bob"' "$OUT")
if [ "$LINES_FROM_BOB" -ne 2 ]; then
  echo "FAIL: expected 2 lines from bob, got $LINES_FROM_BOB" >&2
  cat "$OUT" >&2
  exit 1
fi
# Each emitted line must be valid JSON
while IFS= read -r line; do
  if [ -n "$line" ]; then
    echo "$line" | python3 -c "import json,sys; json.loads(sys.stdin.read())" \
      || { echo "FAIL: emitted line not valid JSON: $line" >&2; exit 1; }
  fi
done < "$OUT"
echo "PASS test 3: markdown body survives round trip"

# Test 4: cursor file exists and advances
CURSOR="$CHANNEL.cursor.alice"
if [ ! -f "$CURSOR" ]; then
  echo "FAIL: cursor file not created at $CURSOR" >&2
  exit 1
fi
OFFSET=$(cat "$CURSOR")
SIZE=$(stat -c '%s' "$CHANNEL" 2>/dev/null || stat -f '%z' "$CHANNEL")
if [ "$OFFSET" != "$SIZE" ]; then
  echo "FAIL: cursor ($OFFSET) does not match file size ($SIZE)" >&2
  exit 1
fi
echo "PASS test 4: cursor advances to EOF"

# Test 5: truncation resets cursor
> "$CHANNEL"
"$SEND" "$CHANNEL" bob "after truncation"
sleep 0.3
NEW_LINES=$(grep -c '"after truncation"' "$OUT")
if [ "$NEW_LINES" -ne 1 ]; then
  echo "FAIL: post-truncation message not seen" >&2
  cat "$OUT" >&2
  exit 1
fi
echo "PASS test 5: truncation handled"

echo
echo "ALL TESTS PASSED"
