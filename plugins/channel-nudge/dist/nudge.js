#!/usr/bin/env node
import { createRequire as __cr } from 'node:module';
import { fileURLToPath as __furl } from 'node:url';
import { dirname as __dn } from 'node:path';
const require = __cr(import.meta.url);
const __filename = __furl(import.meta.url);
const __dirname = __dn(__filename);

// ../shared/console-drift.ts
import { readFileSync } from "fs";
var DEFAULT_SUBSTANTIVE_CHARS = 80;
var MAX_ASSISTANT_TURNS_SINCE_INBOUND = 6;
function isContentList(c) {
  return Array.isArray(c);
}
function extractUserText(rec) {
  const c = rec.message?.content;
  if (typeof c === "string") return c;
  if (isContentList(c)) {
    return c.map((b) => b.type === "text" ? b.text ?? "" : "").join("\n");
  }
  return "";
}
function getAssistantBlocks(rec) {
  const c = rec.message?.content;
  if (isContentList(c)) return c;
  if (typeof c === "string") return [{ type: "text", text: c }];
  return [];
}
function isChannelInboundForUs(rec, sourceTokens) {
  if (rec.type !== "user") return false;
  if (rec.message?.role !== "user") return false;
  const text = extractUserText(rec);
  if (!text.includes("<channel ")) return false;
  const m = /<channel\s+([^>]*)>/.exec(text);
  if (!m) return false;
  const attrs = m[1];
  const sourceMatch = /source\s*=\s*"([^"]+)"/.exec(attrs);
  if (!sourceMatch) return false;
  const source = sourceMatch[1];
  if (!sourceTokens.includes(source)) return false;
  if (/\bmentioned\s*=\s*"false"/.test(attrs)) return false;
  if (/\bsummary\s*=\s*"true"/.test(attrs)) return false;
  return true;
}
function isOurOutboundToolUse(block, outboundToolSuffixes) {
  if (block.type !== "tool_use") return false;
  const name = block.name;
  if (!name) return false;
  const lastSep = name.lastIndexOf("__");
  const suffix = lastSep >= 0 ? name.slice(lastSep + 2) : name;
  return outboundToolSuffixes.includes(suffix);
}
function codepointWeight(cp) {
  if (cp >= 19968 && cp <= 40959 || // CJK Unified Ideographs
  cp >= 13312 && cp <= 19903 || // CJK Ext-A
  cp >= 12352 && cp <= 12447 || // Hiragana
  cp >= 12448 && cp <= 12543 || // Katakana
  cp >= 12289 && cp <= 12351 || // CJK Symbols & Punctuation (U+3000 ideographic space is whitespace and was stripped)
  cp >= 65280 && cp <= 65519) return 2;
  return 1;
}
function weightedLength(text) {
  const stripped = text.replace(/\s+/gu, "");
  let total = 0;
  for (const ch of stripped) {
    total += codepointWeight(ch.codePointAt(0));
  }
  return total;
}
function postInboundAssistantTextLength(records) {
  let total = 0;
  for (const r of records) {
    if (r.type !== "assistant") continue;
    const blocks = getAssistantBlocks(r);
    for (const b of blocks) {
      if (b.type !== "text") continue;
      const t = b.text ?? "";
      total += weightedLength(t);
    }
  }
  return total;
}
function readTranscript(path) {
  const raw = readFileSync(path, "utf8");
  const out = [];
  for (const line of raw.split("\n")) {
    if (!line.trim()) continue;
    try {
      out.push(JSON.parse(line));
    } catch {
    }
  }
  return out;
}
function detectDriftFromRecords(records, opts) {
  const threshold = opts.substantiveChars ?? DEFAULT_SUBSTANTIVE_CHARS;
  let inboundIdx = -1;
  for (let i = records.length - 1; i >= 0; i--) {
    if (isChannelInboundForUs(records[i], opts.sourceTokens)) {
      inboundIdx = i;
      break;
    }
  }
  if (inboundIdx === -1) return { drift: false };
  for (let i = inboundIdx + 1; i < records.length; i++) {
    const r = records[i];
    if (r.type !== "assistant") continue;
    const blocks = getAssistantBlocks(r);
    for (const b of blocks) {
      if (isOurOutboundToolUse(b, opts.outboundToolSuffixes)) {
        return { drift: false };
      }
    }
  }
  const maxTurns = opts.recencyTurns ?? MAX_ASSISTANT_TURNS_SINCE_INBOUND;
  let assistantTurnsSince = 0;
  for (let i = inboundIdx + 1; i < records.length; i++) {
    if (records[i].type === "assistant") assistantTurnsSince++;
  }
  if (assistantTurnsSince > maxTurns) return { drift: false };
  const tailing = records.slice(inboundIdx + 1);
  const chars = postInboundAssistantTextLength(tailing);
  if (chars < threshold) return { drift: false };
  return {
    drift: true,
    reason: `Your last reply to a channel message (source matched ${opts.sourceTokens.join("/")}) appears to have gone to console \u2014 the post-inbound transcript carries ~${chars} weighted chars of prose but no ${opts.outboundToolSuffixes.join("/")} tool call was made after the inbound. If you meant to reply, re-send via the outbound reply tool. (Soft warning \u2014 ignore if you deliberately stayed silent or the user closed the thread.)`
  };
}

// nudge.ts
var CHANNEL_REGISTRY = [
  {
    name: "discord",
    sourceTokens: ["discord", "discord-sse"],
    outboundToolSuffixes: ["reply", "react", "edit_message"]
  },
  {
    name: "zulip",
    sourceTokens: ["zulip", "zulip-sse"],
    outboundToolSuffixes: ["zulip_reply", "zulip_react"]
  },
  {
    name: "wechat",
    sourceTokens: ["wechat", "wechat-sse"],
    outboundToolSuffixes: ["wechat_reply"]
  }
];
async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return Buffer.concat(chunks).toString("utf8").trim();
}
async function main() {
  const stdin = await readStdin();
  if (!stdin) return;
  let payload;
  try {
    payload = JSON.parse(stdin);
  } catch {
    return;
  }
  if (payload.stop_hook_active) return;
  if (!payload.transcript_path) return;
  let records;
  try {
    records = readTranscript(payload.transcript_path);
  } catch {
    return;
  }
  const reasons = [];
  for (const channel of CHANNEL_REGISTRY) {
    try {
      const r = detectDriftFromRecords(records, {
        sourceTokens: channel.sourceTokens,
        outboundToolSuffixes: channel.outboundToolSuffixes
      });
      if (r.drift) reasons.push(`[${channel.name}] ${r.reason}`);
    } catch {
    }
  }
  if (reasons.length === 0) return;
  const merged = reasons.join("\n\n");
  const preamble = "Possible dropped channel reply detected. Before doing anything, verify against the transcript whether you actually left a substantive answer that did NOT go out via the channel reply tool. Resend via that tool ONLY if you confirm it did not. If you deliberately stayed silent, or the user closed the thread (e.g. \u4E0D\u7528\u4E86), ignore this.";
  const additionalContext = `${preamble}

${merged}`;
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "Stop",
        additionalContext
      }
    }) + "\n"
  );
}
main().catch(() => {
}).finally(() => process.exit(0));
