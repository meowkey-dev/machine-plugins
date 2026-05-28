# Upgrading sdlc

The `schema_version` in a consuming repo's `.claude/sdlc.toml` (default `1` if the file or
field is absent) declares which playbook/artifact contract the repo is on. A **breaking** change
to that contract bumps the version here and ships a migration section below. After completing a
migration, set `schema_version` to the new value in your `.claude/sdlc.toml`.

A control agent that finds its repo's `schema_version` *behind* the plugin's current schema should
read the relevant section(s) below and run the migration before relying on `review`/`retro`.

---

## schema_version 1 → 2 — PLAYBOOK becomes a reinforcement ledger over memory (sdlc 0.3.0)

**What changed.** `PLAYBOOK.md` was a free-prose lesson store. It is now a **reinforcement ledger
over memory**: each entry is `[[memory-slug]] · reinforced ×N · contradicted ×M` + a dated evidence
log. The *rule itself* lives in a memory file (`<MEMORY_DIR>/<slug>.md`); PLAYBOOK restates no
content — it carries only the up/down signal. `review`/`retro` now maintain it by incrementing
counts (never writing prose); see those skills' "reinforcement ledger" sections.

**Why.** A prose PLAYBOOK duplicates memory and bloats (it bifurcates the learning store and blows
the memory index cap). The ledger adds the one ACE primitive memory lacked — a running evidence
counter + a contradiction signal (any `contradicted ×M>0` is the prune-or-revise flag) — without
copying a single line of content.

**Migrate your repo** (one PR for `PLAYBOOK.md` + direct-to-disk memory writes that aren't in the
PR — the auto-memory dir lives outside the repo):

1. **Map each prose lesson to a memory item.** For every lesson currently in `PLAYBOOK.md`:
   - already covered by a memory file → note its slug;
   - not in memory → write a `{feedback,project,reference}_*.md` in your memory dir (statement +
     why + how-to-apply) and add a one-line entry to `MEMORY.md`.
2. **Rewrite each prose block as a ledger entry:**
   ```
   ### [[slug]] — short title
   `domain` · reinforced ×N · contradicted ×M
   - <PR/issue> — <one-line firing context>   (newest last; N = number of reinforced bullets)
   ```
3. **Backfill counts conservatively** — only from provenance the prose already cites. One incident
   may legitimately reinforce several distinct rules.
4. **Route mechanical / tool-specific rules out** (e.g. a shell-quoting rule) to their tool's home —
   the dispatch brief or `qa.md` — not the ledger. The ledger holds *generalizable methodology* only.
5. **Add a header** to `PLAYBOOK.md` documenting the model + the increment mechanic, and **set
   `schema_version = 2`** in `.claude/sdlc.toml`.

**Worked reference:** a downstream private project ran this migration in a single PR (artifact
migration) paired with ~6 `feedback_*` memory items; the resulting `PLAYBOOK.md` is a complete
example of the ledger format. Design rationale: `meowkey-dev/machine#126`.
