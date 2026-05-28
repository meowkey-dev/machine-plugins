# Changelog

All notable changes to the sop-compact plugin are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

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
