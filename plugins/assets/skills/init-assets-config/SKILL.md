---
name: init-assets-config
description: Create the assets plugin's config file from the bundled template. Defaults to repo-local <repo>/.claude/assets/config.yaml; --global writes ~/.claude/plugins/assets/config.yaml. Refuses to overwrite without --force. Trigger on /init-assets-config.
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash(git rev-parse *)
  - Bash(mkdir *)
  - Bash(cp *)
  - Bash(ls *)
  - Bash(test *)
  - Bash(cat *)
  - Bash(pwd *)
  - Bash(dirname *)
---

# /init-assets-config — Scaffold the assets config from the bundled template

Create the assets plugin's `config.yaml` from the bundled `config.example.yaml`. By default this
writes a **repo-local** config at `<repo-root>/.claude/assets/config.yaml` (issue #127 — aligns
with the `.claude/` convention). Use `--global` to write the per-user config at
`~/.claude/plugins/assets/config.yaml` instead.

## Arguments

```
/init-assets-config              — repo-local: <repo-root>/.claude/assets/config.yaml
/init-assets-config --global     — global: ~/.claude/plugins/assets/config.yaml
/init-assets-config --force      — overwrite an existing config (combine with --global if needed)
```

Parse `--global` and `--force` from the invocation arguments (order-independent; both may be
present). Anything else is unrecognized — surface a usage line and stop.

## Procedure

1. **Resolve the target path.**
   - If `--global` was passed: `TARGET="${HOME}/.claude/plugins/assets/config.yaml"`.
   - Otherwise, find the git repo root:
     ```bash
     git rev-parse --show-toplevel
     ```
     - If this succeeds (exit 0), `TARGET="<repo-root>/.claude/assets/config.yaml"`.
     - If it fails (not inside a git repo), fall back to the global path
       `TARGET="${HOME}/.claude/plugins/assets/config.yaml"` and tell the user no git repo was
       detected so the config went global.

2. **Check target existence.**
   ```bash
   test -f "$TARGET"
   ```
   - If it exists and `--force` was NOT passed: refuse. `cat "$TARGET"` so the user sees the
     current config, tell them it already exists and `--force` is required to overwrite, and stop
     (this is a successful no-op, not an error).
   - If it exists and `--force` WAS passed: proceed (overwrite below).
   - If it does not exist: proceed.

3. **Resolve the source template.**
   - `SOURCE="${CLAUDE_PLUGIN_ROOT}/config.example.yaml"`. This env var is set in the SKILL's
     Bash context and resolves to the version-pinned plugin install dir.
   - Verify it exists (`test -f "$SOURCE"`). If `$CLAUDE_PLUGIN_ROOT` is unset or the file is
     missing, stop with a clear error — do not write a partial config.

4. **Create the target and copy.**
   ```bash
   mkdir -p "$(dirname "$TARGET")"
   cp "$SOURCE" "$TARGET"
   ```

5. **Print the "now edit these fields" hint.** Tell the user the config was written to `$TARGET`
   and that the minimum required fields to edit before first dispatch are:
   - `tmux.socket` — path to your tmux server socket
   - `tmux.session` — the tmux session name assets run in
   - `paths.workdir` — where asset clones live (must NOT be the controller's cwd)
   - `paths.signals` — the signal-file directory for completion monitoring

   Mention they can `Read` `$TARGET` to see the full annotated schema (the template is commented),
   and that repo-local config overrides global field-by-field.

## Notes

- Repo-local is the default because most assets config is project-shaped (workdir, signals,
  launcher map per repo); `--global` is for the per-user fallback that repo-local configs layer on
  top of.
- This SKILL only scaffolds the file — it does not validate field values. Editing is the user's
  job; the dispatch SKILL surfaces missing-required-field errors at dispatch time.
