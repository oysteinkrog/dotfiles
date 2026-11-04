// Runs on Teams in Chrome (teams.microsoft.com, teams.live.com, teams.cloud.microsoft).
// Every second while a call is live, send a heartbeat with the tab title.
//
// "Live" means the call bar's hang-up button is on the page. The join screen, chat and
// calendar have no hang-up button, so an open Teams tab alone does not count. The URL
// cannot tell: a guest join stays on /light-meetings/launch from the join screen
// through the whole call. The button has id="hangup-button" in the Teams web bundle
// (checked 2026-11-04); the data-tid forms are fallbacks for other Teams builds.

const HANGUP = [
  "#hangup-button",
  '[data-tid="hangup-main-btn"]',
  '[data-tid="calling-hangup-main-button"]',
  '[data-tid="call-hangup"]',
].join(",");

function inCall() {
  return document.querySelector(HANGUP) !== null;
}

function meetingId() {
  // /meet/3634607810271244 or #/meet/3634607810271244; else empty.
  const m = (location.pathname + location.hash).match(/\/meet\/(\d+)/);
  return m ? m[1] : "";
}

function snapshot() {
  return {
    t: Date.now(),
    source: "teams",
    code: meetingId(),
    title: document.title,
    self: null,
    participants: [],
    speaking: [],
  };
}

setInterval(() => {
  if (!inCall()) return;
  try {
    chrome.runtime.sendMessage(snapshot());
  } catch (e) {
    // extension reloaded: this page's script is orphaned until the tab reloads
  }
}, 1000);
