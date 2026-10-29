// Runs on meet.google.com. Every second while the URL is a meeting (abc-defg-hij),
// send a heartbeat with the title, the roster and a best-effort list of who is speaking.
//
// Meet's markup is obfuscated and changes, so this avoids class names:
// - tiles are elements with data-participant-id
// - a tile's name is its first short text that is not a Material icon ligature
// - "speaking" = the tile's subtree keeps changing (the audio indicator animates).
//   Unverified on live calls; the recorder ignores it unless trust_meet_speaking is on.

const CODE = /^\/[a-z]{3}-[a-z]{4}-[a-z]{3}(\/|$)/;
const ICON = /^[a-z_]+$/; // mic_off, more_vert, keep ...
const SELF = new Set(["You", "Du", "Deg", "(You)", "(Du)"]);

const activity = new WeakMap(); // tile -> recent mutation timestamps
const observed = new WeakSet();

function tileName(tile) {
  const walker = document.createTreeWalker(tile, NodeFilter.SHOW_TEXT);
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    const t = n.textContent.trim();
    if (t.length >= 2 && t.length <= 60 && !ICON.test(t) && !SELF.has(t)) return t;
  }
  return null;
}

function watch(tile) {
  if (observed.has(tile)) return;
  observed.add(tile);
  new MutationObserver((muts) => {
    const now = Date.now();
    const list = (activity.get(tile) || []).filter((t) => now - t < 1000);
    for (const m of muts) if (!(m.target instanceof HTMLVideoElement)) list.push(now);
    activity.set(tile, list);
  }).observe(tile, { attributes: true, subtree: true, attributeFilter: ["class", "style"] });
}

function snapshot() {
  const now = Date.now();
  const participants = [];
  const speaking = [];
  const seen = new Set();
  for (const tile of document.querySelectorAll("[data-participant-id]")) {
    const id = tile.getAttribute("data-participant-id");
    if (seen.has(id)) continue;
    seen.add(id);
    watch(tile);
    const name = tileName(tile);
    if (!name) continue;
    participants.push(name);
    const recent = (activity.get(tile) || []).filter((t) => now - t < 1000);
    if (recent.length >= 4) speaking.push(name);
  }
  const selfEl = document.querySelector("[data-self-name]");
  return {
    t: now,
    source: "meet",
    code: location.pathname.slice(1, 13),
    title: document.title,
    self: selfEl ? selfEl.getAttribute("data-self-name") : null,
    participants: [...new Set(participants)],
    speaking: [...new Set(speaking)],
  };
}

setInterval(() => {
  if (!CODE.test(location.pathname)) return;
  try {
    chrome.runtime.sendMessage(snapshot());
  } catch (e) {
    // extension reloaded: this page's script is orphaned until the tab reloads
  }
}, 1000);
