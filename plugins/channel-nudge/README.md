# channel-nudge

A single hooks-only plugin that watches for **console-drift** across every
channel plugin in this marketplace: when an instance answers a real channel
inbound as plain text in its transcript instead of calling that channel's
outbound reply tool, the human reading the channel never sees the answer.

`channel-nudge` consolidates the per-channel Stop hooks shipped in
`discord@1.3.0`, `zulip@1.2.0`, and `wechat@0.2.0` (PR #158) into ONE process
per turn that parses the transcript ONCE and checks every channel against a
single registry.

## Install

```
/plugin install channel-nudge@machine
```

No configuration — install it once per project and it covers discord, zulip,
and wechat. It does not depend on those channel plugins being installed: the
detector no-ops for any channel whose source token doesn't appear in the
transcript.

## How it works

On every `Stop`, the hook:

1. Reads the Stop-event JSON envelope from stdin (`transcript_path`).
2. Parses the transcript JSONL **once**.
3. For each channel in its registry — `discord` / `zulip` / `wechat` — looks
   for the most recent inbound (`<channel source="..."`) where
   `mentioned="false"` is **not** set.
4. If that inbound exists and the assistant did NOT call any of that channel's
   reply tools after it, AND the post-inbound assistant prose sums to ≥80
   weighted non-whitespace chars (see CJK weighting below), the hook flags
   that channel.
5. Every channel that drifted is concatenated into one merged warning and
   emitted on stdout as a single JSON object carrying ONLY
   `hookSpecificOutput.additionalContext` with `hookEventName: "Stop"`. The
   drifting **instance** receives an advisory, verify-before-resend nudge in
   its next-turn context. There is no console banner — `systemMessage` is
   NOT emitted; the nudge is for the instance, not the user.

## Properties

- **Soft / non-blocking.** The hook never sets `decision: "block"` and always
  exits `0`. A detector failure or parse error exits silently — the Stop
  never breaks because of this hook. On no drift, output is empty.
- **Self-heal with judgment (v0.2.0).** On drift the merged warning is
  surfaced ONLY into the drifting instance's next-turn context, via
  `hookSpecificOutput.additionalContext`. The injected body is prefixed with
  an explicit verify-before-resend preamble — the instance is asked to CHECK
  whether it actually dropped a real answer, resend only if it did, and
  ignore on deliberate silence or a closed thread (e.g. `不用了`). The nudge
  reaches the instance, not the user; v0.1.0's console-only `systemMessage`
  is dropped (Kai's explicit decision: drift is chronic and dominant,
  judgment-applied verification is the FP mitigation).
- **80-char threshold (English) / ~40-hanzi equivalent (CJK).** CJK Unified
  Ideographs + Ext-A, CJK Symbols & Punctuation, Hiragana/Katakana, and
  Halfwidth/Fullwidth Forms are weighted **2** toward the threshold;
  everything else non-whitespace counts **1**. Short status text ("On it —",
  "Resending:", "ok", 好的, 收到) falls under the threshold and is treated as
  deliberate silence. Substantive prose past the threshold with no reply
  tool call after the inbound is the fire signal. Mixed zh/en answers sum
  naturally.
- **Channel-agnostic at deploy time.** This is a hooks-only plugin — no MCP
  server, no env vars, no access control. The standalone-SSE deployments that
  can't pull in the channel plugins' own hooks install `channel-nudge`
  instead.

## Channels covered

| Channel | source tokens | reply tool suffixes |
| --- | --- | --- |
| discord | `discord`, `discord-sse` | `reply`, `react`, `edit_message` |
| zulip | `zulip`, `zulip-sse` | `zulip_reply`, `zulip_react` |
| wechat | `wechat`, `wechat-sse` | `wechat_reply` |

The middle MCP-server-name segment of a tool name
(`mcp__<server>__<suffix>`) is instance-configurable, so the matcher gates on
the suffix and tolerates either source-token form (the live
`-sse`-suffixed form leaked into some delivered transcripts).

## License

Apache-2.0.
