#!/usr/bin/env bash
# test_skill_paths.sh — guards the assets-dispatch SKILL's binary-path resolution.
#
# Regression target (machine#121): the bundled dispatch-asset fallback must resolve
# relative to the plugin's own install dir (${CLAUDE_PLUGIN_ROOT}/bin/dispatch-asset)
# so it works on marketplace-cache installs, NOT the hardcoded legacy path
# ~/.claude/plugins/assets/bin/dispatch-asset (absent on cache installs).
#
# Prose-only fix (resolution happens controller-side from the SKILL text — there is
# no executable resolver), so this is a grep guard against the path regressing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
SKILL="${PLUGIN_DIR}/skills/assets-dispatch/SKILL.md"

fail=0
ok()  { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; fail=1; }

# 1. The cache-aware fallback is present.
grep -qF '${CLAUDE_PLUGIN_ROOT}/bin/dispatch-asset' "$SKILL" \
  && ok "dispatch-asset fallback uses \${CLAUDE_PLUGIN_ROOT}/bin/" \
  || bad "dispatch-asset fallback missing \${CLAUDE_PLUGIN_ROOT}/bin/dispatch-asset"

# 2. The legacy hardcoded resolution path is gone (it 404s on cache installs).
#    Note the literal 'assets/bin/dispatch-asset' — the cache layout is
#    'assets/<version>/bin/dispatch-asset', so this only matches the legacy form.
if grep -qF '~/.claude/plugins/assets/bin/dispatch-asset' "$SKILL"; then
  bad "legacy hardcoded ~/.claude/plugins/assets/bin/dispatch-asset still resolved"
else
  ok "no legacy hardcoded dispatch-asset path"
fi

exit "$fail"
