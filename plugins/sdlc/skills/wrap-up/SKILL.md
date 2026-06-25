---
name: wrap-up
description: "The blessed post-PR close-out ritual — gate, merge (policy-respecting), review, and clean up a ready-to-merge closed-loop PR as ONE atomic action. Binds the per-PR review TO the merge so it can't be skipped. Trigger on \"wrap up the PR\", \"wrap up #N\", \"close out the PR\", or /wrap-up."
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Agent
---

# /wrap-up [<PR>] — post-PR close-out ritual

Outer-loop skill. The **single blessed close-out** for a ready-to-merge closed-loop PR: it
gates, merges (respecting merge policy), runs the per-PR review, and cleans up — as one ritual.

## Why this exists (and why it's the blessed merge path)

The per-PR `review` is lossy as a *separate* convention: a merge feels "done," so review gets
forgotten and the lesson only surfaces at the next `retro` (the lossy batch path). `wrap-up`
fixes that **by construction** — the same skill that merges also reviews, so you can't
merge-and-forget. Therefore:

> **A closed-loop PR is closed via `/wrap-up`, never raw `gh pr merge`.** Raw-merging skips the
> review — the exact lossiness this skill exists to prevent.

Being a *skill* (an agent action), it keeps the judging agent in the loop for the ledger
increment + contradiction-hunt — a headless hook/sidecar couldn't make those calls.

## Procedure

(`<PR>` = the PR number; if omitted, infer from the current branch's open PR or the most recent
ready asset PR — confirm before acting. `<MEMORY_DIR>` / `<PLAYBOOK>` per the `review` skill.)

1. **Pre-merge gate — never merge a red or unreviewed PR.**
   - `gh pr checks <PR>` → every check **terminal and green** (no `pending`/`fail`). If red or
     still running, STOP and surface — not ready.
   - Read the **latest** review-bot comment body **in full** — `bucket=pass` ≠ no findings (a
     status passes mechanically with real issues in the body). Confirm no unaddressed findings;
     if a newer bot pass landed after the last fix, read that one.
   - Confirm a `qa` pass exists and is `addresses-issue: YES`(or PARTIAL-but-accepted) +
     `coverage: SUFFICIENT`. If none exists, run the qa reviewer (Agent tool, `general-purpose`
     + the embedded `qa.md` rubric) for a pre-merge sweep.
   - Any unresolved finding / scope drift → STOP, surface to owner, do not merge.

2. **Merge-policy gate.** Read `prod_gated` from `.claude/sdlc.toml` (default false). If
   `prod_gated=true` AND this PR is a **real-world-action class** (deploy / arm / posture flip /
   model-promote, or whatever the repo gates) **AND the PR is not yet merged**, **STOP** — surface
   "owner merges this class directly, then re-run `/wrap-up <PR>`." (Once the owner has merged, this
   gate no longer applies — it passes and step 3's already-merged path completes the close-out.) Do
   **not** proceed to review/cleanup on the STOP: those steps tear
   down the asset's worktree/branch/monitors, which would orphan the still-open PR and break the
   owner's pending `gh pr merge`. Control **never** executes the merge for a gated class — no
   in-session verbal-approval escape hatch (a casual "yes, go ahead" is exactly the ambiguity
   `prod_gated` exists to remove; the owner runs `gh pr merge` / the action themselves). When the
   owner re-runs `/wrap-up` after merging, step 3 sees the PR already-merged and the close-out
   completes normally. For all **other** (non-gated) classes: assets never merge, and **control
   invoking `/wrap-up` IS the merge approval**.

3. **Merge** (idempotent). If the PR is **already merged** (owner merged a gated class, or it
   was merged out-of-band), skip the merge and continue — the close-out still runs review +
   cleanup. Otherwise `gh pr merge <PR> --squash` (or the repo's convention). Then verify the
   linked issue(s) auto-closed (`Closes #N`); if a close keyword didn't fire, close manually with a
   one-line reason.

4. **Sync.** `git checkout <default-branch> && git pull --ff-only`.

5. **Review (this is the `/review` ritual, folded in — see that skill for the full mechanic).**
   Consume the PR's `## Report`. The playbook is a **reinforcement ledger over memory**, so per
   accepted delta do exactly one of: `+1 reinforced` on an existing entry (+ evidence line),
   `+1 contradicted` (+ the case — the prune-or-revise signal), or write a new memory item
   first then add a fresh entry at `reinforced ×1` (A or B only — for C, write the memory item and stop; no ledger entry). (Ledger-eligible: A — methodology; B — reusable technique; C — static domain facts → memory-only; see `review` skill for the full scope.) **Run the contradiction-hunt**: did any
   merged work *contradict* an existing memory (a lesson that misled, a rule a finding
   overturned)? If none, say so deliberately. Memory writes go direct-to-disk; `<PLAYBOOK>`
   ledger edits batch into a ledger-update PR. Post the control `## Session Review` on the
   **issue** (comment-placement contract), not the PR. If the PR has no `## Report`, the review
   step reports "no Report; nothing to review" and is skipped.

6. **Cleanup.** Recall the asset (`assets-dispatch --recall <name>`, or `/exit` + kill its tmux
   window); remove its git worktree + delete the branch; stop its monitors (heartbeat /
   pr-completion / any watch); `rm` its signal + prompt files.

7. **Report to owner** (one line): merged `#<PR>` (`<sha>`), issue(s) closed, ledger ops
   applied, asset recalled — and the ledger-update PR number if one was opened.

## Constraints

- **The pre-merge gate is non-negotiable** — never merge a red or unreviewed PR; a clean
  `qa` does not license skipping the review body.
- **Respect `prod_gated`** — real-world-action classes stay owner-merged.
- **This is the blessed merge path** — close a loop PR via `/wrap-up`, not raw `gh pr merge`.
- The ledger-update PR that step 5 may open is itself closed out later, but it has no `## Report`,
  so its own `wrap-up` review step no-ops — no review-of-review loop.
- Control merges on the owner's behalf only for approved classes; everything else stays gated.
