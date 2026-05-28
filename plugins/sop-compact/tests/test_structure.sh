#!/usr/bin/env bash
# test_structure.sh — structural smoke for the sop-compact plugin.
# Validates the manifest and that the current version has a CHANGELOG entry.
# Not a behavioral test (behavioral tests are in the other test_*.sh files).

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
ok()  { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; fail=1; }

# 1. plugin.json is valid JSON with a name + version
python3 -c "import json,sys; d=json.load(open('${PLUGIN_DIR}/.claude-plugin/plugin.json')); assert d['name']=='sop-compact' and d.get('version'); " \
  && ok "plugin.json valid (name=sop-compact, has version)" || bad "plugin.json"

# 2. CHANGELOG.md has an entry for the current plugin version
VERSION=$(python3 -c "import json; print(json.load(open('${PLUGIN_DIR}/.claude-plugin/plugin.json'))['version'])")
grep -q "^## \[${VERSION}\]" "${PLUGIN_DIR}/CHANGELOG.md" \
  && ok "CHANGELOG entry for ${VERSION}" || bad "CHANGELOG missing entry for version ${VERSION}"

exit "$fail"
