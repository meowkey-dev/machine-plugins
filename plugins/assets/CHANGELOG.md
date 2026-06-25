# Changelog

All notable changes to the assets plugin are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [0.4.0] - 2026-06-10
### Added
- `bin/asset-signal`: harness-emitted lifecycle signals for the dispatched asset. Writes
  `boot` / `turn_end` / `exit` JSONL events to `<signals>/<name>.jsonl` and touches
  `<signals>/<name>.activity` on every tool call. Always exits 0 — a signal-write failure
  never breaks the asset's hook chain.
- `dispatch-asset --name <name>` flag to label harness-emitted signal files explicitly
  (falls back to tmux window name, else `unknown-<pid>`).
- `monitoring.harness_signals` config knob (default `true`, env `ASSETS_HARNESS_SIGNALS`):
  for **claude-family launchers only**, generate a settings file wiring SessionStart /
  PostToolUse / Stop / SessionEnd hooks to `asset-signal` and pass it via `--settings`.
  Settings file persists under `<signals>/.settings/<name>.json` for CC's lifetime.

### Changed
- **Completion signaling is deterministic on the claude-family path.** Replaces the
  prompt-mutated `<signals>/<name>.done` shim (Step 4 of the dispatch SKILL) for claude
  launchers. The `turn_end` event includes a 500-char excerpt of the asset's actual final
  assistant message — extracted from the Stop hook's `last_assistant_message` field, with
  a JSONL-transcript fallback. Non-claude launchers (codex / aider / etc.) keep the
  existing prompt-injected `.done` path.
- **Liveness signal is deterministic on the claude-family path.** The activity file's
  mtime advances on every tool call, so a stale mtime is proof of no-progress rather than
  a pane-content heuristic. `bin/asset-heartbeat` (the pane-diff detector) is retained as
  the recommended path for non-claude launchers.
- `assets-dispatch` SKILL: Step 4 split per launcher family; Step 10/12 monitoring sections
  rewritten to describe the JSONL stream + activity mtime check for claude assets; Step 9
  always passes `--name <name>` through to `dispatch-asset`; recall cleanup removes the
  new `<name>.jsonl`, `<name>.activity`, and `.settings/<name>.json` files.

### Fixed
- Surfaced a silent-no-op trap: `dispatch-asset` runs in the asset's pane with
  `cwd=paths.workdir`, so `_config.sh` walks up from there and cannot see the
  controller's repo-local config. Without a global config or env passthrough,
  `SIGNALS_DIR` resolved empty and the injection block silently no-op'd. The
  launcher now emits a stderr warning naming the unresolved cwd and the env
  fix. The `assets-dispatch` SKILL Step 9 prefixes the send-keys command with
  `ASSETS_SIGNALS_DIR='<resolved>' ASSETS_HARNESS_SIGNALS=<resolved>` so the
  controller's resolved config crosses the pane boundary deterministically.

### Notes
- No tmux behavior changes (no `remain-on-exit`); process-death is still covered
  controller-side via the window-existence check.
- Clean break to JSONL — no legacy `.done` compatibility shim on the claude path.
- Probed against CC 2.1.170: all four hooks fire under both interactive and `claude -p`
  non-interactive mode; `Stop` already includes `last_assistant_message` directly, so the
  transcript-parse path is a defense-in-depth fallback.

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
