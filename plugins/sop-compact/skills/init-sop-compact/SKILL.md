---
name: init-sop-compact
description: Generate a repo-specific .claude/sop-compact.md tailored to this codebase. Run once per repo (or to refresh). Composes a prompt from the plugin's template skeleton + this repo's CLAUDE.md/memory and runs an internal `claude -p` (opus) to emit the SOP, then git-ignores the ephemeral handoff artifacts. Trigger on /init-sop-compact.
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash(claude *)
  - Bash(ls *)
  - Bash(cat *)
  - Bash(grep *)
  - Bash(mkdir *)
  - Bash(test *)
  - Bash(basename *)
  - Bash(pwd *)
  - Bash(date *)
---

# /init-sop-compact — Generate a repo-tailored compaction SOP (hooks-only)

Produce `.claude/sop-compact.md` for the current repo. This is the static, committed file
the **sop-compact** plugin's hooks read: the PreCompact sidecar reads it to know this repo's
promotion targets and snapshot conventions; the SessionStart hook's recovery guidance comes
from it. Run once per repo, or re-run to refresh (e.g. after structure changes or to fold in
the SOP's own Feedback section).

The generation mirrors `cc-session`'s `sop` subcommand: an internal `claude -p` (opus) reads
the template skeleton + this repo's docs and emits the filled SOP. This plugin ships its own
template/prompt rather than shelling out to `cc-session`.

## Procedure

1. **Resolve repo facts.**
   - `REPO_ROOT="$(pwd)"`, `REPO_NAME="$(basename "$REPO_ROOT")"`.
   - Template skeleton: `${CLAUDE_PLUGIN_ROOT}/templates/sop-compact.md.tmpl`. If
     `$CLAUDE_PLUGIN_ROOT` is unset (files copied into a repo manually), fall back to
     `.claude/templates/sop-compact.md.tmpl`.

2. **Locate this repo's context** so the inner `claude -p` can read it:
   - `CLAUDE.md` at the repo root (if present).
   - Memory directories — check `memory/` at the repo root and the CC per-project memory dir
     `~/.claude/projects/-<encoded-repo-path>/memory/` (the encoded path is the repo's
     absolute path with each `/` replaced by `-`). Use `ls` to confirm which exist.
   - `.claude/skills/` and `.claude/commands/` for hints on how the repo is operated.

3. **Run the internal `claude -p`** to generate the SOP. Build a prompt that instructs it to
   read the template skeleton + the repo docs you located, then emit ONLY the filled SOP to
   stdout. Use the same invocation flags as `cc-session` (tool use on, no session pollution):

   ```bash
   claude -p "$PROMPT" \
     --model opus \
     --setting-sources "" \
     --disable-slash-commands \
     --strict-mcp-config \
     --no-chrome \
     --no-session-persistence \
     --dangerously-skip-permissions \
     > .claude/sop-compact.md
   ```

   (Override the model via the `SOP_COMPACT_MODEL` env var if set.) Run `mkdir -p .claude`
   first. The `$PROMPT` must tell the inner agent to:
   - Read the template at the path from step 1 and use it as the **authoritative structure** —
     carry the trust hierarchy, the 2x2 rule, and the four section headings through verbatim.
   - Read this repo's `CLAUDE.md` + memory (paths from step 2), reading high-level only
     (names + one-line descriptions), not drowning in content.
   - Fill in the repo-specific sections: **(a)** pre-compact sidecar guidance (promotion
     targets, snapshot conventions, dirty-tree note), **(b)** post-compact recovery
     (live-state checks, channels/interfaces, in-flight work + signal file locations).
   - Substitute `{REPO_NAME}` and `{INSTANCE_DESCRIPTION}` (one line from `CLAUDE.md`).
   - Output ONLY the final Markdown to stdout — no preamble, no code fence around the whole
     document, no trailing commentary.

4. **Verify.** `Read` the written `.claude/sop-compact.md`. If it is empty or the `claude -p`
   call failed (non-zero exit / empty output), tell the user the generation failed, do NOT
   leave a broken file (overwrite with a minimal stub built from the template, or remove it),
   and stop.

5. **Update `.gitignore`** so the ephemeral artifacts stay out of git while the SOP itself
   stays committed. Read the repo-root `.gitignore` (create if absent). If these lines are
   not already present, append them under a `# sop-compact (ephemeral)` comment:

   ```
   .claude/sop-compact/handoff-*.md
   ```

   Use `grep` to check for existing entries before appending so re-runs don't duplicate them.

6. **Report.** Tell the user `.claude/sop-compact.md` was written, summarize what you
   customized (which memory dirs were found, what live-state checks / channels / promotion
   targets were filled in), and note that the file is committed/tunable while
   `handoff-*.md` is git-ignored. Remind them the hooks now run automatically
   on `/compact` — there is no `/prep-compact` step in this version.

## Notes

- Keep the generic procedure (trust hierarchy, 2x2 rule, the four section headings) intact;
  only the repo-specific bullets and the two header placeholders should change per repo.
- If the repo has no `CLAUDE.md` and no memory dirs, still write a usable SOP — leave the
  repo-specific bullets as prompts ("inspect `git status`...") and tell the user it's a
  minimal stub they can flesh out.
