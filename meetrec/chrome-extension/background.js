// Forward Meet state from the content script to the local recorder.
// The page itself cannot reach 127.0.0.1 (CORS); the service worker can, via host_permissions.
chrome.runtime.onMessage.addListener((ev) => {
  fetch("http://127.0.0.1:47833/event", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Meetrec": "1" },
    body: JSON.stringify(ev),
  }).catch(() => {}); // recorder not running: nothing to do
});
