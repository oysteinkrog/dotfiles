// Put chosen apps on named monitors, but only while every monitor in the layout is on.
//
// After a reboot, apps that restore themselves (Chrome, Slack, terminals) open on
// whatever monitor KWin picks. This moves each one to its place when its window opens,
// and moves all of them back when the full set of monitors comes back on (remote mode
// turns the side monitors off). With any layout monitor off, windows are left alone, so
// a single-monitor RDP session gets KWin's normal placement.
//
// The layout is per machine, in kwinrc:
//   [Script-pin-to-monitor]
//   Layout=[{"class":"slack","output":"DP-2","mode":"max"}, ...]
// class:   the window's resourceClass (see the KWin debug console)
// caption: optional regex the window title must match
// output:  connector name (see `kscreen-doctor -o`)
// mode:    "max" maximizes, "left" or "right" fills that half, "move" only moves it

// Outputs need a moment to settle after a monitor turns on.
const SETTLE_MS = 2000;
// Apps that restore their own window size do so just after the window opens.
const REPLACE_MS = 1500;

function loadLayout() {
    try {
        const rules = JSON.parse(readConfig("Layout", "[]"));
        rules.forEach(r => { if (r.caption) r.captionRe = new RegExp(r.caption); });
        return rules;
    } catch (e) {
        print("pin-to-monitor: bad Layout: " + e);
        return [];
    }
}

const LAYOUT = loadLayout();
const NEEDED = [...new Set(LAYOUT.map(r => r.output))];

function outputNamed(name) {
    return workspace.screens.find(o => o.name === name) || null;
}

function allOn() {
    return NEEDED.length > 0 && NEEDED.every(outputNamed);
}

function ruleFor(w) {
    return LAYOUT.find(r => r.class === w.resourceClass &&
        (!r.captionRe || r.captionRe.test(w.caption))) || null;
}

function place(w) {
    if (!w || !w.normalWindow || w.fullScreen || !allOn()) return;
    const rule = ruleFor(w);
    if (!rule) return;
    const output = outputNamed(rule.output);
    if (w.output !== output) workspace.sendClientToScreen(w, output);
    if (rule.mode === "max") {
        w.setMaximize(true, true);
    } else if (rule.mode === "left" || rule.mode === "right") {
        w.setMaximize(false, false);
        const a = workspace.clientArea(KWin.MaximizeArea, output, workspace.currentDesktop);
        const half = Math.floor(a.width / 2);
        w.frameGeometry = {
            x: rule.mode === "left" ? a.x : a.x + half, y: a.y,
            width: half, height: a.height,
        };
    }
}

function placeAll() {
    workspace.windowList().forEach(place);
}

function placeNew(w) {
    // Some apps set their title after the window opens (plasmawindowed does), so a
    // rule that matches on caption is checked again on each title change until it
    // matches once.
    if (!ruleFor(w) && LAYOUT.some(r => r.captionRe && r.class === w.resourceClass)) {
        const onCaption = () => {
            if (!ruleFor(w)) return;
            w.captionChanged.disconnect(onCaption);
            placeNew(w);
        };
        w.captionChanged.connect(onCaption);
        return;
    }
    place(w);
    const again = new QTimer();
    again.singleShot = true;
    again.interval = REPLACE_MS;
    again.timeout.connect(() => place(w));
    again.start();
}

// Only a return to the full set of monitors re-places every window, so other monitor
// changes (a scale change, a mode switch) never undo a window you moved yourself.
let wasAllOn = allOn();
const settle = new QTimer();
settle.singleShot = true;
settle.interval = SETTLE_MS;
settle.timeout.connect(() => {
    const now = allOn();
    if (now && !wasAllOn) placeAll();
    wasAllOn = now;
});

workspace.windowAdded.connect(placeNew);
workspace.screensChanged.connect(() => settle.start());

registerShortcut("PinToMonitorReapply", "Pin to monitor: put windows back in the layout", "", placeAll);

placeAll();
