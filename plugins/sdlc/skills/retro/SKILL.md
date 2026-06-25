---
name: retro
description: "Outer-loop release-cadence skill — synthesize across a release window of merged PRs + closed issues + git to propose higher-order playbook updates the per-PR review pass wouldn't catch. Cross-workstream patterns only. Trigger on \"run a retro\", \"release retro\", or /retro."
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Agent
---

# /retro [--window <range>] — release-cadence cross-PR retrospective

Outer-loop skill. **Cross-workstream synthesis at release boundaries.** Reads all merged PRs + closed issues + git log (+ any repo-specific lineage) in a window and proposes higher-order playbook updates the per-PR `review` pass wouldn't catch on its own.

Different cadence, different scope from `review`:

| Skill | Cadence | Scope |
|---|---|---|
| `review` | every merge | one PR's `## Report` → playbook |
| `retro` (this) | every release | window of N PRs → cross-cutting patterns |

Per-PR review is the continuous path; the retro is the release-boundary catch-up that finds the patterns no single PR's report would surface alone.

**The playbook is a reinforcement ledger over memory** (see the `review` skill's section + the PLAYBOOK header): retro never writes prose lessons — it increments `reinforced` / `contradicted` counts on memory-backed ledger entries, and for genuinely-new cross-PR patterns it writes the memory item first, then adds a fresh entry at `reinforced ×1`. Ledger-eligibility scope: A + B only (see `review` skill) — a `new`, `reinforce`, or `contradict` op is valid only for an A (closed-loop methodology) or B (reusable technique) memory; a C (static domain fact) stays memory-only.

## Why a skill (not a subagent)

The outer-loop AGENT does the retro. The skill is the recipe. Heavy window-reads go into an ephemeral subagent (via Agent tool) so control's context isn't blown by raw PR bodies / git logs.

## Procedure

1. **Determine the window.** Default = `<prev_release_tag>..HEAD`. Override via `--window <range>`.

2. **Spawn a subagent** with this prompt (so the heavy read doesn't enter control's context):

   > Survey this repo's closed-loop release window `<range>`. Return ONLY a markdown summary; no raw PR dumps.
   >
   > Read in parallel:
   > - `cat <MEMORY_DIR>/MEMORY.md` + `ls <MEMORY_DIR>/*.md` (`<MEMORY_DIR>` = `~/.claude/projects/<project-slug>/memory/`, derived from the repo path) — the memory index, so every `reinforce`/`contradict` op names a slug that **actually exists**; a lesson with no matching slug is a `new` op (name the memory item to create). Without this you'd guess slugs and create orphaned ledger entries.
   > - `git log <range> --merges --oneline`
   > - For each merged PR in the window: `gh pr view <N> --comments` — locate `## Iteration N` + `## Report`
   > - For each closed issue in the window: `gh issue view <N> --comments`
   > - `gh api repos/{owner}/{repo}/actions/runs?per_page=10` for CI patterns
   > - any repo-specific cost/lineage summary (skip if none)
   >
   > Extract **cross-PR patterns** (single-PR lessons are the review pass's job; you find what review missed):
   > - Repeated owner-corrections across multiple PRs that suggest a contract bug
   > - Recurring bot-review findings on the same theme across PRs
   > - Cost-budget overruns + their root causes
   > - Memory / playbook entries that proved wrong in-window
   > - Workflow rituals invented ad-hoc in multiple PRs that should be codified
   > - Drift between the repo's contract docs and actual practice
   >
   > Return (the playbook is a **reinforcement ledger over memory** — express deltas as ledger ops, not prose):
   > - 3-7 proposed deltas, each as one of: **reinforce** `[[memory-slug]]` (+1, with the validating PR), **contradict** `[[memory-slug]]` (+1, with the case), or **new** (no memory home yet → name the memory item to create, then a fresh entry at `reinforced ×1`)
   > - **Eligibility:** a `reinforce`, `new`, or `contradict` op is valid only for an **A** (closed-loop methodology: how we work, ritual mechanics, control discipline) or **B** (reusable technique: a reach-for-again HOW-TO) memory. A **C** memory (static domain fact: tool/model/framework constants, fixed behavioral facts of an external system) stays memory-only — no ledger row; a count on a static fact adds noise.
   > - Per-delta: cross-PR evidence — **≥2 PRs/issues** (this is what distinguishes a retro finding from a review finding; single-PR findings are review's job)
   > - **Required contradiction pass (a null result must be STATED, not omitted):** name *every* memory/ledger entry the window weakened or overturned — a lesson that misled an asset, a rule a finding superseded, guidance now stale — each with its contradicting case (the prune-or-revise signal). If none, say so explicitly and why (what you swept). The ledger drifts up-only without this forcing step; the same hunt runs per-PR in `review` and in `wrap-up` step 5.
   > - Cost report if measurable

3. **Apply the accepted ledger ops, then open a single ledger-update PR.** *New* lessons: write the memory item(s) direct-to-disk first (+ a `MEMORY.md` line), then add their ledger entries. *Reinforce / contradict*: bump the counts + append the evidence lines on existing entries. The PR diff is the `<PLAYBOOK>` ledger change only (memory writes aren't in it — the auto-memory dir isn't in the repo). Tag `playbook-update` if the repo has the label; link the release tag in the body.

4. **Owner reviews + merges** (or control merges on owner's behalf if pre-approved).

## Constraints

- One retro PR per release window.
- Cross-PR evidence required per delta — a finding citable to a single PR is review's job, not the retro's. Reject "found in PR #N" deltas; require "PR #N AND PR #M AND…" patterns.
- If the repo's convention is "runtime-contract-doc edits ride with their feature PR," keep such edits out of the retro PR.
- Owner reviews + merges any PLAYBOOK / doc / skill-file PR; control never auto-merges these.

## Relation to review

- `review` runs CONTINUOUSLY (per merge). If a lesson is from one PR, review captures it.
- `retro` runs at RELEASE BOUNDARIES. If a lesson only emerges when N PRs are seen together, the retro captures it.
- Net: by the time `/retro` runs, review has already drained the per-PR lessons. The retro's job is the cross-cutting residue.
