#!/usr/bin/env node
// Syncs the current Claude Code session to the running Paseo daemon.
// Called as a Claude Code hook on Stop/SessionStart events.
// Sends a resume_agent_request so Paseo picks up the session with full timeline.

import { randomUUID } from "node:crypto";

const DAEMON_URL = process.env.PASEO_DAEMON_URL || "ws://127.0.0.1:6767/ws";
const SESSION_ID = process.env.CLAUDE_SESSION_ID;
const CWD = process.env.CLAUDE_CWD || process.cwd();

if (!SESSION_ID) {
  // No session ID available — nothing to sync
  process.exit(0);
}

const TIMEOUT_MS = 10000;
let done = false;

function finish(code) {
  if (done) return;
  done = true;
  process.exit(code);
}

try {
  const ws = new WebSocket(DAEMON_URL);
  const clientId = randomUUID();
  const requestId = randomUUID();
  let resumeSent = false;

  ws.addEventListener("open", () => {
    ws.send(JSON.stringify({
      type: "hello",
      clientId,
      clientType: "cli",
      protocolVersion: 1,
      appVersion: "0.0.1",
    }));
  });

  ws.addEventListener("message", (event) => {
    const msg = JSON.parse(event.data);
    const inner = msg.type === "session" ? msg.message : msg;

    // After server_info, send resume request
    if (inner.type === "status" && inner.payload?.status === "server_info" && !resumeSent) {
      resumeSent = true;
      ws.send(JSON.stringify({
        type: "session",
        message: {
          type: "resume_agent_request",
          requestId,
          handle: {
            provider: "claude",
            sessionId: SESSION_ID,
            nativeHandle: SESSION_ID,
            metadata: { cwd: CWD },
          },
          overrides: { cwd: CWD },
        },
      }));
      return;
    }

    // Success — session is now in Paseo
    if (inner.type === "status" && inner.payload?.status === "agent_resumed") {
      ws.close();
      finish(0);
    }

    // Already exists or error — that's fine, session is known to Paseo
    if (inner.type === "status" && inner.payload?.error) {
      ws.close();
      finish(0); // Don't fail the hook on sync errors
    }
  });

  ws.addEventListener("error", () => {
    // Daemon not running — silently skip
    finish(0);
  });

  ws.addEventListener("close", () => {
    finish(0);
  });

  setTimeout(() => finish(0), TIMEOUT_MS);
} catch {
  // Any error — don't block Claude Code
  finish(0);
}
