# Changelog

All notable changes to the assets plugin are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [0.3.3] - 2026-05-26
### Documentation
- OSS-readiness redaction: dropped an internal agent codename from the `/btw` rule label in `assets-dispatch` (no behavior change).

## [0.3.2] - 2026-05-24
### Added
- CHANGELOG.md (this file); version-bump convention note in README.

## [0.3.1] - 2026-05-23
### Fixed
- `pr-completion-monitor` now fires on all-checks-terminal; surfaces a red/green verdict and failed check names. Previously the monitor hung indefinitely when the named highlight check was `paths-ignore`'d or when an unrelated check went red.
- `assets-dispatch` SKILL resolves `dispatch-asset` via `${CLAUDE_PLUGIN_ROOT}/bin/dispatch-asset` (correct for marketplace-cache and standard installs); removed hardcoded `~/.claude/plugins/assets/bin/…` path.
- Worktree dispatch: runs `uv sync --frozen` after `git worktree add` when a `uv.lock` is present at the worktree root.

## [0.3.0] - 2026-05-23
### Added
- `/init-assets-config` skill: scaffolds `config.yaml` from the bundled template, repo-local by default; `--global` writes the per-user fallback.
### Changed
- Canonical config path moved from `.assets/config.yaml` to `.claude/assets/config.yaml`; legacy path retained as a fallback with a deprecation warning.

## [0.2.7] - 2026-05-23
### Added
- `asset-heartbeat`: no-progress heartbeat that wakes the controller only when an asset looks stuck (pane frozen, on a permission prompt, or window vanished).
- `pr-completion-monitor`: fires when all CI checks reach a terminal state.

## [0.2.6] - 2026-05-22
### Changed
- `assets-dispatch` SKILL always composes the worktree path as `<config.paths.workdir>/worktrees/<branch-slug>` rather than accepting a raw path.
- Added writability pre-flight check and `git status` smoke-test after `git worktree add`.

## [0.2.5] - 2026-05-18
### Fixed
- Fixed Codex prompt dispatch.
### Changed
- Clarified controller-asymmetric comms overlap in docs.

## [0.2.4] - 2026-05-18
### Fixed
- Fixed per-launcher yolo flag selection.

## [0.2.3] - 2026-05-11
### Added
- Explicit signal-file and remote-path handling in dispatch SKILL; `/btw` section added to `assets-dispatch` SKILL.
### Changed
- OSS-readiness: marketplace registration, `.gitignore`, plugin test scaffolding.

## [0.2.2] - 2026-05-11
### Added
- Worktree-based dispatch section in `assets-dispatch` SKILL.

## [0.2.1] - 2026-05-02
### Changed
- Dispatch confirmation step auto-proposes model based on launcher config.

## [0.2.0] - 2026-05-01
### Added
- Remote-tmux support via SSH socket forwarding: `bin/ensure-tmux-forward` (idempotent socket manager) and `bin/send-prompt` (scp-based prompt delivery).

## [0.1.0] - 2026-05-01
### Added
- Initial plugin: local-tmux agent dispatch with spawn, continue, check, and recall lifecycle; config-driven launcher selection.
