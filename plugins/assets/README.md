# assets

Drive long-running coding agents in a local tmux session from a controlling Claude Code instance.

Spawn agents ("assets") in dedicated tmux windows, monitor completion via signal files, and recover
from stuck states — without keeping the controlling session busy waiting. The pattern: fire-and-forget
dispatch, asynchronous health check, signal-file wakeup.

## Install

```
/plugin install assets@machine
```

## How it works

The controlling agent (your CC session) reads config and picks a launcher based on the per-command
rules in the `launchers` list. The bundled `dispatch-asset` script is a dumb shim: it trusts
`--launcher`, verifies the command exists in PATH, sets up the workdir / env / flags, and `exec`s
the agent CLI. Launcher selection is the agent's job; the script just executes.

Layered config (local `<repo>/.claude/assets/config.yaml` > global `~/.claude/plugins/assets/config.yaml`)
governs paths, approval, and monitoring — not launcher selection.

## Configuration

Assets reads config from two locations, merged field-by-field (local overrides global):

| Location | Purpose |
|---|---|
| `~/.claude/plugins/assets/config.yaml` | Per-user global config |
| `<repo>/.claude/assets/config.yaml` | Repo-local override (canonical) |
| `<repo>/.assets/config.yaml` | Repo-local override (legacy fallback — see below) |

A repo-local file that only sets `tmux.socket` does not need to repeat the `launchers` list from
the global file. Env vars provide a per-field ultimate fallback (see `config.example.yaml`).

Scaffold a config from the bundled template with `/init-assets-config`:

```
/init-assets-config            # repo-local: writes <repo>/.claude/assets/config.yaml (default)
/init-assets-config --global   # global:     writes ~/.claude/plugins/assets/config.yaml
```

Repo-local is the default — most config is project-shaped (workdir, signals, per-repo launcher
map), and a repo-local file layers field-by-field over the global one. `--global` writes the
per-user fallback. Pass `--force` to overwrite an existing config. Then edit the file to point at
your own tmux socket, workdir, signals dir, and launcher commands.

### Legacy config path (back-compat)

The repo-local config used to live at `<repo>/.assets/config.yaml`. As of v0.3.0 the canonical
path is `<repo>/.claude/assets/config.yaml` (aligns with the `.claude/` convention). The legacy
path still works as a fallback, but emits a one-line deprecation warning to stderr:

```
assets: using legacy <repo>/.assets/config.yaml; move to <repo>/.claude/assets/config.yaml at your leisure (legacy path support drops in v0.4.0)
```

Move the file (`mkdir -p .claude/assets && git mv .assets/config.yaml .claude/assets/config.yaml`)
at your leisure; the fallback is removed in v0.4.0.

### Minimal config

```yaml
tmux:
  socket: /home/user/work/tmux.sock
  session: assets

paths:
  workdir: /home/user/work
  signals: /home/user/work/signals

launchers:
  - command: claude
    rule: "Default launcher."
```

### Launcher map

Each `launchers` entry has a `command` (the agent CLI binary) and a `rule` (a one-line description
of when to use it). The controlling agent reads these rules from config and picks the right launcher
per task — the `dispatch-asset` script itself does not validate or interpret the list.

```yaml
launchers:
  - command: claude
    rule: "Default. Use unless the task requires a non-Anthropic-API auth path."
  - command: codex
    rule: "Use for OpenAI-API-authed work or A/B comparison vs CC on the same task."
```

### Model selection

The dispatch SKILL proposes a model (`--model <id>`) alongside the launcher in the confirmation
before each new dispatch. The choice is based on task complexity — opus-tier for heavy reasoning,
haiku-tier for routine work, sonnet-tier as the default. The user can override before confirming.
The launcher script passes `--model` through to the underlying CLI; supported by `claude`, `codex`,
`aider`, and most other CLIs that accept `--model` as a standard flag.

### Worktree-based dispatch

For filesystem isolation (multiple branches in parallel, exploratory experiments without touching
main checkout), the SKILL manages git worktrees and dispatches into them via the existing
`--workdir` flag. No launcher changes needed — works with any launcher. See the `assets-dispatch`
SKILL's "Worktree-based dispatch (optional)" section for the create/invoke/cleanup lifecycle.

### Launcher override

For esoteric needs, set `paths.launcher` to a custom script. The plugin calls it with the same
`--launcher` / `--prompt` contract as the bundled `dispatch-asset`:

```yaml
paths:
  launcher: /path/to/my/dispatch-script
```

### Approval style

The `approval.style` field controls how the controlling agent asks for permission before dispatching:

- `ui` (default): uses the standard Claude Code interactive permission prompt.
- `verbal`: the agent asks in the chat conversation and waits for a conversational yes/no.

```yaml
approval:
  style: verbal
  new_dispatch: required
```

## First dispatch walkthrough

This walkthrough takes you from a clean install to a dispatched hello-world agent.

**Prerequisites:**
- A running tmux server with a named session. Example: `tmux -S /home/user/work/tmux.sock new-session -d -s assets`
- The `claude` CLI (or another agent CLI) in your PATH.

**1. Clone the target repo into your workdir.**

Assets should operate from a separate clone — not from the same cwd as your controlling session.
This prevents MCP connection collisions (see Anti-patterns).

```bash
cd /home/user/work
git clone git@github.com:example/myrepo.git
```

**2. Write a minimal config.**

```bash
mkdir -p ~/.claude/plugins/assets
cat > ~/.claude/plugins/assets/config.yaml <<'EOF'
tmux:
  socket: /home/user/work/tmux.sock
  session: assets

paths:
  workdir: /home/user/work
  signals: /home/user/work/signals

launchers:
  - command: claude
    rule: "Default launcher."
EOF
mkdir -p /home/user/work/signals
```

**3. Write a hello-world prompt.**

```bash
cat > /tmp/hello-asset.txt <<'EOF'
Echo "hello from the asset" to stdout.

When done, write a one-line summary to /home/user/work/signals/hello.done
EOF
```

**4. Dispatch.**

In your Claude Code session:

```
/assets-dispatch hello /tmp/hello-asset.txt
```

The skill will:
- Show you the config and launcher, ask for approval
- Create a tmux window named `hello` in the `assets` session
- Launch the agent on your prompt
- Set up signal-file monitoring and a 10-minute health check

**5. Check the tmux window.**

In a terminal:

```bash
tmux -S /home/user/work/tmux.sock attach -t assets
```

You should see the `hello` window with the agent running.

**6. Wait for the signal file.**

The agent writes to `/home/user/work/signals/hello.done` when it finishes. The monitoring loop
in the controlling session will report completion when that file appears.

**7. Recall.**

```
/assets-dispatch hello --recall
```

This sends `/exit` to the agent, waits 3 s, kills the tmux window, and removes the signal file.

---

## Going remote

Assets can drive agents on a remote machine — beefier hardware, persistent box, isolation from the
laptop — without changing the controlling-agent ergonomics. Two approaches:

### Case 1: socket pre-prepared (zero plugin changes)

Set up the SSH socket forward yourself, either in `~/.ssh/config`:

```
Host my-remote-box
  LocalForward /home/user/work/remote.sock /home/user/tmux.sock
```

Or as a one-liner per session:

```bash
ssh -fN -L /home/user/work/remote.sock:/home/user/tmux.sock my-remote-box
```

Then point the plugin at the forwarded socket — no `tmux.remote` block needed:

```yaml
tmux:
  socket: /home/user/work/remote.sock
  session: assets
```

The plugin sees a normal local socket file. Everything works as in v0.1. This is the simplest
approach if you already manage SSH connections yourself.

### Case 2: plugin manages the forward

Add a `tmux.remote` block to your config and the plugin handles the SSH forward automatically:

```yaml
tmux:
  socket: /tmp/assets-fwd.sock
  session: assets
  remote:
    host: my-remote-box
    socket: /home/user/tmux.sock
    ssh_opts: ["-i", "~/.ssh/id_ed25519"]
```

Before every tmux operation (dispatch, check, recall), the plugin runs `bin/ensure-tmux-forward`.
This helper is idempotent — it checks whether the forward is healthy, reaps stale connections,
and only spawns a new SSH process when needed. Typical happy-path overhead: <100ms.

#### Prerequisites

Before your first remote dispatch, ensure:

- [ ] **SSH key auth** to the remote host (no interactive passwords — the forward runs detached)
- [ ] **tmux installed** on the remote, with a server running at the configured socket path
      (`tmux -S /home/user/tmux.sock new-session -d -s assets`)
- [ ] **Launcher binary on remote PATH** (e.g. `claude`, `codex`, `aider`)
- [ ] **Workdir is a git repo on the remote** — clone it once; `git pull` between dispatches

Auth tokens for the launcher (e.g. API keys) are your responsibility — set them via `.env` in
the workdir or remote-side environment variables.

#### First remote dispatch walkthrough

**1. Prepare the remote box.**

```bash
ssh my-remote-box
tmux -S /home/user/tmux.sock new-session -d -s assets
cd /home/user
git clone git@github.com:example/myrepo.git work
# ensure 'claude' (or your launcher) is in PATH
exit
```

**2. Write config on the controlling machine.**

```bash
cat > ~/.claude/plugins/assets/config.yaml <<'EOF'
tmux:
  socket: /tmp/assets-fwd.sock
  session: assets
  remote:
    host: my-remote-box
    socket: /home/user/tmux.sock

paths:
  workdir: /home/user/work
  signals: /home/user/work/signals

launchers:
  - command: claude
    rule: "Default launcher."
EOF
```

**3. Write a hello-world prompt.**

```bash
cat > /tmp/hello-remote.txt <<'EOF'
Echo "hello from the remote asset" to stdout.

When done, write a one-line summary to /home/user/work/signals/hello.done
EOF
```

**4. Dispatch.**

```
/assets-dispatch hello /tmp/hello-remote.txt
```

The plugin will:
- Run `ensure-tmux-forward` to establish the SSH socket forward
- Run `send-prompt` to copy the prompt file to the remote
- Create a tmux window on the remote and launch the agent

**5. Verify.**

```bash
ssh my-remote-box "tmux -S /home/user/tmux.sock list-windows -t assets"
```

#### Sync model: git, not shared FS

Assets uses **git as the sync mechanism** between controller and remote. The remote workdir is a
normal git clone. Between dispatches, pull changes; the dispatched agent pushes its work. This is
simpler and more robust than shared-filesystem approaches (sshfs, NFS) and works across any network.

Workdir creation on the remote is your responsibility — clone once, then `git pull` as needed.

---

## Skills reference

### `/assets-dispatch`

Core lifecycle skill. Handles spawn, continue, check, and recall.

```
/assets-dispatch <name> <prompt-file>               — new asset
/assets-dispatch <name> --continue "message"        — send message to running asset
/assets-dispatch <name> --check                     — check status (via subagent peek)
/assets-dispatch <name> --recall                    — exit and clean up
```

Flags for new dispatch: `--launcher <command>`, `--safe`, `--teams`, `--model <model>`,
`--monitor signal|cron <N>|none`.

### `/assets-pr-review`

Dispatch-derived skill for the PR review iteration loop. Generates a structured prompt and calls
`/assets-dispatch`. The asset runs the full loop autonomously: check comments → fix → push →
reply → resolve → repeat until clean.

```
/assets-pr-review <owner/repo> <pr-number> [--launcher <command>]
```

---

## Anti-patterns

These are patterns that cause hard-to-diagnose failures. Read them before your first dispatch.

### 1. MCP collision when spawning from the controller's cwd

If the controlling session and the spawned agent both run from the same working directory, they
share the same MCP plugin connections (Discord, Zulip, tmux-sse, etc.). The result: tool-call
collisions, lost messages, and tmux-pane confusion that is very hard to untangle.

**Always spawn assets from a separate workdir** — a clean clone or a dedicated directory configured
in `paths.workdir`. The bundled `dispatch-asset` script enforces this by `cd`-ing to `paths.workdir`
before launching. Never override this with the controller's own directory.

### 2. The container-shell-is-fish trap

If your CC session or tmux shell is fish, `source`-ing a bash script fails silently or errors in
confusing ways — fish does not implement the bash `source` semantics.

**Always execute `dispatch-asset` directly**, never source it. The tmux send-keys invocation in
the dispatch skill does this correctly:

```bash
tmux send-keys ... "bash /path/to/dispatch-asset --launcher claude --prompt /tmp/task.txt" Enter
```

If you customize the launcher, make sure your custom script is also directly executable (has a
shebang, `chmod +x`), and call it via its path, not via `source`.

### 3. Yolo-mode-disabling-via-config-write footgun

Writing `.mcp.json` or any other config file in the cwd *during* an agent session silently disables
`--dangerously-skip-permissions` (yolo mode). The agent gets permission prompts for every tool call
and appears frozen.

This happens because CC re-reads config on each tool call and sees the new file. It is not a bug;
it is intentional security behavior. But it is surprising when it happens mid-task.

**Recovery dance** (via tmux send-keys from the controlling session):

1. Approve the current blocked prompt: `tmux send-keys -t <session>:<name> Enter`
2. Re-enable yolo: `tmux send-keys -t <session>:<name> S-Tab S-Tab`

The double `Shift+Tab` cycles the permission level back to "always allow." Repeat if the agent
gets blocked again (each config-file write is a separate trigger).

**Mitigation:** If your agent task involves writing config files (`.mcp.json`, `settings.json`,
etc.), either run with `--safe` from the start (accept permission prompts) or gitignore those
files in the asset's clone so CC doesn't see them.

---

## Config reference

See [`config.example.yaml`](./config.example.yaml) for the full annotated schema.

| Field | Default | Env var |
|---|---|---|
| `tmux.socket` | — (required) | `ASSETS_TMUX_SOCKET` |
| `tmux.session` | — (required) | `ASSETS_TMUX_SESSION` |
| `tmux.remote.host` | — (optional) | — |
| `tmux.remote.socket` | — (optional) | — |
| `tmux.remote.ssh_opts` | `[]` | — |
| `paths.workdir` | — (required) | `ASSETS_WORKDIR` |
| `paths.signals` | — (required) | `ASSETS_SIGNALS_DIR` |
| `paths.launcher` | (bundled script) | — |
| `features.rtk_aliases` | `false` | — |
| `approval.style` | `ui` | — |
| `approval.new_dispatch` | `required` | — |
| `approval.continue` | `optional` | — |
| `approval.recall` | `optional` | — |
| `monitoring.default_strategy` | `signal` | — |
| `monitoring.signal_poll_interval_sec` | `5` | — |
| `monitoring.signal_timeout_min` | `30` | — |
| `monitoring.health_check_at_min` | `10` | — |

## Changelog & versioning

Every version bump requires a `CHANGELOG.md` entry. A breaking change additionally requires
an `UPGRADING.md` section (plus a `schema_version` bump for schema-keyed plugins).
Enforced by `tests/test_structure.sh`.
