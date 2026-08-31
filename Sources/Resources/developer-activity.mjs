import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { findOpenClawDist } from "./goal-controller.mjs";

const [agentId, sessionId, sinceRaw] = process.argv.slice(2);
const since = Number(sinceRaw ?? 0);
if (!/^[a-z0-9][a-z0-9_-]*$/.test(agentId ?? "") || !/^[\w-]+$/.test(sessionId ?? "")) {
  throw new Error("Invalid activity session identity");
}
const dist = findOpenClawDist();
if (!dist) throw new Error("OpenClaw runtime not found");
const store = await import(pathToFileURL(join(dist, "plugin-sdk/session-store-runtime.js")).href);
const transcript = await import(pathToFileURL(join(dist, "plugin-sdk/session-transcript-runtime.js")).href);
const storePath = store.resolveStorePath(undefined, { agentId });
const scope = { agentId, sessionId, storePath };
let cursor;
let maxBytes = 256 * 1024;
const seen = new Set();

function emitEvent(event) {
  const message = event?.message;
  if (event?.type !== "message" || !["assistant", "toolResult"].includes(message?.role)) return;
  const timestamp = typeof message.timestamp === "number" ? message.timestamp : Date.parse(event.timestamp ?? "");
  if (timestamp < since) return;
  const key = event.id ?? JSON.stringify(event);
  if (seen.has(key)) return;
  seen.add(key);
  if (seen.size > 4096) seen.delete(seen.values().next().value);
  // Send only tool metadata to the UI, never complete prompts or tool output bodies.
  const content = Array.isArray(message.content) ? message.content.filter((part) => part.type === "toolCall").map((part) => ({
    type: "toolCall", id: part.id, name: part.name,
    arguments: { path: part.arguments?.path ?? part.arguments?.file_path ?? part.arguments?.filePath },
  })) : [];
  if (message.role === "assistant" && content.length === 0) return;
  process.stdout.write(JSON.stringify({ type: "message", message: {
    role: message.role, timestamp: message.timestamp, content,
    toolCallId: message.toolCallId, isError: message.isError,
  } }) + "\n");
}

async function poll() {
  try {
    for (let pageIndex = 0; pageIndex < 4; pageIndex++) {
      const page = await transcript.readSessionTranscriptRawDelta({ ...scope, cursor, maxBytes, maxEvents: 64 });
      if (page.kind === "missing") break;
      cursor = page.cursor;
      if (page.kind === "reset") continue;
      if (page.requiredBytes) {
        if (page.requiredBytes > 64 * 1024 * 1024) throw new Error("Transcript event exceeds the runtime read limit");
        maxBytes = page.requiredBytes;
        continue;
      }
      for (const { event } of page.events) emitEvent(event);
      maxBytes = 256 * 1024;
      if (!page.hasMore) break;
    }
  } catch (error) {
    process.stderr.write(`Activity read: ${error.message}\n`);
  } finally {
    setTimeout(poll, 1000);
  }
}
await poll();
