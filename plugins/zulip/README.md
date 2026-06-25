# zulip — Zulip channel for Claude Code

MCP server that bridges Zulip streams and DMs into a Claude Code session as a
first-class **channel**: incoming messages arrive as `<channel>` tags that
Claude can read mid-conversation, and tools let Claude reply, react, type, and
fetch history. Stream/DM access is governed by a local `access.json` file.

Built on the Anthropic channel protocol (`claude/channel` capability). Supports
two transports: stdio (plugin mode, single session) and SSE (standalone server,
multi-session).

## Install

```
/plugin marketplace add meowkey-dev/machine-plugins
/plugin install zulip@machine
```

## Configure

The server needs three environment variables and an access policy file.

### Environment variables

Copy `.env.example` to `.env` and fill in your bot credentials:

```
ZULIP_SITE=https://your-org.zulipchat.com
ZULIP_EMAIL=bot@your-org.zulipchat.com
ZULIP_API_KEY=your_api_key_here
PORT=3000               # only used in SSE mode
# ACCESS_FILE=./access.json   # optional, defaults to access.json in cwd
```

Create the bot at *Settings → Bots → Add a new bot*. Choose **Generic bot**
type. Note the bot's email and API key.

### Access policy (`access.json`)

Copy `access.json.example` to `access.json`. Schema:

```json
{
  "allowedStreams": ["general", "engineering"],
  "deniedStreams": [],
  "requireMention": true,
  "allowedUsers": [],
  "deniedUsers": []
}
```

- `allowedStreams` / `deniedStreams` — stream-name allowlist / denylist.
  Allowlist wins if both are set.
- `requireMention` (default `true`) — only deliver stream messages that
  `@`-mention the bot. Set `false` to deliver every message on allowed streams.
- `allowedUsers` / `deniedUsers` — Zulip user IDs. DMs from anyone in
  `allowedUsers` (or anyone, if empty) are delivered, except `deniedUsers`.

Messages that the policy filters out are still acknowledged to Zulip — they
just never reach Claude.

## Run modes

### stdio (plugin mode — default)

Claude Code's plugin loader runs `node dist/server.js` as a subprocess and
talks to it over stdin/stdout. No flags needed. This is what
`/plugin install` wires up.

### SSE (standalone server)

```
node dist/server.js --sse
```

Listens on `$PORT` (default 3000). Clients connect with:

```
GET /sse?streams=general,engineering
```

The `streams=` query filter narrows the session to a subset of allowed
streams; useful when one server backs several sessions (one per project).

### Inbound delivery to a tmux pane

```
node dist/server.js --inbound tmux --tmux-pane <session>:<win>.<pane> [--tmux-sock <path>]
```

Instead of delivering via the MCP channel protocol, paste incoming messages
into a specific tmux pane. Useful for piping a long-running shell agent.

## Tools exposed

The server registers these tools with the session:

- `zulip_reply` — send a message to a stream/topic or DM.
- `zulip_react` — add an emoji reaction to a message.
- `zulip_typing` — start/stop a typing indicator.
- `fetch_messages` — fetch recent messages from a stream/topic.
- `upload_file` — upload an attachment, returns a URL embeddable in a message.

## Console-drift Stop hook

The per-channel `Stop` hook this plugin shipped in `1.2.0` has been moved
into the dedicated [`channel-nudge`](../channel-nudge) plugin — one process
per turn covering every channel, not three. Install it alongside `zulip` to
keep the warning behavior:

```
/plugin install channel-nudge@machine
```

## License

Apache-2.0.
