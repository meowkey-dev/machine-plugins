---
name: backlog
description: Rank the open issue backlog for the closed loop by triage priority (bug > refactoring > feature), filtered to dispatchable issues, with cost estimates. Invoked by the outer-loop (control) when picking the next dispatch target. Trigger on "rank backlog", "what's next", or /backlog.
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Agent
---

# /backlog — rank dispatchable issues for the closed loop

Outer-loop skill: surveys the open backlog and recommends the next issue to dispatch to an asset.

## Why it's a skill (not a subagent)

The procedure is short; context isolation is only needed for the heavy reads (many issues + memory + git). Those go into an ephemeral general-purpose subagent that returns a digest; the outer loop only sees the recommendation, not the raw reads.

## Procedure

1. **Spawn a general-purpose subagent** for the heavy read with this prompt (fill `<MEMORY_DIR>` = this project's auto-memory dir, `~/.claude/projects/<project-slug>/memory/`):

   > Survey this repo's backlog for the closed-loop dispatcher. Return ONLY a markdown table + 2-3 sentence recommendation; no raw issue dumps.
   >
   > Read in parallel:
   > - `gh issue list --state open --limit 60 --json number,title,labels,createdAt`
   > - `ls -t <MEMORY_DIR>/feedback_*.md <MEMORY_DIR>/project_*.md | head -10` and read the top 5 (skip if no memory dir)
   > - `git log --oneline -20`
   > - any repo-specific lineage/status command (skip if none)
   >
   > Apply triage priority: **bug > refactoring > feature** (something broken > improving existing structure > new capability). Filter out:
   > - Issues that touch a repo's declared `frozen_paths` (see `.claude/sdlc.toml`) — e.g. a hash-freeze
   > - Real-world-action requests gated by `prod_gated` (deploy / arm / posture / promote — human-gated)
   > - Research umbrellas (too broad for a single asset workstream)
   > - Blocked issues (upstream dependency / external lock)
   >
   > Return:
   >
   > ```
   > | # | Type | Brief | Cost est. |
   > |---|------|-------|-----------|
   > | <N> | bug/refactor/feature | one sentence | <min>min / $<dollars> |
   > ```
   >
   > Plus 2-3 sentences on the top pick and why. Be terse — the controller is forwarding this to the owner.

2. **Persist** the subagent's digest to `/tmp/sdlc-backlog-summary.md` (always). This unconditional write survives `/compact` and is the fallback `/dispatch <N>` falls back on.

3. **Present** the subagent's digest verbatim to the user.

4. **Wait** for the user to pick. Do not auto-dispatch — that's `/dispatch <N>`.

5. **After the user picks an issue #N**, write a per-issue copy to `/tmp/sdlc-backlog-<N>.md` so `/dispatch <N>` reads the per-issue digest directly rather than scanning the full summary. Skip if the user doesn't pick anything in this turn.

## Constraints

- Don't dump raw issues — the subagent's digest is the surface.
- Don't dispatch from this skill. Pick is the user's; dispatch is `/dispatch`.
- Cost-estimate uncertainty is fine; flag unbounded research as such.
- The triage ordering is a default, not a rule — a high-value refactor can outrank a trivial bug; say so when forwarding. Filters (frozen_paths, prod_gated, research umbrellas, blocked) drop out *before* ranking.
