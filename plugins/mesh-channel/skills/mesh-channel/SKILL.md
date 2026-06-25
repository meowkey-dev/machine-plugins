---
description: Two-agent communication over a shared JSONL file. Controller-asymmetric — install on the controller side only; the peer uses the channel via shell commands in its prompt. Use Monitor to wake on new lines from the other agent.
---

# mesh-channel — Two-agent comms over a JSONL file

A minimal protocol so two long-running agents can exchange messages through a single file, without polling each other and without coordinating writes.

## Controller-asymmetric install model

**This plugin installs on the controller side only.** The peer agent is a generic Claude Code (or
similar) session that uses the channel via plain shell commands embedded in its instruction
prompt — it never installs `mesh-channel` itself.

- **Controller** (this session): install the plugin so you get this SKILL and the `Monitor` wake on inbound messages.
- **Peer** (the other session): no install. You hand it the absolute paths of `mesh-channel-send` and `mesh-channel-watch` (or pre-baked command lines) inside the prompt you spawn it with. The peer treats them as opaque shell commands.

This shape lets you set up a one-way controller→peer asymmetry quickly, while the channel itself is still bidirectional at the file level — the peer can write back, your `Monitor` task wakes you on its lines.

## When to use vs `assets-dispatch --continue`/`--btw`

Both mechanisms can carry "controller wants to tell a running asset something." The boundary:

| | tmux-pane (`--continue` / `--btw`) | file-channel (`mesh-channel`) |
|---|---|---|
| Direction | controller → asset, one-way | bidirectional |
| Sync | synchronous (send-keys, immediate) | async (file append + poll) |
| Persistence | pane scrollback only | durable JSONL log, inspectable with `cat`/`tail`/`jq` |
| Peers per channel | one asset | many (file is shared) |
| Cross-host | requires the controller to have the tmux socket | works wherever the file is reachable (shared FS, sync) |

Rule of thumb: **tmux-pane for one-shot directives to a single asset**, **mesh-channel for bidirectional / multi-peer / observable streams**.

## When to use

- You have two agents (this session + another) that need to send each other intermittent messages
- The other agent doesn't have a callable inbox (no MCP/HTTP/Discord)
- You want event-driven wake (`Monitor`), not loop-polling
- Messages are infrequent (sub-second-per-event is overkill; this is for human-scale chat between agents)

Examples: pairing this session with a long-running squad in tmux; cross-instance debug chat with another agent; agent ↔ external program that can append JSONL lines.

## Protocol

- **One file per channel.** Both agents share it. Path is your choice (default convention: `/tmp/<channel-name>.jsonl`).
- **Each line is a JSON object** with at least: `ts`, `from`, `body`. `body` is a string; markdown is fine (the JSON encoder handles newlines, quotes, backticks).
- **Append-only.** Writers use `O_APPEND` + single `write()`. On Linux and macOS the kernel atomically appends each write to regular files via the inode lock — concurrent writers won't interleave bytes within one call. We cap each line at 4096 bytes as a portability guard for exotic filesystems (e.g. NFS without locking).
- **Per-agent cursor.** Each agent's last-read byte offset lives in a sidecar file `<channel>.cursor.<my-name>`. A new watcher starts at EOF by default (no backlog replay); pass `--catch-up` to start at 0. `--catch-up` always wins — it overwrites an existing cursor.
- **Self-filter.** The watcher drops lines where `from == my-name` so you don't get your own writes back. Note this is honor-system: any writer can set `from` to your name and your watcher will silently drop those lines.

## Three verbs

### 1. Join (start watching)

Wrap the watcher in the `Monitor` tool. Each notification = one inbound message from the OTHER agent.

```
Monitor(
  command="/path/to/mesh-channel-watch /tmp/<channel>.jsonl <my-name>",
  description="mesh-channel <channel> as <my-name>",
  persistent=true
)
```

Add `--catch-up` to the command if you want to read the file from the beginning (replay backlog). Default starts at EOF.

The Monitor task ID is what you'll pass to `TaskStop` later. Save it.

### 2. Send

```
bash: /path/to/mesh-channel-send /tmp/<channel>.jsonl <my-name> "<body>"
```

Body is a single shell argument — quote it. Markdown inside is fine; the writer does `json.dumps` so any `"`, `\n`, or `\`` becomes a proper JSON-string escape.

For multi-line markdown body, pass the whole thing inside the quotes:

```
mesh-channel-send /tmp/demo.jsonl worker "Multi-line body:
- one
- two
Looks good?"
```

### 3. Leave

```
TaskStop(<monitor-task-id>)
```

Or just let the session end — Monitor is session-bound and dies with the REPL.

## Schema

Each line is:

```json
{"ts": "2026-05-15T02:38:00Z", "from": "worker", "body": "any string, markdown OK"}
```

Optional fields you can add downstream (the watcher passes them through):

- `to` — addressing hint when more than two agents share a channel
- `type` — message kind (`msg`, `ack`, `event`, etc.)
- Anything else — the protocol doesn't care, only `from` is enforced for self-filtering

## Behavior notes

- **The watcher polls.** 200ms by default (`--poll <seconds>` to tune). Pure-Python, no `inotify` / `watchdog` dependency.
- **Atomic-append + self-filter caveats.** See the bullets under "Protocol" above for the 4096-byte cap and the trust-based self-filter — both apply at runtime. Use a unique channel path (not `/tmp/test.jsonl`) for production traffic so a third writer can't impersonate you.
- **Truncation handling.** If the channel file shrinks (someone truncated it), the watcher resets its cursor to 0 and re-reads from the top. Don't rely on truncation as "mark as read" — post-truncation content is always re-emitted from offset 0.
- **One watcher per name per channel.** Two watchers running with the same `<my-name>` on the same channel will race on the cursor sidecar (atomic per write, but they'll leapfrog each other → both lose lines intermittently). Pick distinct names or stop the stale watcher.
- **Incomplete trailing line.** If a writer crashes mid-append, the watcher reads up to the last `\n` and waits for the next event before re-trying — no half-line emissions.
- **No history retention beyond the file itself.** No log rotation, no compaction; if you want to start fresh, delete the file (or `> file` truncate) — watchers will pick it up.

## Anti-patterns

- **Don't poll inside the agent loop.** The whole point of this skill is to delegate the watching to a background process; use `Monitor`, not a `while True: read()` in your reasoning.
- **Don't send instructions as `body`.** This is a comms protocol, not a remote-control protocol. Whatever the other agent does with the message is up to its own SKILL/logic.
- **Don't rely on order across writers.** Two writers can interleave at the line level; the file order is the OS's append order, which is monotonic per writer but not synchronized across writers.

## Pairs with

- `Monitor` — event-driven wake, replaces polling.
- `TaskStop` — to leave a channel cleanly.
