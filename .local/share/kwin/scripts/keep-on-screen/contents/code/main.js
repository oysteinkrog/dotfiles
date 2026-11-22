// Move notification popups, OSDs and stranded windows back inside a monitor.
//
// RDP clients change the desktop size (krdp resize hook). Plasma places notification
// popups from the screen size it had when the popup opened and does not move them when
// the size drops, so a critical notification (which never times out) can sit half off
// screen where its close button cannot be reached (2026-11-22, aiolos re-auth toast).
// KWin moves normal windows off a removed output, but not this case.
//
// Rules:
//   - notification, critical notification and OSD windows are kept fully inside the
//     output they are on (or the nearest output);
//   - any other movable window that shows less than MIN_VISIBLE px on every output is
//     moved inside the nearest output (top-left aligned if it is bigger than the output).
// Checks run after each output change (twice, as Plasma may re-place its popups late),
// when a popup opens, and when a popup moves.

const SETTLE_MS = 400;
const LATE_MS = 2000;
const MIN_VISIBLE = 48;
const LOG = readConfig("Debug", false);

function log(msg) { if (LOG) console.log("keep-on-screen: " + msg); }

function isPopup(w) {
    return w.notification || w.criticalNotification || w.onScreenDisplay;
}

function isStrandable(w) {
    return !isPopup(w) && w.moveable && !w.fullScreen && !w.specialWindow &&
        (w.normalWindow || w.dialog || w.utility);
}

function area(output) {
    return workspace.clientArea(KWin.FullScreenArea, output, workspace.currentDesktop);
}

function overlap(g, a) {
    const w = Math.min(g.x + g.width, a.x + a.width) - Math.max(g.x, a.x);
    const h = Math.min(g.y + g.height, a.y + a.height) - Math.max(g.y, a.y);
    return w > 0 && h > 0 ? { w: w, h: h } : null;
}

function nearestOutput(g) {
    const cx = g.x + g.width / 2, cy = g.y + g.height / 2;
    let best = null, bestD = Infinity;
    workspace.screens.forEach(o => {
        const a = area(o);
        const dx = Math.max(a.x - cx, 0, cx - (a.x + a.width));
        const dy = Math.max(a.y - cy, 0, cy - (a.y + a.height));
        const d = dx * dx + dy * dy;
        if (d < bestD) { bestD = d; best = o; }
    });
    return best;
}

function clampInto(g, a) {
    const x = Math.max(a.x, Math.min(g.x, a.x + a.width - g.width));
    const y = Math.max(a.y, Math.min(g.y, a.y + a.height - g.height));
    return { x: x, y: y };
}

function fix(w) {
    if (!w || w.deleted) return;
    const g = w.frameGeometry;
    if (g.width <= 0 || g.height <= 0 || workspace.screens.length === 0) return;
    let target = null;
    if (isPopup(w)) {
        // The output that holds the popup's centre, else the nearest one.
        const o = nearestOutput(g);
        target = clampInto(g, area(o));
    } else if (isStrandable(w)) {
        const seen = workspace.screens.some(o => {
            const v = overlap(g, area(o));
            return v && v.w >= Math.min(MIN_VISIBLE, g.width) && v.h >= Math.min(MIN_VISIBLE, g.height);
        });
        if (seen) return;
        target = clampInto(g, area(nearestOutput(g)));
    }
    if (!target || (Math.abs(target.x - g.x) < 0.5 && Math.abs(target.y - g.y) < 0.5)) return;
    log("move " + w.resourceClass + " " + w.internalId + " from " + g.x + "," + g.y +
        " to " + target.x + "," + target.y);
    w.frameGeometry = { x: target.x, y: target.y, width: g.width, height: g.height };
}

function fixAll() { workspace.stackingOrder.forEach(fix); }

function timer(ms) {
    const t = new QTimer();
    t.singleShot = true;
    t.interval = ms;
    t.timeout.connect(fixAll);
    return t;
}
const settle = timer(SETTLE_MS);
const late = timer(LATE_MS);
function outputsChanged() { log("outputs changed"); settle.start(); late.start(); }

let watched = [];
function watchOutputs() {
    watched.forEach(o => { try { o.geometryChanged.disconnect(outputsChanged); } catch (e) {} });
    watched = workspace.screens.slice();
    watched.forEach(o => o.geometryChanged.connect(outputsChanged));
}

function watchWindow(w) {
    // New normal windows are left to KWin's own placement.
    if (!isPopup(w)) return;
    // Plasma places the popup after it maps, and moves it when popups above it close.
    w.frameGeometryChanged.connect(() => fix(w));
    fix(w);
}

workspace.screensChanged.connect(() => { watchOutputs(); outputsChanged(); });
workspace.virtualScreenGeometryChanged.connect(outputsChanged);
workspace.windowAdded.connect(watchWindow);

registerShortcut("KeepOnScreenNow", "Keep on screen: move stray popups and windows back", "", fixAll);

watchOutputs();
workspace.stackingOrder.forEach(watchWindow);
fixAll();
