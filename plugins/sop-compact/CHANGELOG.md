# Changelog

All notable changes to the sop-compact plugin are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [0.6.0] - 2026-06-11
### Added
- Per-repo opt-out for the PreCompact sidecar pipeline (machine#153). Two equivalent signals, either one suppresses bootstrap, snapshot, and the `.claude/sop-compact/` directory creation entirely:
  - **Marker file** `.claude/sop-compact/disabled` — primary, discoverable, commit-friendly (drop one in shared scratch/CI dirs to disable for everyone).
  - **Env var** `SOP_COMPACT_DISABLED=1` — escape hatch for ad-hoc shells / per-launcher wrappers.
- When either signal is present the hook exits 0 silently before any side effects; SessionStart on `source=compact` then falls back to its existing "no handoff found" pointer, same path as a fresh, never-compacted repo. Targets lightweight / throwaway sessions where the `opus[1m]` snapshot cost isn't justified.

## [0.5.0] - 2026-06-03
### Removed
- **Breaking-ish:** the `/init-sop-compact` user-invocable slash command (`skills/init-sop-compact/`). Folded into the PreCompact hook — the bootstrap step now happens automatically on the first compact in a fresh repo, so there's nothing to remember to run.
### Added
- PreCompact hook auto-bootstraps `.claude/sop-compact.md` on the first compact in a repo. Runs as a second `claude -p` sidecar (default `opus`, override via `SOP_COMPACT_MODEL`) BEFORE the snapshot sidecar — two sequential calls keep each prompt single-purpose and let bootstrap and snapshot carry independent time budgets.
- `hooks/lib/generate-sop.sh` shared helper carries the bootstrap logic so `pre-compact.sh` stays readable.
- `SOP_COMPACT_BOOTSTRAP_TIMEOUT` env override (default 300 s) for the bootstrap sidecar, separate from `SOP_COMPACT_TIMEOUT` (default 600 s) for the snapshot.
- Bootstrap auto-appends `.claude/sop-compact/handoff-*.md` to `.gitignore` (idempotent).
### Changed
- Failure policy: a failed *bootstrap* sidecar falls back to the legacy "stub handoff + exit 0" path (compaction proceeds, next compact retries) — never blocks. A failed *snapshot* still exit-2-blocks, same as before. Bootstrap errors land at `.claude/sop-compact/bootstrap-<ts>.error.log`.
- `SessionStart` no-handoff and legacy-snapshot pointers updated to reference the new auto-bootstrap path instead of suggesting `/init-sop-compact`.

## [0.4.3] - 2026-05-26
### Documentation
- OSS-readiness redaction: generalized the sidecar-pattern provenance comment in `pre-compact.sh` to drop a private source-repo path (no behavior change).

## [0.4.2] - 2026-05-25
### Documentation
- Clarify in README that SessionStart's `additionalContext` is queued for the next agent turn (which requires a user prompt) — the hook script itself runs immediately after compact, but the orientation directive isn't acted on until the user resumes the session.

## [0.4.1] - 2026-05-24
### Added
- CHANGELOG.md (this file); version-bump convention note in README.

## [0.4.0] - 2026-05-24
### Added
- Auto-prune old handoffs after each write: keeps the most recent N files (`SOP_COMPACT_HANDOFF_RETENTION`, default 10).
### Fixed
- Added PID suffix to handoff timestamp to prevent same-wall-second filename collisions when two compacts run concurrently.

## [0.3.4] - 2026-05-23
### Changed
- Default sidecar timeout raised 300 s → 600 s (opus[1m] over a long transcript can exceed 5 min).

## [0.3.3] - 2026-05-23
### Changed
- Default sidecar model changed to `opus[1m]` for 1 M-context reads; override via `SOP_COMPACT_MODEL`.

## [0.3.2] - 2026-05-23
### Fixed
- Moved `hooks.json` into the `hooks/` subdir so the plugin loader picks it up correctly.

## [0.3.1] - 2026-05-23
### Changed
- Handoff content is now extracted via sentinels to scope what the sidecar narrates.

## [0.3.0] - 2026-05-22
### Added
- Initial `sop-compact` plugin (hooks-only rewrite of `compact-sop`): works with a bare `/compact` (manual or auto), no user-typed step needed.
- `/init-sop-compact` skill: generates a per-repo `.claude/sop-compact.md` (one-time setup).
- PreCompact hook: runs a `claude -p` sidecar to promote durable learnings and write a handoff snapshot; hard-blocks compaction (exit 2) if the sidecar fails.
- SessionStart hook (gated on `source=compact`): emits a pointer-only directive to the latest handoff.
- PostCompact hook: archives the compact summary to `.claude/sop-compact/summaries/`.
