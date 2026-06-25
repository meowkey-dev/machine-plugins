# sop-compact

Survive a Claude Code `/compact` without losing the high-value, non-reconstructable context a
session builds up — **with no user-typed step at compaction time**. v0.3.0 was a hooks-only
rewrite of the older `compact-sop` plugin; v0.5.0 folded the last remaining setup step
(`/init-sop-compact`) into the PreCompact hook itself, so even the very first compact in a
fresh repo just works. There is nothing to remember to run before you compact, and nothing to
run once per repo either.

## What problem this solves

A `/compact` lossily rewrites the conversation into a summary. The first things it drops are
exactly the things that took the whole session to build: active framings, in-flight design
reasoning, rejected approaches and *why*, shared language, relationship/tonal context. File
contents, PR state, and memory are reconstructable on demand — those framings are not.

The fix is a three-step loop: before compacting, **promote** durable learnings and **snapshot**
in-flight state; then, on the way back in, **re-orient** against the snapshot before doing
anything. The old plugin made each step a SKILL you invoked. This version moves the whole loop
into hooks so it happens around a plain `/compact` automatically.

## The surfaces

### PreCompact hook — bootstrap (first compact only) + promote + snapshot (automatic)

- **When:** fires before every `/compact` (manual or auto). PreCompact is *awaited*, so CC
  waits for it to finish before summarizing.
- **First-compact bootstrap (new in v0.5.0):** if `.claude/sop-compact.md` is missing, a
  bootstrap `claude -p` sidecar runs *first* (default `opus`, override via
  `SOP_COMPACT_MODEL`; default timeout 300 s, override via `SOP_COMPACT_BOOTSTRAP_TIMEOUT`).
  It reads the plugin's template skeleton + this repo's `CLAUDE.md` / memory dirs, fills in
  the repo-specific bullets, and writes `.claude/sop-compact.md` atomically. It also appends
  `.claude/sop-compact/handoff-*.md` to `.gitignore`. The bootstrap and snapshot run as **two
  sequential sidecars**, not one fused prompt — each has one job, time budgets stay
  independent, and the bootstrap cost only lands once per repo.
- **Snapshot:** runs a `claude -p` sidecar (`opus[1m]` by default; override with
  `SOP_COMPACT_MODEL`) that reads `.claude/sop-compact.md` + the just-finished transcript,
  **promotes** principled learnings to this repo's durable targets via direct file edits, and
  writes a dense **handoff** to `.claude/sop-compact/handoff-<ts>.md`.
- **Failure handling:** if the *snapshot* sidecar fails (non-zero exit or empty output) the
  hook writes a debug log and **exits 2**, which hard-blocks the compaction — you keep the
  live context and know the snapshot failed, rather than silently compacting into a lossy
  summary. If the *bootstrap* sidecar fails on a first-compact repo, the hook writes a stub
  handoff and **exits 0** (never blocks): a failed bootstrap should not eat your live context,
  and the next compact will retry. The bootstrap error log lands at
  `.claude/sop-compact/bootstrap-<ts>.error.log`.
- **Timeout:** the sidecar is wrapped in `timeout` (default 600s, override with
  `SOP_COMPACT_TIMEOUT`). Since PreCompact is awaited, an unbounded sidecar would hang
  `/compact` indefinitely; on expiry the timeout fails clean (rc 124 → exit 2). The default
  is 600s because the sidecar runs `opus[1m]` over the whole transcript — a 1M-context
  read + promote + snapshot on a long session can exceed 5min, and a too-short wall would
  exit-2-block compaction on exactly the sessions this plugin is for.

### SessionStart hook (gated on `source=compact`) — orientation (automatic)

- **When:** the hook script itself runs the moment `/compact` finishes, before any further
  user input. No-op for every other session start (`startup`, `resume`, `clear`).
- **What it does:** finds the latest `handoff-*.md` and emits a **pointer-only**
  `additionalContext` directive telling the new session to read it before doing anything.
  Pointer, not full content — minimalism by design.
- **When the agent actually reads it:** the `additionalContext` payload is **queued for the
  next agent turn**, which doesn't fire until the user prompts the new session. There is no
  autonomous post-compact turn — CC doesn't run the agent again on its own. So the
  orientation directive sits staged until you come back and type something; then the
  agent's first turn sees the directive, reads the handoff, and orients before responding.
  The handoff file is written to disk and readable by external tools (or `cat`) even if
  the session never resumes — subject to the retention policy (default: keep the 10 most
  recent handoffs per repo, see `SOP_COMPACT_HANDOFF_RETENTION`). A dormant session's
  handoff can fall out of the window if 10+ subsequent compacts run in the same repo
  before resumption.

## Where things live (the two-name rule)

- **`<repo>/.claude/sop-compact.md`** — static, per-repo, **committed**. The procedure.
  Auto-generated on first compact by the PreCompact hook's bootstrap sidecar; edit and commit
  it freely thereafter (just delete it and the next compact will regenerate it from scratch).
- **`<repo>/.claude/sop-compact/handoff-<ts>.md`** — dynamic, ephemeral, **git-ignored**.
  Written by the PreCompact sidecar, read by the SessionStart hook.

## Extension hooks (per-deployment overlays)

The generic plugin doesn't bake in deployment-specific checks. Two optional repo-local
extension points run if present:

- `<repo>/.claude/sop-compact/pre.sh` — sourced by the PreCompact hook *after* a successful
  snapshot. Gets `SOP_COMPACT_HANDOFF` and `SOP_COMPACT_TRANSCRIPT` in its env.
- `<repo>/.claude/sop-compact/post.sh` — run by the SessionStart hook on `source=compact`.
  Gets `SOP_COMPACT_HANDOFF` in its env. Its stdout is discarded (the hook's stdout is the
  orientation JSON).

Both run guarded (`set +e`) so a failing extension never takes down the hook.

## Install

```
/plugin install sop-compact@machine
```

That's it — no per-repo init step. On the first `/compact` in each repo, the PreCompact hook
auto-generates `.claude/sop-compact.md` before running the snapshot sidecar. Subsequent
compacts skip the bootstrap and just run the snapshot.

## Configuration

### Per-repo opt-out (v0.6.0)

Once `sop-compact` is installed user-level, every `/compact` in every repo fires the
`claude -p` sidecar — great for long heavy sessions in working repos, unwanted overhead
for lightweight or throwaway sessions (a `/tmp/scratch-dir`, a one-file edit, a quick
`claude` in an unrelated dir). Two equivalent signals disable the entire PreCompact
pipeline for a single repo without disabling the plugin everywhere; either is enough:

- **Marker file** — `touch .claude/sop-compact/disabled`. Discoverable, version-
  controllable: commit it in shared scratch / CI dirs to disable for everyone who
  checks out that tree. This is the primary mechanism.
- **Env var** — `SOP_COMPACT_DISABLED=1` honoured at hook-invocation time. Escape hatch
  for ad-hoc shells or for wiring a "lightweight claude" launcher alias / `.env`.

When either is present the PreCompact hook exits 0 silently **before** bootstrap,
**before** the snapshot sidecar, and **before** the `.claude/sop-compact/` directory is
created — a disabled repo never acquires the plugin's on-disk footprint, and `/compact`
behaves as if the plugin weren't installed. SessionStart on `source=compact` then takes
its existing no-handoff path (the same path a never-compacted repo takes).

To re-enable: `rm .claude/sop-compact/disabled` and/or unset `SOP_COMPACT_DISABLED`.

### Environment variables

| Variable | Default | Effect |
| --- | --- | --- |
| `SOP_COMPACT_DISABLED` | unset | Set to `1` to disable the PreCompact pipeline for this shell. |
| `SOP_COMPACT_MODEL` | `opus[1m]` (snapshot) / `opus` (bootstrap) | Override the sidecar model. |
| `SOP_COMPACT_TIMEOUT` | `600` | Snapshot-sidecar wall-time budget (seconds). |
| `SOP_COMPACT_BOOTSTRAP_TIMEOUT` | `300` | Bootstrap-sidecar wall-time budget (seconds). |
| `SOP_COMPACT_HANDOFF_RETENTION` | `10` | Keep the N most recent handoffs per repo (`< 1` = no-op). |

## Migration from compact-sop

`sop-compact` replaces `compact-sop` (hard cutover — `compact-sop` is removed from the
marketplace in the same change). To migrate:

1. `/plugin uninstall compact-sop@machine`
2. `/plugin install sop-compact@machine`
3. Trigger one `/compact` in each repo where you had a `.claude/sop.md`. The new
   `.claude/sop-compact.md` will be auto-bootstrapped from the v0.5.0 template (the schema is
   different from the v0.2.x `sop.md`, so regenerating beats renaming).

What changed:

- **No more `/prep-compact`.** The pre-compact Promote+Snapshot now runs automatically in the
  PreCompact hook's sidecar.
- **No more `/init-sop-compact`** (removed in v0.5.0). The PreCompact hook now bootstraps
  `.claude/sop-compact.md` on the first compact in a fresh repo.
- **The `/compact <argument>` story is dropped.** v0.2.x emitted a KEEP/DROP argument for you
  to paste; this version assumes bare `/compact`. (CC can't let a PreCompact hook modify the
  `/compact` argument, and the Skill tool can't invoke `/compact` — so the typed-argument flow
  never closed the loop. The sidecar + handoff approach closes it without a typed step.)
- **Snapshots moved** from `~/.claude/compact-sop/snapshots/` (or `/tmp/`) into the repo at
  `.claude/sop-compact/handoff-*.md`. For one cycle, the SessionStart hook still falls back to
  the old v0.2.x snapshot locations (`${COMPACT_SOP_SNAPSHOT_DIR:-~/.claude/compact-sop/snapshots}`
  and `/tmp/`) if no in-repo handoff is found, labelling them as legacy.

## How to wire without the plugin

Copy the pieces into a repo's `.claude/`:

- `templates/sop-compact.md.tmpl` → `.claude/templates/sop-compact.md.tmpl`
- `hooks/*.sh` and `hooks/lib/generate-sop.sh` → `.claude/hooks/` (preserving the `lib/`
  subdir; `chmod +x` the top-level scripts)

Then add to `.claude/settings.json`:

```json
{
  "hooks": {
    "PreCompact": [{"hooks": [{"type": "command", "command": ".claude/hooks/pre-compact.sh"}]}],
    "SessionStart": [{"matcher": "*", "hooks": [{"type": "command", "command": ".claude/hooks/session-start.sh"}]}]
  }
}
```

## Requirements

- `jq` (hooks parse stdin with it).
- `claude` on PATH (the PreCompact hook shells out to it for both the bootstrap and snapshot sidecars).
- `timeout` (coreutils) — bounds the PreCompact sidecar.

## Security note

The PreCompact sidecar runs with `--dangerously-skip-permissions` and reads the just-finished
transcript, which contains verbatim session content (user messages, tool output, external
data). That makes the transcript untrusted input reaching an agent with broad tool access.
This is accepted deliberately: the same transcript was already read in full by the main
session that produced it, so the sidecar gains no privilege over the repo that the original
session didn't already have. Broad access is required because promotion targets aren't
confinable to a fixed subtree (`CLAUDE.md` is at the repo root; per-project memory can live
outside the repo under `~/.claude/projects/...`) and the prompt samples large transcripts via
`head`/`grep`. The `timeout` wrapper bounds runaway behavior. If you need a stronger boundary,
run the sidecar in a sandbox or restrict promotion to in-repo paths. See the header comment in
`hooks/pre-compact.sh`.

## Provenance

The `claude -p` sidecar invocation pattern is adapted from `cc-session`'s `sop` subcommand
(`_call_claude_sop` / `_build_sop_prompt`). Hook behavior was verified against Claude Code
2.1.149 — see the probe report referenced in [#108](https://github.com/meowkey-dev/machine/issues/108).

## Changelog & versioning

Every version bump requires a `CHANGELOG.md` entry. A breaking change additionally requires
an `UPGRADING.md` section (plus a `schema_version` bump for schema-keyed plugins).
Enforced by `tests/test_structure.sh`.
