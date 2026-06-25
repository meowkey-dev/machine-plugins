---
name: review
description: "Outer-loop per-PR learning. Consume one asset's just-merged PR + its `## Report` section; cross-reference against existing guidance; fold accepted deltas into the reinforcement ledger (memory writes go straight to disk; PLAYBOOK.md is a reinforcement ledger over memory — increment reinforced/contradicted counts, never write prose). The continuous post-merge ritual. Trigger on \"review the report\", \"run review on PR N\", or /review."
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Agent
---

# /review [--pr <N>] — per-PR learning ritual

Outer-loop skill. **Fires on every merge** as the control-side post-merge ritual. Consumes the just-merged PR's `## Report` section (the asset's final reflection) and decides per delta: accept, reject, refine.

This is the **continuous** path that keeps the playbook current in real time. Don't confuse with `retro` (release-cadence, cross-PR window synthesis) — different cadence, different scope.

> Normally `review` runs **as step 5 of `/wrap-up`** (the blessed close-out that merges + reviews + cleans up in one ritual, so review can't be skipped). Run `review` standalone only to re-review a PR merged outside `wrap-up`.

## Why a skill (not a subagent)

The outer-loop AGENT does the reviewing. The skill is the recipe. If the PR's diff/comments are heavy, push the read into an ephemeral subagent (via Agent tool) so control's context stays lean.

## Comment-placement contract

GitHub is the comms substrate, so placement is load-bearing — keep it consistent:

- The asset's `## Report` and `## Iteration N` comments live **on the PR**.
- Control's review (`## Session Review`) goes **on the issue** (the durable per-issue record), not duplicated to the PR.

## `<PLAYBOOK>` is a reinforcement ledger over memory (not a content store)

`<PLAYBOOK>` does **not** hold prose lessons — it's a ledger of *memory items'* battle-testing: each entry is `[[memory-slug]]` + `reinforced ×N` / `contradicted ×M` + a dated evidence log (see the PLAYBOOK header). The rule itself lives in memory; the ledger carries only the up/down signal. So a review never *writes a lesson into `<PLAYBOOK>`* — per accepted delta it does exactly one of:

1. **memory item exists + this PR validated it** → **+1 reinforced** on its ledger entry, append the PR + one-line context to its evidence log.
2. **memory item exists + this PR shows it wrong / superseded** → **+1 contradicted**, append the case. Any `contradicted ×M>0` flags that memory item for revision-or-prune.
3. **no memory item yet** → **write the memory item first** (`<MEMORY_DIR>/…`, direct-to-disk), *then* add a fresh ledger entry at `reinforced ×1`.

"Worth reinforcing" ⟺ "worth a memory entry." A purely **mechanical / tool-specific** rule (not generalizable methodology) goes to that tool's home (a plugin's brief / qa rubric / a runbook), **not** the ledger.

**Ledger-eligibility scope (A + B only — not C):**
- **A — closed-loop methodology:** how we work — review/dispatch/control discipline, ritual mechanics, escalation contracts → ledger row
- **B — reusable techniques:** reach-for-again HOW-TOs (a profiling probe, a dev/test bridge, a recurring workflow pattern) → ledger row
- **C — static domain facts:** tool/framework/model constants, fixed behavioral facts of an external system → **memory-only, no ledger row**

*Discriminator:* does a reinforce/contradict count change a future decision? Yes for A/B (you want to know which how-we-work rules and reusable techniques are battle-tested); no for C (a static fact is just true — a count adds noise). A `new`, `reinforce`, or `contradict` op is valid only for an A or B memory; a C fact stays memory-only.

## Procedure

(`<MEMORY_DIR>` = this project's auto-memory dir, `~/.claude/projects/<project-slug>/memory/`. `<PLAYBOOK>` = `playbook_path` from `.claude/sdlc.toml`, default `PLAYBOOK.md`.)

1. **Read the PR + its Report.** `gh pr view <N> --comments --json title,body,comments`. Locate the `## Report` section in the asset's final summary.
2. **Cross-reference** each proposed delta against existing guidance:
   - `ls -t <MEMORY_DIR>/*.md | head -20` — read titles, look for duplicates (skip if no memory dir)
   - `git log --oneline -10 <PLAYBOOK> .claude/` — recent edits
3. **Contradiction-hunt (forcing step — a null result must be STATED, not skipped).** Ups are easy to spot and downs need deliberate attention, so the ledger drifts up-only without this. Ask explicitly: *did any merged work CONTRADICT an existing memory/ledger entry — a lesson that misled the asset, a rule a review finding overturned, or guidance now superseded?* If so, `+1 contradicted` on that entry + the case, and flag the memory item for revise/prune (per mechanic 2 below). If not, **say so** ("no contradictions — swept X, Y, Z"). (Same hunt `wrap-up` step 5 runs when it folds in review.)
4. **Decide per delta**: accept, reject (duplicate / already covered), or refine.
5. **Apply accepted deltas (per the ledger mechanic above):**
   - **New lesson, no memory home** → write `<MEMORY_DIR>/{feedback,project,reference}_*.md` directly + one line to `MEMORY.md` (no PR; the auto-memory dir isn't in the repo), *then* add its ledger entry at `reinforced ×1`.
   - **Lesson already in memory** → increment its `<PLAYBOOK>` ledger entry (`+1 reinforced`, or `+1 contradicted`) and append the evidence line. A small `<PLAYBOOK>` edit → batched follow-up PR (see below).
   - **Repo-doc / skill-file edit** → follow-up PR. Owner reviews + merges.
   - **Mechanical / tool-specific** rule → its tool's home (plugin brief / qa rubric), not the ledger.
6. **Surface to owner** in the controller chat: brief summary of what landed + what was rejected with reasoning. If you post a `## Session Review` comment, put it **on the issue** (per the comment-placement contract above), not the PR.

## Constraints

- Don't propose memory entries for things derivable from `gh` / `git` / a live datastore (recall the repo's "what NOT to save" guidance if it has one).
- If the repo keeps a runtime-contract doc (e.g. `SPEC.md`) whose convention is "spec edits ride with their originating feature PR," do NOT put such edits in a review follow-up PR.
- One review pass per merged PR. If the PR has no `## Report` section, the review pass reports "no Report; nothing to review" and ends.
- Owner reviews + merges any `<PLAYBOOK>` / doc / skill-file follow-up PR; control never auto-merges those.

## When review triggers a follow-up PR

If multiple PRs in the same session each generate small playbook/skill edits, **batch them** rather than opening one PR per review — file a single "playbook touch-ups" follow-up PR that bundles the changes. Keeps PR noise down.
