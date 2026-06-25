# mesh-channel

Minimal two-agent communication plugin. One shared JSONL file + a background watcher + Monitor-driven wake.

## Install

```
/plugin install mesh-channel@machine
```

## Use

See `skills/mesh-channel/SKILL.md` for the full protocol. Quick reference:

```
# Join (start watching) — typically wrapped in Monitor
mesh-channel-watch /tmp/demo.jsonl worker

# Send
mesh-channel-send /tmp/demo.jsonl worker "hello from worker"

# Leave — kill the watcher (TaskStop from CC, or just exit the session)
```

## What it does

- One JSONL file = one channel. Both agents read + write the same file.
- Watcher polls mtime + size (200ms default), reads new lines since a sidecar cursor (`<channel>.cursor.<my-name>`), filters out self-writes (`from == my-name`), prints surviving lines to stdout. Each printed line = one event for the wrapping `Monitor`.
- Writer uses `O_APPEND` + a single `write()` syscall — atomic on Linux/macOS for regular files (the inode lock serializes appends across writers). Each line is capped at 4096 bytes as a portability guard for exotic filesystems.
- Body is a JSON string, so markdown / newlines / quotes / backticks all survive intact.

## Why it exists

Long-running agents often need to exchange occasional messages — say, a coordinator session and a worker squad, or one agent instance and a separate Claude process. Building a per-pair protocol every time is annoying; building a heavyweight queue (Redis, NATS, MQ) is overkill. A shared file + cursor + self-filter is enough for most agent-to-agent use cases.

## Design choices

- **Plain JSONL.** Inspectable with `cat`, `tail -f`, `jq -c '.'`. No daemon, no broker, no schema registry.
- **Per-agent cursor.** Each side advances independently. Restart-safe; if a watcher dies and restarts, it picks up where it left off.
- **Default: start at EOF.** New watchers don't replay backlog. Pass `--catch-up` if you want them to.
- **No external dependencies.** Pure Python; no `inotify`, `watchdog`, or system packages.

## Limits

- Linux + macOS only (relies on the regular-file `O_APPEND` atomicity that the inode lock provides; Windows untested, NFS-without-locking unreliable).
- Each line capped at 4096 bytes as a conservative portability guard. For larger payloads, write a reference and store the payload elsewhere.
- Self-filter is honor-system (`from` is whatever the writer claims). Use unique channel paths for production; shared `/tmp` is fine for demos only.
- 200ms poll cadence. Tune via `--poll <seconds>` on the watcher.
- Not designed for high throughput. Sub-second-per-event is overkill territory for this; for that, use a real queue.

## Pairs with

- The `Monitor` tool (CC v2.1.98+) — wrap the watcher and each emitted line becomes a notification.
- `TaskStop` — leave a channel cleanly.

## Status

v0.1.1 — added CHANGELOG. No durability beyond the file itself; no log rotation; no message acks. Add later if needed.

## Changelog & versioning

Every version bump requires a `CHANGELOG.md` entry. A breaking change additionally requires
an `UPGRADING.md` section (plus a `schema_version` bump for schema-keyed plugins).
Enforced by `tests/test_structure.sh`.
