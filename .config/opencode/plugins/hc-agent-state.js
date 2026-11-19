// hc-agent-state: tell herdr-core (hc) and the herdr app what opencode is doing.
//
// herdr-core shows an agent's status only when the program reports it with an
// OSC 7501 escape sequence on its terminal. opencode does not send one
// (herdr-app issue #489), and herdr's own opencode integration reports to the
// older herdr TUI socket instead, so in an hc terminal opencode had no status.
// This plugin writes `ESC ] 7501 ; state=<s>:app=opencode ESC \` to the
// controlling terminal. The sequence is invisible on screen.
//
// Active only inside an hc terminal (HC_TERMINAL_ID set). Event mapping follows
// herdr's integration (version 11); child sessions (subagents) only report
// blocked/working on behalf of their root session.

import fs from "node:fs";

const childSessions = new Map();
const CHILD_EVENT_STATES = new Map([
  ["permission.asked", "blocked"],
  ["question.asked", "blocked"],
  ["permission.replied", "working"],
  ["question.replied", "working"],
  ["question.rejected", "working"],
]);
const SESSION_STATE_BY_STATUS = new Map([
  ["idle", "idle"],
  ["active", "working"],
  ["busy", "working"],
  ["pending", "working"],
  ["retry", "working"],
  ["running", "working"],
  ["streaming", "working"],
  ["working", "working"],
]);

let tty;
let last;

function report(state) {
  if (!state || state === last) return;
  try {
    tty ??= fs.openSync("/dev/tty", "w");
    fs.writeSync(tty, `\x1b]7501;state=${state}:app=opencode\x1b\\`);
    last = state;
  } catch {
    // No terminal (for example `opencode run` in a pipe): nothing to report to.
  }
}

function stateFromStatus(status) {
  const kind = typeof status === "string" ? status : status?.type;
  return typeof kind === "string"
    ? SESSION_STATE_BY_STATUS.get(kind.toLowerCase())
    : undefined;
}

export const HcAgentStatePlugin = async () => {
  if (!process.env.HC_TERMINAL_ID) return {};
  report("idle");

  return {
    "chat.message": async ({ sessionID }) => {
      if (sessionID && childSessions.has(sessionID)) return;
      report("working");
    },
    event: async ({ event }) => {
      const type = event?.type;
      const properties = event?.properties ?? {};
      const sessionID =
        typeof properties.sessionID === "string" ? properties.sessionID : undefined;
      const info = properties.info;
      if (info?.id && info.parentID) childSessions.set(info.id, info.parentID);
      if (sessionID && childSessions.has(sessionID)) {
        report(CHILD_EVENT_STATES.get(type));
        return;
      }
      switch (type) {
        case "session.status":
          report(stateFromStatus(properties.status));
          break;
        case "tool.execute.before":
        case "tool.execute.after":
        case "permission.replied":
        case "question.replied":
        case "question.rejected":
        case "session.compacted":
          report("working");
          break;
        case "permission.asked":
        case "question.asked":
        case "session.error":
          report("blocked");
          break;
        case "session.idle":
          report("idle");
          break;
        default:
          break;
      }
    },
  };
};
