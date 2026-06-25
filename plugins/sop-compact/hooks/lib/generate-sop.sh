#!/usr/bin/env bash
# generate-sop.sh — bootstrap a per-repo `.claude/sop-compact.md` using a `claude -p`
# sidecar over the plugin's template skeleton + the repo's own CLAUDE.md / memory.
#
# Sourced by pre-compact.sh on the first compact in a repo (when `.claude/sop-compact.md`
# is missing) so the user never hits the "did I run /init-sop-compact?" failure mode.
# Replaces the user-invocable `/init-sop-compact` skill that v0.5.0 removed.
#
# Contract:
#   generate_sop "$REPO_DIR"
#     env in:    SOP_COMPACT_MODEL              (optional, default `opus`)
#                SOP_COMPACT_BOOTSTRAP_TIMEOUT  (optional, default 300s)
#                CLAUDE_PLUGIN_ROOT             (required — set by the hook loader)
#     side fx:   writes `$REPO_DIR/.claude/sop-compact.md` atomically on success
#                appends an entry to `$REPO_DIR/.gitignore` for the ephemeral artifacts
#                writes a debug log under `$REPO_DIR/.claude/sop-compact/` on failure
#     stderr:    a one-line failure summary on rc!=0 (caller surfaces it to the user)
#     return:    0 on success (SOP file present and non-empty), 1 otherwise
#
# The bootstrap sidecar is awaited like the snapshot sidecar — failure here must not
# block compaction; the caller falls back to its existing missing-SOP stub-handoff path.
#
# Time budget is independent of the snapshot's (default 600s). Bootstrap is a smaller job
# (skeleton + a few docs, no transcript), so 300s is enough headroom even on opus.

generate_sop() {
  local repo_dir="$1"
  local sop_file="${repo_dir}/.claude/sop-compact.md"
  local snap_dir="${repo_dir}/.claude/sop-compact"
  # CLAUDE_PLUGIN_ROOT is set by the hook loader in normal operation, but may be unset
  # under hand-wired installs or in tests; fall back to a path relative to this file so
  # the helper still resolves the template. Use ${VAR:-} so `set -u` in the caller doesn't
  # trip on the unset variable.
  local plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
  local template="${plugin_root}/templates/sop-compact.md.tmpl"

  mkdir -p "${repo_dir}/.claude" "$snap_dir"

  if [[ ! -f "$template" ]]; then
    # Keep the stub-handoff pointer in pre-compact.sh honest: the user is told to look
    # for `bootstrap-*.error.log` under `.claude/sop-compact/`, so write one here too —
    # not only on the sidecar-fail path. (Surfaced by claude-review on PR #152.)
    local ts debug
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    debug="${snap_dir}/bootstrap-${ts}.error.log"
    {
      printf 'sop-compact bootstrap aborted at %s: template not found\n' "$ts"
      printf 'expected at: %s\n' "$template"
      printf 'CLAUDE_PLUGIN_ROOT=%s\n' "${CLAUDE_PLUGIN_ROOT:-<unset>}"
      printf '\nHand-wired install? Copy `templates/sop-compact.md.tmpl` into the plugin root,\n'
      printf 'or set CLAUDE_PLUGIN_ROOT to the directory that contains `templates/`.\n'
    } >"$debug" 2>/dev/null || true
    echo "sop-compact: bootstrap aborted — template not found at $template (see $debug)" >&2
    return 1
  fi

  local model="${SOP_COMPACT_MODEL:-opus}"
  local timeout_s="${SOP_COMPACT_BOOTSTRAP_TIMEOUT:-300}"
  local repo_name
  repo_name="$(basename "$repo_dir")"

  local prompt_file stderr_file
  prompt_file="$(mktemp)"
  stderr_file="$(mktemp)"
  # NOTE: a `trap "..." RETURN` set here would persist after generate_sop returns and
  # fire on every later function return in the calling shell (bash RETURN traps are
  # shell-global, not function-scoped, unless `local -` / `set -o functrace` are used).
  # Currently benign — the trap would only `rm -f` files already removed — but a latent
  # footgun if a future function reuses these variable names. Explicit cleanup at each
  # return path is the simpler, scope-correct pattern. (Surfaced by claude-review on
  # PR #152, round 2.)

  # Prompt mirrors the procedure that used to live in skills/init-sop-compact/SKILL.md:
  # read the template skeleton as authoritative structure; sample this repo's CLAUDE.md,
  # memory dirs, and skill/command hints at high level; fill in the per-repo bullets;
  # output ONLY the final markdown. Memory locations vary by repo, so let the agent
  # discover them rather than hard-coding paths here.
  cat >"$prompt_file" <<EOF
You are the sop-compact bootstrap sidecar. Generate a per-repo \`.claude/sop-compact.md\`
for this codebase. The file will be committed and read by the plugin's hooks on every
future \`/compact\` in this repo.

Working directory: ${repo_dir}
Repo name: ${repo_name}
Template skeleton (authoritative structure — DO NOT restructure): ${template}

Do this, in order:

1. Read the template at \`${template}\`. Carry its trust hierarchy, the 2x2 selection
   rule, and the four section headings through verbatim. Only the repo-specific bullets
   and the two header placeholders (\`{REPO_NAME}\`, \`{INSTANCE_DESCRIPTION}\`) should
   change.

2. Survey this repo's context at HIGH LEVEL (names + one-line descriptions, not full
   content):
   - \`${repo_dir}/CLAUDE.md\` if present (use its first non-heading paragraph as
     \`{INSTANCE_DESCRIPTION}\`).
   - Memory directories — check \`${repo_dir}/memory/\` and the Claude Code per-project
     memory dir at \`\$HOME/.claude/projects/-<encoded-repo-path>/memory/\` (encoded path
     = the repo's absolute path with each \`/\` replaced by \`-\`). Use \`ls\` first to
     confirm which exist.
   - \`${repo_dir}/.claude/skills/\` and \`${repo_dir}/.claude/commands/\` for hints on
     how the repo is operated.

3. Fill in the repo-specific sections of the template:
   - **(a) Pre-compact sidecar guidance**: promotion targets (the actual memory dirs /
     CLAUDE.md / skills dir paths you found), snapshot conventions (what
     non-reconstructable state matters most here), dirty-tree note.
   - **(b) Post-compact recovery**: live-state checks (\`git status\`, \`gh pr list\`,
     repo-specific signals), channels / interfaces (Discord / Slack / Zulip / WeChat /
     mesh-channel / none — infer from installed plugins or CLAUDE.md), in-flight work
     file locations / signal files.
   - Substitute \`{REPO_NAME}\` with \`${repo_name}\`. Substitute
     \`{INSTANCE_DESCRIPTION}\` with a one-liner from CLAUDE.md (or a sensible
     placeholder if absent).

4. If the repo has no CLAUDE.md and no memory dirs, still emit a usable SOP — leave the
   repo-specific bullets as inspection prompts (e.g. "inspect \`git status\` on resume")
   so the user has a minimal stub they can flesh out.

Output ONLY the final filled-in markdown to stdout. No preamble, no surrounding code
fence around the whole document, no trailing commentary. The output must begin with the
\`# SOP: Compaction Survival — ${repo_name}\` heading.
EOF

  # Same invocation pattern as the snapshot sidecar (claude -p with tool use, no session
  # pollution). Honour SOP_COMPACT_MODEL but default to plain `opus` for bootstrap —
  # the inputs are small (skeleton + a few docs) so the 1m-context model isn't needed.
  local sidecar_out rc
  sidecar_out="$(
    cd "$repo_dir" && timeout "$timeout_s" claude -p "$(cat "$prompt_file")" \
      --model "$model" \
      --setting-sources "" \
      --disable-slash-commands \
      --strict-mcp-config \
      --no-chrome \
      --no-session-persistence \
      --dangerously-skip-permissions \
      2>"$stderr_file"
  )"
  rc=$?

  if [[ $rc -ne 0 || -z "${sidecar_out// /}" ]]; then
    local ts debug
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    debug="${snap_dir}/bootstrap-${ts}.error.log"
    {
      printf 'sop-compact bootstrap sidecar failed (rc=%s) at %s\n' "$rc" "$ts"
      printf 'model=%s timeout=%s\n\n--- stderr ---\n' "$model" "$timeout_s"
      cat "$stderr_file" 2>/dev/null
    } >"$debug" 2>/dev/null || true
    echo "sop-compact: bootstrap sidecar failed (rc=$rc); falling back to stub handoff. See $debug" >&2
    rm -f "$prompt_file" "$stderr_file"
    return 1
  fi

  rm -f "$prompt_file" "$stderr_file"

  # Atomic write so a half-written SOP never gets committed.
  local tmp
  tmp="$(mktemp "${repo_dir}/.claude/.sop-compact.XXXXXX")"
  printf '%s\n' "$sidecar_out" >"$tmp"
  mv -f "$tmp" "$sop_file"

  # Match the old skill: keep the ephemeral handoffs out of git. Re-runs must not
  # duplicate the entry, so grep before appending.
  local gitignore="${repo_dir}/.gitignore"
  if [[ ! -f "$gitignore" ]] || ! grep -qxF '.claude/sop-compact/handoff-*.md' "$gitignore"; then
    {
      [[ -s "$gitignore" ]] && printf '\n'
      printf '# sop-compact (ephemeral)\n.claude/sop-compact/handoff-*.md\n'
    } >>"$gitignore"
  fi

  return 0
}
