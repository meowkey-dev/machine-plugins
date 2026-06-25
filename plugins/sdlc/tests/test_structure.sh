#!/usr/bin/env bash
# test_structure.sh — structural smoke for the sdlc plugin scaffold.
# Validates the manifest, the six skills + qa agent (frontmatter present),
# and that the hook scripts parse. Not a behavioral test of the loop itself
# (that's validated by installing in a real repo).

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
ok()   { echo "ok   - $1"; }
bad()  { echo "FAIL - $1"; fail=1; }

# 1. plugin.json is valid JSON with a name + version
python3 -c "import json,sys; d=json.load(open('${PLUGIN_DIR}/.claude-plugin/plugin.json')); assert d['name']=='sdlc' and d.get('version'); " \
  && ok "plugin.json valid (name=sdlc, has version)" || bad "plugin.json"

# 2. all skills exist with YAML frontmatter
for s in backlog dispatch wrap-up review retro release optimize; do
  f="${PLUGIN_DIR}/skills/${s}/SKILL.md"
  if [[ -f "$f" ]] && head -1 "$f" | grep -q '^---'; then ok "skill: $s"; else bad "skill: $s"; fi
done

# 3. qa agent exists with frontmatter
f="${PLUGIN_DIR}/agents/qa.md"
{ [[ -f "$f" ]] && head -1 "$f" | grep -q '^---'; } && ok "agent: qa" || bad "agent: qa"

# 4. hooks + installer parse under bash
for h in pre-commit pre-push install-git-hooks; do
  bash -n "${PLUGIN_DIR}/hooks/${h}" && ok "hook parses: $h" || bad "hook parses: $h"
done

# 5. renamed skills carry the NEW vocabulary, not the old
grep -Eqi "was \"archive\"|/review" "${PLUGIN_DIR}/skills/review/SKILL.md" && ok "review skill uses new term" || bad "review skill term"
grep -Eqi "/retro|retrospective" "${PLUGIN_DIR}/skills/retro/SKILL.md" && ok "retro skill uses new term" || bad "retro skill term"

# 6. no leaked downstream-repo specifics in the methodology.
# This is a denylist guard: the published methodology must stay repo-agnostic.
# Forks should extend DOWNSTREAM_TERMS with the private project names / domain
# jargon specific to their consuming repo so those never leak into skills/agents.
# The defaults below are neutral placeholders, not real project names.
DOWNSTREAM_TERMS="EXAMPLE_PRIVATE_REPO|EXAMPLE_PRIVATE_TERM"
if grep -rilE "${DOWNSTREAM_TERMS}" "${PLUGIN_DIR}/skills" "${PLUGIN_DIR}/agents" >/dev/null 2>&1; then
  echo "FAIL - downstream-specific terms leaked into methodology:"; grep -rilE "${DOWNSTREAM_TERMS}" "${PLUGIN_DIR}/skills" "${PLUGIN_DIR}/agents"; fail=1
else
  ok "no downstream-specific leakage in skills/agents"
fi

# 7. CHANGELOG.md has an entry for the current plugin version
VERSION=$(python3 -c "import json; print(json.load(open('${PLUGIN_DIR}/.claude-plugin/plugin.json'))['version'])")
grep -q "^## \[${VERSION}\]" "${PLUGIN_DIR}/CHANGELOG.md" \
  && ok "CHANGELOG entry for ${VERSION}" || bad "CHANGELOG missing entry for version ${VERSION}"

exit "$fail"
