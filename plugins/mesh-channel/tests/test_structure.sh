#!/usr/bin/env bash
# test_structure.sh — structural smoke for the mesh-channel plugin.
# Validates the manifest and that the current version has a CHANGELOG entry.
# Not a behavioral test (behavioral tests are in test_send_and_watch.sh).

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
ok()  { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; fail=1; }

# 1. plugin.json is valid JSON with a name + version
python3 -c "import json,sys; d=json.load(open('${PLUGIN_DIR}/.claude-plugin/plugin.json')); assert d['name']=='mesh-channel' and d.get('version'); " \
  && ok "plugin.json valid (name=mesh-channel, has version)" || bad "plugin.json"

# 2. CHANGELOG.md has an entry for the current plugin version
VERSION=$(python3 -c "import json; print(json.load(open('${PLUGIN_DIR}/.claude-plugin/plugin.json'))['version'])")
grep -q "^## \[${VERSION}\]" "${PLUGIN_DIR}/CHANGELOG.md" \
  && ok "CHANGELOG entry for ${VERSION}" || bad "CHANGELOG missing entry for version ${VERSION}"

exit "$fail"
