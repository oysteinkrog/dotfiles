// Build Queue: the heavy-build queue at a glance. Whether the gate lets jobs start, what
// runs and what starts next, why jobs wait, how the queue grew over the last hour, and each
// Claude session with its worktrees, its jobs and its build priority. Machine resources are
// left out: Tasklens shows them beside this window.
// Data comes from $XDG_RUNTIME_DIR/buildqueue/queue.json, which ~/bin/buildqueue-fetch
// rewrites every five seconds. Colours and fonts come from the Plasma style, so the window
// matches the panels. The priority steppers run heavy-build-prio; nothing else writes.
// Run as a window with ~/bin/buildqueue-window, which starts the fetch and sets
// QML_XHR_ALLOW_FILE_READ=1 so the widget may read the file.

import QtCore
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property url dataFile: StandardPaths.writableLocation(StandardPaths.RuntimeLocation) + "/buildqueue/queue.json"
    property var q: ({
            updated: 0,
            error: ""
        })
    property string lastText: ""
    property double now: Date.now()
    // The fetch writes every 5 s, so 30 s without a new file means it has stopped.
    readonly property bool stale: q.updated > 0 && now - q.updated > 30000
    readonly property string problem: stale ? i18n("No new data for %1: is buildqueue-fetch running?", dur((now - q.updated) / 1000))
        : q.updated === 0 && now - startedAt > 15000 ? i18n("No data in %1. Start the window with buildqueue-window.", dataFile)
        : (q.error || "")
    readonly property double startedAt: Date.now()

    readonly property var running: q.running || []
    readonly property var waiting: q.waiting || ({
            count: 0,
            oldest: 0,
            causes: []
        })
    readonly property var velocity: q.velocity || ({
            finished: {}
        })
    readonly property var projects: q.projects || []
    readonly property var gate: q.gate || ({
            state: "unknown"
        })
    readonly property var slots: q.slots || ({})
    readonly property var nextJobs: (q.next || []).slice(0, 4)
    // Builds sent to other machines with the job system (`job run --on WORKER`).
    readonly property var remote: q.remote || ({})
    readonly property var remoteRunning: remote.running || []
    readonly property var remoteWorkers: remote.workers || []
    // The worker to suggest for a job that could run remotely: a Linux worker that is not frozen.
    readonly property string remoteTarget: remote.target || ""

    function remoteHint(job) {
        return remoteTarget !== "" && job.remoteOk === true;
    }

    function workerText(w) {
        const parts = [w.name, w.frozen ? i18n("frozen") : w.active ? i18n("owner at the machine") : i18n("owner away")];
        if (w.threads)
            parts.push(i18n("%1 threads, %2", w.threads, w.memHigh));
        if (w.memAvailGib !== undefined && w.memAvailGib !== null)
            parts.push(i18n("%1 GiB free", w.memAvailGib));
        return parts.join(" · ");
    }
    readonly property var history: q.history || []

    // Lane name -> true or false, for lanes the owner opened or closed. The top lane starts open.
    property var expanded: ({})
    // The Sessions list: "session" groups jobs by owning session, "queue" lists them in run order.
    property string listMode: "session"
    readonly property var queueRows: q.queue || []
    // A priority change in flight: the rule name, until the next fetch shows it.
    property string prioBusy: ""

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground

    function load() {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            root.now = Date.now();
            // An unchanged file means nothing new, so nothing is rebuilt.
            if (!xhr.responseText || xhr.responseText === root.lastText)
                return;
            root.lastText = xhr.responseText;
            try {
                const next = JSON.parse(xhr.responseText);
                // On an error the fetch writes only the error, so the last data stays.
                root.q = next.running ? next : Object.assign({}, root.q, {
                    updated: next.updated,
                    error: next.error
                });
            } catch (err) {
                root.q = Object.assign({}, root.q, {
                    error: String(err)
                });
            }
        };
        xhr.open("GET", dataFile);
        xhr.send();
    }

    // 45 s, 12 min, 3 h 5 min.
    function dur(s) {
        if (s === null || s === undefined)
            return "–";
        s = Math.round(s);
        if (s < 60)
            return i18n("%1 s", s);
        const m = Math.round(s / 60);
        if (m < 60)
            return i18n("%1 min", m);
        const h = Math.floor(m / 60), rest = m % 60;
        return rest ? i18n("%1 h %2 min", h, rest) : i18n("%1 h", h);
    }

    // The plain words for a wait cause, from the first word of heavy-build's reason.
    function causeLabel(kind) {
        const labels = {
            pressure: i18n("held by memory pressure"),
            memory: i18n("not enough memory for it"),
            starve: i18n("behind a job that waited too long"),
            behind: i18n("behind an older job"),
            interactive: i18n("keeping the desktop responsive"),
            hold: i18n("new jobs on hold"),
            critical: i18n("a critical job goes first"),
            key: i18n("same tree already building"),
            cores: i18n("not enough CPU cores"),
            "app-cap": i18n("all app-run slots in use")
        };
        return labels[kind] || kind;
    }

    function isAppRun(b) {
        return b.cls === "app-run";
    }

    function laneOpen(name, index) {
        return expanded[name] === undefined ? index === 0 : expanded[name];
    }

    function toggleLane(name, index) {
        const next = Object.assign({}, expanded);
        next[name] = !laneOpen(name, index);
        expanded = next;
    }

    // Runs heavy-build-prio. Each command runs once and its source is dropped when it ends.
    P5Support.DataSource {
        id: shell
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source);
            root.prioBusy = "";
            root.load();
        }
    }

    function quote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    // Moves a session's or worktree's rule one step: low, normal (no rule) or high.
    function setTheme(name) {
        shell.connectSource("os-theme " + quote(name));
    }

    function shiftPrio(match, current, delta) {
        const next = Math.max(-1, Math.min(1, prioStep(current) + delta));
        if (!match || next === prioStep(current))
            return;
        prioBusy = match;
        if (next === 0)
            shell.connectSource("heavy-build-prio clear --by oystein " + quote(match));
        else
            shell.connectSource("heavy-build-prio set --by oystein " + quote(match) + " " + (next > 0 ? "high" : "low") + " " + quote("Build Queue panel"));
    }

    function ownerName(o) {
        return o ? o : i18n("Unknown owner");
    }

    // How the owner of a worktree is known, for its tooltip.
    function ownerSource(lane) {
        switch (lane.ownerHow) {
        case "recorded":
            return i18n("heavy-build recorded the session on the job");
        case "folder":
            return i18n("the session works in this folder");
        case "mentions":
            return i18n("inferred: the session's transcripts name this worktree far more than any other session");
        case "siblings":
            return i18n("inferred from its sibling worktrees");
        case "guess":
            return i18n("a guess: several sessions name this worktree");
        }
        return i18n("no session found");
    }

    function inferred(lane) {
        return lane.ownerHow !== "recorded" && lane.ownerHow !== "folder";
    }

    // A lane's priority setting as a step: low -1, normal 0, high +1, critical +2.
    function prioStep(p) {
        if (!p)
            return 0;
        return {
            low: -1,
            normal: 0,
            high: 1,
            critical: 2
        }[p.prio] || 0;
    }

    // The rows of an open session: its worktrees, and under each open worktree its jobs,
    // grouped by subagent when heavy-build names one.
    function laneRows(lane, max) {
        const rows = [];
        if (lane.lanes) {
            for (const kid of lane.lanes) {
                const open = laneOpen(kid.name, 1);
                rows.push({
                    kind: "lane",
                    depth: 0,
                    lane: kid,
                    open: open
                });
                if (open)
                    jobRows(kid, 1, max, rows);
            }
            return rows;
        }
        jobRows(lane, 0, max, rows);
        return rows;
    }

    function jobRows(lane, base, max, rows) {
        const groups = {};
        const order = [];
        for (const j of lane.jobs || []) {
            const key = "\u0000" + (j.agent || "");
            if (!groups[key]) {
                groups[key] = [];
                order.push(key);
            }
            groups[key].push(j);
        }
        order.sort((a, b) => (a === "\u0000" ? -1 : b === "\u0000" ? 1 : a < b ? -1 : 1));
        let lastSession = null;
        let shown = 0;
        for (const key of order) {
            const [session, agent] = key.split("\u0000");
            let depth = base;
            if (session) {
                if (session !== lastSession)
                    rows.push({
                        kind: "group",
                        depth: base,
                        text: i18n("session %1", session)
                    });
                lastSession = session;
                depth += 1;
            }
            if (agent) {
                rows.push({
                    kind: "group",
                    depth: depth,
                    text: i18n("subagent %1", agent)
                });
                depth += 1;
            }
            for (const j of groups[key]) {
                if (shown >= max)
                    break;
                rows.push({
                    kind: "job",
                    depth: depth,
                    job: j
                });
                shown += 1;
            }
        }
        const total = lane.waiting + lane.running + lane.finished;
        if (total > shown)
            rows.push({
                kind: "more",
                depth: base,
                text: i18n("+ %1 more jobs", total - shown)
            });
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.load()
    }

    // Plasma style (panel) colours from buildqueue-fetch. Empty until the first fetch, and
    // then the app colour scheme is used.
    readonly property var style: q.theme || ({})
    readonly property bool styled: style.background !== undefined
    // The panel theme picked with panel-theme, shared with the Agenda widget. Its colours
    // replace the Plasma style ones; "plasma" (no colours) keeps the Plasma style.
    readonly property var pt: q.panelTheme || ({})
    readonly property bool themed: pt.window !== undefined
    readonly property color cardColor: themed ? pt.card : styled ? style.background : Kirigami.Theme.backgroundColor
    readonly property color inkColor: themed ? pt.text : styled ? style.text : Kirigami.Theme.textColor

    // Type scale, from the Plasma font so it follows the owner's font size. Shared with the
    // Agenda widget: docs/desktop-panels-style.md.
    readonly property real fs: Kirigami.Theme.defaultFont.pointSize * 1.08
    readonly property real fsRow: fs * 0.95
    readonly property real fsSmall: Kirigami.Theme.smallFont.pointSize

    // Data colours are the Plasma ones, a little less saturated so they sit calmly on the
    // dark cards. Text and chrome stay neutral: colour is for data only.
    function muted(c) {
        if (themed && !pt.mute)
            return c;
        return Qt.hsla(c.hslHue, c.hslSaturation * 0.78, Math.min(c.hslLightness, 0.6), 1);
    }

    function tint(amount) {
        return Kirigami.ColorUtils.tintWithAlpha(cardColor, inkColor, amount);
    }

    // A section title: body size, semi-bold, in the theme's title colour (a light tint of the
    // accent with the Plasma style).
    component Heading: PlasmaComponents.Label {
        font.pointSize: root.fs
        font.weight: Font.DemiBold
        color: root.themed ? root.pt.title : Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.highlightColor, "white", 0.35)
    }

    // Muted small text: labels, captions, axis text.
    component Small: PlasmaComponents.Label {
        font.pointSize: root.fsSmall
        opacity: 0.62
    }

    // Table text.
    component Cell: PlasmaComponents.Label {
        font.pointSize: root.fsRow
        elide: Text.ElideRight
    }

    // A column heading in a table.
    component Head: PlasmaComponents.Label {
        font.pointSize: root.fsSmall
        opacity: 0.5
        elide: Text.ElideRight
    }

    // A panel with a hairline border on the window background, with an optional title row.
    // Extra header items (a toggle, a legend, a note) go in `header`.
    component Card: Rectangle {
        id: card
        property string title: ""
        default property alias content: body.data
        property alias header: headerRow.data
        readonly property real pad: Kirigami.Units.smallSpacing * 2.5
        implicitHeight: col.implicitHeight + pad * 2
        implicitWidth: col.implicitWidth + pad * 2
        radius: 6
        color: root.themed ? root.pt.card : root.tint(0.045)
        border.width: 1
        border.color: root.themed ? root.pt.border : root.tint(0.11)
        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: card.pad
            spacing: Kirigami.Units.smallSpacing
            RowLayout {
                id: headerRow
                visible: card.title !== ""
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing * 1.5
                Heading {
                    text: card.title
                }
            }
            ColumnLayout {
                id: body
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 1
            }
        }
    }

    // A row that lights up under the mouse and shows `tip` as a tooltip. `clickable` rows
    // light up more and show a hand cursor.
    component HoverRow: Rectangle {
        id: hoverRow
        default property alias content: row.data
        property alias spacing: row.spacing
        property string tip: ""
        property bool clickable: false
        property real minHeight: 0
        readonly property bool hovered: hover.hovered
        implicitHeight: Math.max(minHeight, row.implicitHeight + 2)
        implicitWidth: row.implicitWidth + 4
        radius: 3
        color: hover.hovered ? root.tint(clickable ? 0.11 : 0.065) : "transparent"
        Behavior on color {
            ColorAnimation {
                duration: Kirigami.Units.shortDuration
            }
        }
        HoverHandler {
            id: hover
            cursorShape: hoverRow.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
        RowLayout {
            id: row
            anchors.fill: parent
            anchors.leftMargin: 3
            anchors.rightMargin: 3
            spacing: Kirigami.Units.smallSpacing * 1.5
        }
        PlasmaComponents.ToolTip.visible: hover.hovered && tip !== ""
        PlasmaComponents.ToolTip.text: tip
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
    }

    // A big number with a smaller suffix on the same baseline: "4" "of 9".
    component BigNumber: RowLayout {
        property string value: ""
        property real size: 1.7
        property string suffix: ""
        property color color: Kirigami.Theme.textColor
        spacing: Kirigami.Units.smallSpacing
        PlasmaComponents.Label {
            text: parent.value
            color: parent.color
            font.pointSize: root.fs * parent.size
            font.weight: Font.Bold
        }
        PlasmaComponents.Label {
            visible: text !== ""
            text: parent.suffix
            font.pointSize: root.fs * 1.1
            opacity: 0.6
            Layout.alignment: Qt.AlignBaseline
        }
    }

    // A row of cells across the given width, `used` of `total` filled.
    component CellMeter: Item {
        id: meter
        property int total: 0
        property int used: 0
        property color fill: Kirigami.Theme.positiveTextColor
        implicitHeight: Math.round(Kirigami.Units.gridUnit * 0.62)
        implicitWidth: Kirigami.Units.gridUnit * 3
        Row {
            anchors.fill: parent
            spacing: 3
            Repeater {
                model: Math.max(0, meter.total)
                delegate: Rectangle {
                    required property int index
                    width: Math.max(4, (meter.width - (meter.total - 1) * 3) / Math.max(1, meter.total))
                    height: meter.height
                    radius: 2
                    color: index < meter.used ? meter.fill : root.tint(0.1)
                }
            }
        }
    }

    // A thin bar `value` long on a scale of `max`, with a faint track behind it.
    component ValueBar: Rectangle {
        property real value: 0
        property real max: 1
        property color fill: Kirigami.Theme.textColor
        implicitHeight: 4
        radius: 2
        color: root.tint(0.08)
        Rectangle {
            height: parent.height
            radius: parent.radius
            width: parent.max > 0 ? Math.max(value > 0 ? 2 : 0, parent.width * Math.min(1, parent.value / parent.max)) : 0
            color: parent.fill
        }
    }

    // Segments side by side, each `[count, colour]`, scaled to `max` (default: their sum).
    component StackBar: Item {
        id: stack
        property var parts: []
        property real max: 0
        implicitHeight: 8
        readonly property real sum: parts.reduce((a, p) => a + p[0], 0)
        readonly property real scale: max > 0 ? max : sum
        Rectangle {
            anchors.fill: parent
            radius: 2
            color: root.tint(0.08)
        }
        Row {
            height: parent.height
            spacing: 1
            Repeater {
                model: stack.parts
                delegate: Rectangle {
                    required property var modelData
                    height: stack.height
                    visible: modelData[0] > 0
                    width: stack.scale > 0 ? Math.max(2, stack.width * modelData[0] / stack.scale - 1) : 0
                    radius: 1
                    color: modelData[1]
                }
            }
        }
    }

    // A legend dot.
    component Dot: Rectangle {
        property real size: Kirigami.Units.smallSpacing * 1.8
        implicitWidth: size
        implicitHeight: size
        radius: size / 2
    }

    // A sparkline of a lane's waiting count over the hour, one point a minute. The scale has a
    // floor of 4 jobs, so a lane that only ever has 1 waiting stays low and flat.
    component Spark: Canvas {
        property var values: []
        property color line: Kirigami.Theme.textColor
        implicitWidth: Kirigami.Units.gridUnit * 2.8
        implicitHeight: Kirigami.Units.gridUnit * 0.85
        readonly property string key: values.join(",")
        onKeyChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const s = values;
            if (s.length < 2)
                return;
            const top = Math.max(4, ...s);
            const X = i => 1 + (width - 3) * i / (s.length - 1), Y = v => height - 1 - (height - 3) * v / top;
            ctx.beginPath();
            ctx.moveTo(X(0), height);
            for (let i = 0; i < s.length; i++)
                ctx.lineTo(X(i), Y(s[i]));
            ctx.lineTo(X(s.length - 1), height);
            ctx.closePath();
            ctx.fillStyle = Qt.rgba(line.r, line.g, line.b, 0.14);
            ctx.fill();
            ctx.beginPath();
            for (let i = 0; i < s.length; i++)
                i === 0 ? ctx.moveTo(X(i), Y(s[i])) : ctx.lineTo(X(i), Y(s[i]));
            ctx.strokeStyle = Qt.rgba(line.r, line.g, line.b, 0.85);
            ctx.lineWidth = 1.2;
            ctx.stroke();
            ctx.fillStyle = line;
            ctx.beginPath();
            ctx.arc(X(s.length - 1), Y(s[s.length - 1]), 1.6, 0, 2 * Math.PI);
            ctx.fill();
        }
    }

    // One arrow of a priority stepper.
    component StepArrow: Rectangle {
        id: arrow
        property string glyph: ""
        property string tip: ""
        property bool active: false
        signal clicked
        implicitWidth: Kirigami.Units.gridUnit * 0.85
        implicitHeight: Kirigami.Units.gridUnit
        radius: 3
        color: hover.hovered && active ? root.tint(tap.pressed ? 0.22 : 0.14) : "transparent"
        PlasmaComponents.Label {
            anchors.centerIn: parent
            text: arrow.glyph
            font.pointSize: root.fs
            font.weight: Font.DemiBold
            opacity: arrow.active ? (hover.hovered ? 1 : 0.75) : 0.22
        }
        HoverHandler {
            id: hover
            cursorShape: arrow.active ? Qt.PointingHandCursor : Qt.ForbiddenCursor
        }
        TapHandler {
            id: tap
            onTapped: if (arrow.active) arrow.clicked()
        }
        PlasmaComponents.ToolTip.visible: hover.hovered && tip !== ""
        PlasmaComponents.ToolTip.text: tip
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
    }

    // A session's build priority as one control: ‹ low ›, ‹ high ›. The arrows run
    // heavy-build-prio. A session with a rule gets the accent fill, since the owner chose that
    // value. Without a rule, or without `match` (no known owner), it is flat and shows a dash.
    component Stepper: Rectangle {
        id: stepper
        property var prio: null
        property string match: ""
        property bool editable: true
        readonly property int step: root.prioStep(prio)
        readonly property bool busy: root.prioBusy !== "" && root.prioBusy === match
        readonly property bool ruled: prio !== null && prio !== undefined
        readonly property bool can: editable && match !== "" && root.q.prioTool && root.prioBusy === ""
        implicitWidth: Kirigami.Units.gridUnit * 4.6
        implicitHeight: Kirigami.Units.gridUnit * 1.05
        radius: 4
        color: ruled ? Kirigami.Theme.highlightColor : "transparent"
        RowLayout {
            anchors.fill: parent
            spacing: 0
            StepArrow {
                visible: stepper.editable && stepper.match !== ""
                glyph: "‹"
                active: stepper.can && stepper.step > -1 && stepper.step < 2
                tip: !root.q.prioTool ? i18n("heavy-build-prio is not installed") : stepper.step >= 2 ? i18n("Critical comes from the machine's session list, not from here") : stepper.step <= -1 ? i18n("%1 is at low priority already", stepper.match) : i18n("Lower %1 to %2", stepper.match, stepper.step > 0 ? i18n("normal") : i18n("low"))
                onClicked: root.shiftPrio(stepper.match, stepper.prio, -1)
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: stepper.busy ? "…" : stepper.ruled ? stepper.prio.prio : "–"
                font.pointSize: root.fsSmall
                font.weight: stepper.ruled ? Font.DemiBold : Font.Normal
                color: stepper.ruled ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                opacity: stepper.ruled ? 1 : 0.45
                HoverHandler {
                    id: valueHover
                }
                PlasmaComponents.ToolTip.visible: valueHover.hovered
                PlasmaComponents.ToolTip.text: stepper.match === "" ? i18n("Jobs with no known owner have no session rule") : stepper.prio ? i18n("Priority %1 from rule \"%2\", set by %3", stepper.prio.prio, stepper.prio.rule, stepper.prio.by || "?") : i18n("Normal priority: no rule matches")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            StepArrow {
                visible: stepper.editable && stepper.match !== ""
                glyph: "›"
                active: stepper.can && stepper.step < 1
                tip: !root.q.prioTool ? i18n("heavy-build-prio is not installed") : stepper.step >= 1 ? i18n("%1 is at high priority already", stepper.match) : i18n("Raise %1 to %2", stepper.match, stepper.step < 0 ? i18n("normal") : i18n("high"))
                onClicked: root.shiftPrio(stepper.match, stepper.prio, 1)
            }
        }
    }

    fullRepresentation: Rectangle {
        id: view

        // Colours are worked out here, not on root, so they come from the Plasma style.
        readonly property color gateColor: root.gate.state === "paused" ? Kirigami.Theme.negativeTextColor
            : root.gate.state === "slowed" ? Kirigami.Theme.neutralTextColor
            : root.gate.state === "open" ? Kirigami.Theme.positiveTextColor
            : Kirigami.Theme.disabledTextColor
        readonly property color runColor: root.muted(Kirigami.Theme.linkColor)
        readonly property color appColor: root.themed ? root.pt.extra : root.muted(Kirigami.Theme.highlightColor)
        readonly property color waitColor: root.muted(Kirigami.Theme.neutralTextColor)
        readonly property color okColor: root.muted(Kirigami.Theme.positiveTextColor)
        readonly property color failColor: root.muted(Kirigami.Theme.negativeTextColor)
        readonly property var causePalette: [waitColor, failColor, runColor, appColor, okColor, Kirigami.Theme.disabledTextColor]
        readonly property color faint: root.tint(0.08)
        readonly property color line: root.tint(0.11)

        // Table columns, shared by the header and the rows.
        readonly property real gu: Kirigami.Units.gridUnit
        readonly property real rowH: gu * 1.2

        function prioColor(p) {
            if (p === "critical")
                return Kirigami.Theme.negativeTextColor;
            if (p === "high")
                return Kirigami.Theme.neutralTextColor;
            if (p === "low")
                return Kirigami.Theme.disabledTextColor;
            return Kirigami.Theme.textColor;
        }

        function stateColor(s) {
            return s === "running" ? runColor : s === "waiting" ? waitColor : s === "ok" ? okColor : failColor;
        }

        // "20 · 2 · 1 · 3": waiting, running, ok and failed, each in its colour, zeros dim.
        function counts(r) {
            const part = (n, c) => n > 0 ? "<font color='" + c + "'>" + n + "</font>" : "<font color='" + Kirigami.Theme.disabledTextColor + "'>0</font>";
            return [part(r.waiting, waitColor), part(r.running, runColor), part(r.finished - r.failed, okColor), part(r.failed, failColor)].join(" · ");
        }

        // Where a wait of `s` seconds sits on the 1 min to 10 h log axis, from 0 to 1.
        function logPos(s) {
            const v = Math.log(Math.max(60, s) / 60) / Math.log(600);
            return Math.max(0, Math.min(1, v));
        }

        readonly property var causeList: (root.waiting.causes || []).slice(0, 3)
        readonly property var causeParts: (root.waiting.causes || []).map((c, i) => [c.count, causePalette[Math.min(i, causePalette.length - 1)]])
        readonly property real runMax: root.running.reduce((a, b) => Math.max(a, b.runtime), 60)
        readonly property real nextMax: root.nextJobs.reduce((a, j) => Math.max(a, j.waited), 60)
        readonly property real laneMax: root.projects.reduce((a, p) => Math.max(a, p.waiting + p.running + p.finished), 1)
        readonly property real queueMax: root.queueRows.reduce((a, j) => Math.max(a, j.age), 60)
        readonly property int finishedTotal: Object.values(root.velocity.finished || {}).reduce((a, n) => a + n, 0)
        readonly property real flowMax: Math.max(1, root.velocity.arrived || 0, root.velocity.started || 0, finishedTotal)

        Layout.minimumWidth: Kirigami.Units.gridUnit * 22
        Layout.minimumHeight: Kirigami.Units.gridUnit * 30
        Layout.preferredWidth: Kirigami.Units.gridUnit * 29
        Layout.preferredHeight: Kirigami.Units.gridUnit * 60

        Kirigami.Theme.inherit: !root.styled
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.backgroundColor: root.themed ? root.pt.card : root.styled ? root.style.background : undefined
        Kirigami.Theme.alternateBackgroundColor: root.themed ? root.pt.band : root.styled ? root.style.alternate : undefined
        Kirigami.Theme.textColor: root.themed ? root.pt.text : root.styled ? root.style.text : undefined
        Kirigami.Theme.disabledTextColor: root.themed ? root.pt.muted : root.styled ? root.style.inactive : undefined
        Kirigami.Theme.negativeTextColor: root.themed ? root.pt.negative : root.styled ? root.style.negative : undefined
        Kirigami.Theme.neutralTextColor: root.themed ? root.pt.warning : root.styled ? root.style.neutral : undefined
        Kirigami.Theme.positiveTextColor: root.themed ? root.pt.positive : root.styled ? root.style.positive : undefined
        Kirigami.Theme.highlightColor: root.themed ? root.pt.accent : root.styled ? root.style.accent : undefined
        Kirigami.Theme.linkColor: root.themed ? root.pt.info : undefined
        Kirigami.Theme.highlightedTextColor: root.themed ? root.pt.onAccent : root.styled ? root.style.accentText : undefined
        // The window sits a step darker than the cards, so the cards lift off it.
        color: root.themed ? root.pt.window : Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, "black", 0.18)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing * 1.25
            spacing: Kirigami.Units.largeSpacing

            // Header: title, how fresh the data is, and any problem.
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing * 1.5
                PlasmaComponents.Label {
                    text: i18n("Build Queue")
                    font.pointSize: root.fs * 1.4
                    font.weight: Font.Bold
                }
                Item {
                    Layout.fillWidth: true
                }
                Small {
                    visible: root.q.updated > 0
                    text: root.stale ? i18n("No update for %1", root.dur((root.now - root.q.updated) / 1000)) : i18n("Updated %1 ago", root.dur(Math.max(0, root.now - root.q.updated) / 1000))
                }
                Dot {
                    visible: root.q.updated > 0
                    color: root.stale || root.problem !== "" ? Kirigami.Theme.neutralTextColor : view.okColor
                }
                PlasmaComponents.ToolButton {
                    id: themeButton
                    visible: (root.pt.names || []).length > 0
                    icon.name: "color-management"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    text: i18n("Theme")
                    implicitWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                    implicitHeight: implicitWidth
                    onClicked: themeMenu.open()
                    PlasmaComponents.ToolTip.visible: hovered && !themeMenu.visible
                    PlasmaComponents.ToolTip.text: i18n("Panel theme: %1", root.pt.label || root.pt.name || "")
                    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                    PlasmaComponents.Menu {
                        id: themeMenu
                        y: themeButton.height
                        Repeater {
                            model: root.pt.names || []
                            PlasmaComponents.MenuItem {
                                required property var modelData
                                text: modelData[1]
                                checkable: true
                                checked: modelData[0] === root.pt.name
                                onTriggered: root.setTheme(modelData[0])
                            }
                        }
                    }
                }
                Kirigami.Icon {
                    visible: root.problem !== ""
                    source: "data-warning"
                    implicitWidth: Kirigami.Units.iconSizes.small
                    implicitHeight: implicitWidth
                    HoverHandler {
                        id: errHover
                    }
                    PlasmaComponents.ToolTip.visible: errHover.hovered
                    PlasmaComponents.ToolTip.text: root.problem
                }
            }

            // The gate: one banner with the state and why.
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: -Kirigami.Units.smallSpacing
                implicitHeight: banner.implicitHeight + Kirigami.Units.smallSpacing * 3
                radius: 6
                color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, view.gateColor, 0.08)
                clip: true
                // The state bar on the left edge.
                Rectangle {
                    width: 3
                    height: parent.height
                    color: view.gateColor
                }
                RowLayout {
                    id: banner
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.smallSpacing * 2 + 3
                    anchors.rightMargin: Kirigami.Units.smallSpacing * 2
                    spacing: Kirigami.Units.smallSpacing * 2.5
                    RowLayout {
                            id: gateRow
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon {
                                source: root.gate.state === "paused" ? "media-playback-pause-symbolic" : root.gate.state === "slowed" ? "media-seek-forward-symbolic" : "media-playback-start-symbolic"
                                isMask: true
                                color: view.gateColor
                                implicitWidth: Kirigami.Units.iconSizes.small
                                implicitHeight: implicitWidth
                            }
                            PlasmaComponents.Label {
                                text: root.gate.state === "paused" ? i18n("PAUSED") : root.gate.state === "slowed" ? i18n("SLOWED") : root.gate.state === "open" ? i18n("OPEN") : i18n("UNKNOWN")
                                color: view.gateColor
                                font.pointSize: root.fs
                                font.weight: Font.Bold
                            }
                    }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font.pointSize: root.fsRow
                        text: {
                            const since = root.gate.since ? Qt.formatTime(new Date(root.gate.since * 1000), "HH:mm") : "";
                            const what = root.gate.state === "paused" ? i18n("Only high and critical jobs start.")
                                : root.gate.state === "slowed" ? i18n("One new job at a time.")
                                : root.gate.state === "open" ? i18n("Jobs start when they fit.") : "";
                            return since && root.gate.state !== "open" ? i18n("Since %1: %2. %3", since, root.gate.reason || "", what) : what;
                        }
                    }
                }
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: root.problem !== ""
                text: root.problem
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.Wrap
            }

            // The key numbers, each on its visual, in one card split by hairlines.
            Card {
                Layout.fillWidth: true
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: view.gu * 4.6
                        Layout.alignment: Qt.AlignTop
                        spacing: 3
                        Small {
                            text: i18n("Running")
                        }
                        BigNumber {
                            value: root.running.length
                            suffix: i18n("of %1", root.slots.jobs || "?")
                        }
                        CellMeter {
                            Layout.fillWidth: true
                            total: root.slots.jobs || 0
                            used: root.running.length
                            fill: view.runColor
                        }
                        Small {
                            text: i18n("job slots in use")
                        }
                    }
                    Rectangle {
                        implicitWidth: 1
                        Layout.fillHeight: true
                        color: view.line
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: view.gu * 3.6
                        Layout.alignment: Qt.AlignTop
                        spacing: 3
                        Small {
                            text: i18n("App runs")
                        }
                        BigNumber {
                            value: root.slots.appRunsUsed || 0
                            suffix: i18n("of %1", root.slots.appRuns || "?")
                        }
                        CellMeter {
                            Layout.fillWidth: true
                            total: root.slots.appRuns || 0
                            used: root.slots.appRunsUsed || 0
                            fill: view.appColor
                        }
                        Small {
                            text: i18n("in use")
                        }
                    }
                    Rectangle {
                        implicitWidth: 1
                        Layout.fillHeight: true
                        color: view.line
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: view.gu * 8
                        Layout.alignment: Qt.AlignTop
                        spacing: 3
                        Small {
                            text: i18n("Waiting")
                        }
                        BigNumber {
                            value: root.waiting.count
                        }
                        StackBar {
                            Layout.fillWidth: true
                            parts: view.causeParts
                        }
                        Repeater {
                            model: view.causeList.length
                            delegate: HoverRow {
                                required property int index
                                readonly property var modelData: view.causeList[index] || ({})
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                tip: modelData.example || ""
                                Dot {
                                    color: view.causePalette[Math.min(index, view.causePalette.length - 1)]
                                }
                                PlasmaComponents.Label {
                                    text: modelData.count
                                    font.pointSize: root.fsSmall
                                    font.weight: Font.DemiBold
                                }
                                Small {
                                    Layout.fillWidth: true
                                    text: root.causeLabel(modelData.kind)
                                    elide: Text.ElideRight
                                    opacity: 0.75
                                }
                            }
                        }
                    }
                    Rectangle {
                        implicitWidth: 1
                        Layout.fillHeight: true
                        color: view.line
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: view.gu * 6.4
                        Layout.alignment: Qt.AlignTop
                        spacing: 3
                        Small {
                            text: i18n("Oldest wait")
                        }
                        BigNumber {
                            value: root.waiting.count > 0 ? root.dur(root.waiting.oldest) : "–"
                            // Durations are long, so this one is a step smaller.
                            size: 1.45
                        }
                        // A log axis from 1 min to 10 h: median and slowest 10% of the jobs that
                        // started in the last hour, and the oldest job still waiting.
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: view.gu * 1.5
                            Rectangle {
                                y: 4
                                width: parent.width
                                height: 4
                                radius: 2
                                color: view.faint
                            }
                            Repeater {
                                model: [60, 3600, 36000]
                                delegate: Rectangle {
                                    required property var modelData
                                    x: Math.round(parent.width * view.logPos(modelData))
                                    y: 9
                                    width: 1
                                    height: 3
                                    color: view.line
                                }
                            }
                            Repeater {
                                model: [[root.velocity.waitMedian, view.okColor, 4], [root.velocity.waitP90, view.waitColor, 4], [root.waiting.count > 0 ? root.waiting.oldest : null, view.failColor, 9]]
                                delegate: Rectangle {
                                    required property var modelData
                                    visible: modelData[0] !== null && modelData[0] !== undefined
                                    x: Math.max(0, Math.min(parent.width - width, parent.width * view.logPos(modelData[0] || 0) - width / 2))
                                    y: 6 - height / 2
                                    width: modelData[2]
                                    height: modelData[2] === 9 ? 9 : 12
                                    radius: width / 2
                                    color: modelData[1]
                                }
                            }
                            Repeater {
                                model: [[60, i18n("1 min")], [3600, i18n("1 h")], [36000, i18n("10 h")]]
                                delegate: Small {
                                    required property var modelData
                                    y: 12
                                    x: Math.max(0, Math.min(parent.width - width, parent.width * view.logPos(modelData[0]) - width / 2))
                                    text: modelData[1]
                                }
                            }
                        }
                        Repeater {
                            model: [[view.okColor, i18n("median %1", root.dur(root.velocity.waitMedian))], [view.waitColor, i18n("slowest 10% %1", root.dur(root.velocity.waitP90))]]
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                Dot {
                                    color: modelData[0]
                                }
                                Small {
                                    Layout.fillWidth: true
                                    text: modelData[1]
                                    elide: Text.ElideRight
                                    opacity: 0.75
                                }
                            }
                        }
                    }
                }
            }

            // Queue length over the last hour, and the flow of jobs beside it. The row keeps
            // its natural height: the Sessions card takes the spare room.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Kirigami.Units.largeSpacing

                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    title: i18n("Queue, last hour")
                    header: [
                        Item {
                            Layout.fillWidth: true
                        },
                        Small {
                            readonly property int t: root.velocity.trend || 0
                            visible: root.velocity.trend !== null && root.velocity.trend !== undefined
                            text: t > 0 ? i18n("▲ %1 in %2 min", t, root.velocity.trendMinutes) : t < 0 ? i18n("▼ %1 in %2 min", -t, root.velocity.trendMinutes) : i18n("steady")
                            opacity: 0.8
                        }
                    ]
                    Canvas {
                        id: chart
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        implicitHeight: view.gu * 4.6
                        readonly property var points: root.history
                        readonly property color line: view.waitColor
                        readonly property color grid: root.tint(0.09)
                        readonly property color text: Kirigami.Theme.disabledTextColor
                        readonly property color slow: Kirigami.Theme.neutralTextColor
                        readonly property color pause: Kirigami.Theme.negativeTextColor
                        readonly property string key: points.length ? points.length + ":" + points[points.length - 1][0] : ""
                        onKeyChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            const pts = points;
                            if (pts.length < 2)
                                return;
                            const fontPx = 10;
                            ctx.font = fontPx + "px sans-serif";
                            const t1 = pts[pts.length - 1][0], t0 = t1 - 3600;
                            const raw = Math.max(10, ...pts.map(p => p[1]));
                            const stepN = raw > 100 ? 50 : raw > 40 ? 20 : 10;
                            const top = Math.ceil(raw / stepN) * stepN;
                            const L = ctx.measureText(String(top)).width + 6, T = 4, h = height - fontPx - 6, w = width;
                            const X = t => L + (w - L) * (t - t0) / 3600;
                            const Y = n => T + (h - T) * (1 - n / top);
                            // Gridlines and y labels.
                            ctx.textBaseline = "middle";
                            ctx.fillStyle = text;
                            for (let n = 0; n <= top; n += stepN) {
                                const y = Math.round(Y(n)) + 0.5;
                                ctx.strokeStyle = grid;
                                ctx.lineWidth = 1;
                                ctx.beginPath();
                                ctx.moveTo(L, y);
                                ctx.lineTo(w, y);
                                ctx.stroke();
                                const label = String(n);
                                ctx.fillText(label, L - 4 - ctx.measureText(label).width, y);
                            }
                            // Slowed and paused stretches: a ribbon along the bottom.
                            for (let i = 0; i < pts.length - 1; i++) {
                                const lvl = pts[i][2];
                                if (lvl === "slow" || lvl === "pause") {
                                    ctx.fillStyle = Qt.rgba((lvl === "pause" ? pause : slow).r, (lvl === "pause" ? pause : slow).g, (lvl === "pause" ? pause : slow).b, 0.75);
                                    ctx.fillRect(X(pts[i][0]), h - 3, X(pts[i + 1][0]) - X(pts[i][0]) + 0.5, 3);
                                }
                            }
                            // The queue: a faint area and a line.
                            ctx.beginPath();
                            ctx.moveTo(X(pts[0][0]), Y(0));
                            for (const p of pts)
                                ctx.lineTo(X(p[0]), Y(p[1]));
                            ctx.lineTo(X(t1), Y(0));
                            ctx.closePath();
                            ctx.fillStyle = Qt.rgba(line.r, line.g, line.b, 0.13);
                            ctx.fill();
                            ctx.beginPath();
                            for (let i = 0; i < pts.length; i++)
                                i === 0 ? ctx.moveTo(X(pts[i][0]), Y(pts[i][1])) : ctx.lineTo(X(pts[i][0]), Y(pts[i][1]));
                            ctx.strokeStyle = line;
                            ctx.lineWidth = 1.4;
                            ctx.stroke();
                            ctx.fillStyle = line;
                            ctx.beginPath();
                            ctx.arc(X(t1), Y(pts[pts.length - 1][1]), 2.2, 0, 2 * Math.PI);
                            ctx.fill();
                            // A dashed marker where the gate last changed, with its new state.
                            let at = -1;
                            for (let i = pts.length - 1; i > 0; i--)
                                if (pts[i][2] !== pts[i - 1][2]) {
                                    at = i;
                                    break;
                                }
                            if (at > 0 && (pts[at][2] === "slow" || pts[at][2] === "pause")) {
                                const c = pts[at][2] === "pause" ? pause : slow, x = Math.round(X(pts[at][0])) + 0.5;
                                ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.7);
                                ctx.lineWidth = 1;
                                for (let y = T; y < h - 3; y += 5) {
                                    ctx.beginPath();
                                    ctx.moveTo(x, y);
                                    ctx.lineTo(x, Math.min(y + 2.5, h - 3));
                                    ctx.stroke();
                                }
                                const tag = (pts[at][2] === "pause" ? i18n("paused") : i18n("slowed")) + " " + Qt.formatTime(new Date(pts[at][0] * 1000), "HH:mm");
                                const tw = ctx.measureText(tag).width;
                                ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.95);
                                ctx.textBaseline = "bottom";
                                ctx.fillText(tag, x + tw + 4 < w ? x + 4 : x - tw - 4, h - 5);
                            }
                            // Time labels.
                            ctx.fillStyle = text;
                            ctx.textBaseline = "bottom";
                            const fmt = t => Qt.formatTime(new Date(t * 1000), "HH:mm");
                            ctx.fillText(fmt(t0), L, height);
                            const mid = fmt(t0 + 1800);
                            ctx.fillText(mid, X(t0 + 1800) - ctx.measureText(mid).width / 2, height);
                            const nowText = i18n("now %1", pts[pts.length - 1][1]);
                            ctx.fillText(nowText, w - ctx.measureText(nowText).width, height);
                        }
                    }
                }

                Card {
                    Layout.preferredWidth: view.gu * 10.5
                    Layout.fillHeight: true
                    title: i18n("Jobs, last hour")
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.largeSpacing
                        Repeater {
                            model: [[i18n("arrived"), root.velocity.arrived || 0, view.waitColor], [i18n("started"), root.velocity.started || 0, view.runColor], [i18n("finished"), view.finishedTotal, view.okColor]]
                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                spacing: 2
                                Small {
                                    text: modelData[0]
                                }
                                PlasmaComponents.Label {
                                    text: modelData[1]
                                    font.pointSize: root.fs * 1.3
                                    font.weight: Font.DemiBold
                                }
                                ValueBar {
                                    Layout.fillWidth: true
                                    value: modelData[1]
                                    max: view.flowMax
                                    fill: modelData[2]
                                }
                            }
                        }
                    }
                    StackBar {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing * 1.5
                        readonly property var f: root.velocity.finished || {}
                        parts: [[f.ok || 0, view.okColor], [f.fail || 0, view.failColor], [view.finishedTotal - (f.ok || 0) - (f.fail || 0), view.waitColor]]
                    }
                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        readonly property var f: root.velocity.finished || {}
                        Dot {
                            color: view.okColor
                        }
                        Small {
                            text: i18n("%1 ok", parent.f.ok || 0)
                            opacity: 0.8
                        }
                        Dot {
                            Layout.leftMargin: Kirigami.Units.smallSpacing
                            color: view.failColor
                        }
                        Small {
                            text: i18n("%1 failed", parent.f.fail || 0)
                            opacity: 0.8
                        }
                    }
                    Item {
                        Layout.fillHeight: true
                    }
                }
            }

            // Running builds, longest first.
            Card {
                Layout.fillWidth: true
                title: i18n("Running now")
                header: Small {
                    text: i18n("%1 of %2 slots", root.running.length, root.slots.jobs || "?")
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing * 1.5
                    Item {
                        implicitWidth: Kirigami.Units.smallSpacing * 1.8
                    }
                    Head {
                        text: i18n("Class")
                        Layout.preferredWidth: view.gu * 5
                    }
                    Head {
                        text: i18n("Worktree")
                        Layout.fillWidth: true
                    }
                    Head {
                        text: i18n("Session")
                        Layout.preferredWidth: view.gu * 5
                    }
                    Head {
                        text: i18n("Priority")
                        Layout.preferredWidth: view.gu * 2.8
                    }
                    Head {
                        text: i18n("Running for")
                        Layout.preferredWidth: view.gu * 6.4
                        horizontalAlignment: Text.AlignRight
                    }
                }
                Repeater {
                    model: root.running.length
                    delegate: HoverRow {
                        id: runRow
                        required property int index
                        readonly property var job: root.running[index] || ({})
                        readonly property var own: root.queueRows[index] && root.queueRows[index].state === "running" ? root.queueRows[index] : ({})
                        Layout.fillWidth: true
                        minHeight: view.rowH
                        spacing: Kirigami.Units.smallSpacing * 1.5
                        tip: i18n("%1 in %2, %3 priority, running %4", job.cls, job.project, job.prio || "normal", root.dur(job.runtime)) + (own.owner !== undefined ? "\n" + i18n("Owner %1: %2", root.ownerName(own.owner), root.ownerSource(own)) : "") + (job.why ? "\n" + job.why : "")
                        Dot {
                            color: root.isAppRun(runRow.job) ? view.appColor : view.runColor
                        }
                        Cell {
                            text: runRow.job.cls || ""
                            Layout.preferredWidth: view.gu * 5
                        }
                        Cell {
                            text: runRow.job.project || ""
                            Layout.fillWidth: true
                            opacity: 0.85
                        }
                        Cell {
                            text: root.ownerName(runRow.own.owner) + (runRow.own.owner && root.inferred(runRow.own) ? " ≈" : "")
                            Layout.preferredWidth: view.gu * 5
                            opacity: runRow.own.owner ? 0.85 : 0.5
                            font.italic: !runRow.own.owner
                        }
                        Cell {
                            text: runRow.job.prio || i18n("normal")
                            Layout.preferredWidth: view.gu * 2.8
                            font.pointSize: root.fsSmall
                            color: view.prioColor(runRow.job.prio)
                            opacity: runRow.job.prio === "high" || runRow.job.prio === "critical" ? 1 : 0.55
                        }
                        ValueBar {
                            Layout.preferredWidth: view.gu * 2.6
                            value: runRow.job.runtime
                            max: view.runMax
                            fill: root.isAppRun(runRow.job) ? view.appColor : view.runColor
                        }
                        Cell {
                            text: root.dur(runRow.job.runtime)
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: view.gu * 3.5
                        }
                    }
                }
                Small {
                    visible: root.running.length === 0
                    text: i18n("Nothing running")
                }
            }

            // Builds on other machines, from the job system. heavy-build does not see them.
            Card {
                Layout.fillWidth: true
                visible: root.remoteWorkers.length > 0 || root.remoteRunning.length > 0
                title: i18n("Remote")
                header: Small {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.remoteWorkers.map(w => root.workerText(w)).join("   ")
                }
                Repeater {
                    model: root.remoteRunning.length
                    delegate: HoverRow {
                        id: remRow
                        required property int index
                        readonly property var job: root.remoteRunning[index] || ({})
                        Layout.fillWidth: true
                        minHeight: view.rowH
                        spacing: Kirigami.Units.smallSpacing * 1.5
                        tip: i18n("%1 in %2 on %3, running %4", job.cmd, job.project, job.worker, root.dur(job.age)) + (job.owner !== undefined ? "\n" + i18n("Owner %1: %2", root.ownerName(job.owner), root.ownerSource(job)) : "")
                        Dot {
                            color: view.runColor
                        }
                        Cell {
                            text: remRow.job.cmd || ""
                            Layout.preferredWidth: view.gu * 5
                        }
                        Cell {
                            text: remRow.job.project || ""
                            Layout.fillWidth: true
                            opacity: 0.85
                        }
                        Cell {
                            text: root.ownerName(remRow.job.owner) + (remRow.job.owner && root.inferred(remRow.job) ? " ≈" : "")
                            Layout.preferredWidth: view.gu * 5
                            opacity: remRow.job.owner ? 0.85 : 0.5
                            font.italic: !remRow.job.owner
                        }
                        Cell {
                            text: remRow.job.worker || ""
                            Layout.preferredWidth: view.gu * 2.8
                            font.pointSize: root.fsSmall
                            opacity: 0.6
                        }
                        Cell {
                            text: root.dur(remRow.job.age)
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: view.gu * 3.5
                        }
                    }
                }
                Small {
                    text: (root.remoteRunning.length === 0 ? i18n("Nothing running.") + " " : "") + i18n("Last hour: %1 ok, %2 failed", root.remote.ok || 0, root.remote.failed || 0)
                }
            }

            // The next jobs in queue order.
            Card {
                Layout.fillWidth: true
                visible: root.nextJobs.length > 0
                title: i18n("Next in line")
                header: Small {
                    text: i18n("%1 of %2 waiting", root.nextJobs.length, root.waiting.count)
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing * 1.5
                    Head {
                        text: "#"
                        Layout.preferredWidth: view.gu * 0.9
                        horizontalAlignment: Text.AlignRight
                    }
                    Head {
                        text: i18n("Session")
                        Layout.fillWidth: true
                    }
                    Head {
                        text: i18n("Worktree")
                        Layout.preferredWidth: view.gu * 5
                    }
                    Head {
                        text: i18n("Class")
                        Layout.preferredWidth: view.gu * 5
                    }
                    Head {
                        text: i18n("Waited")
                        Layout.preferredWidth: view.gu * 6.4
                        horizontalAlignment: Text.AlignRight
                    }
                }
                Repeater {
                    model: root.nextJobs.length
                    delegate: HoverRow {
                        id: nextRow
                        required property int index
                        readonly property var job: root.nextJobs[index] || ({})
                        readonly property bool urgent: job.prio === "critical" || job.prio === "high"
                        Layout.fillWidth: true
                        minHeight: view.rowH
                        spacing: Kirigami.Units.smallSpacing * 1.5
                        tip: i18n("%1 in %2, %3 priority\nOwner %4: %5\nWaited %6, %7\nRuns about %8", job.cls, job.project, job.prio, root.ownerName(job.owner), root.ownerSource(job), root.dur(job.waited), root.causeLabel(job.cause), root.dur(job.est)) + (root.remoteHint(job) ? "\n" + i18n("Could run on %1: job run --on %1 -- <command>", root.remoteTarget) : "")
                        Cell {
                            text: nextRow.index + 1
                            Layout.preferredWidth: view.gu * 0.9
                            horizontalAlignment: Text.AlignRight
                            opacity: 0.5
                        }
                        Cell {
                            text: root.ownerName(nextRow.job.owner) + (nextRow.job.owner && root.inferred(nextRow.job) ? " ≈" : "")
                            Layout.fillWidth: true
                            font.italic: !nextRow.job.owner
                            opacity: nextRow.job.owner ? 1 : 0.55
                        }
                        Cell {
                            text: nextRow.job.project || ""
                            Layout.preferredWidth: view.gu * 5
                            opacity: 0.85
                        }
                        Cell {
                            text: nextRow.job.cls || ""
                            Layout.preferredWidth: view.gu * 5
                            opacity: 0.85
                        }
                        ValueBar {
                            visible: !root.remoteHint(nextRow.job)
                            Layout.preferredWidth: view.gu * 2.6
                            value: nextRow.job.waited
                            max: view.nextMax
                            fill: nextRow.urgent ? view.prioColor(nextRow.job.prio) : view.waitColor
                        }
                        Small {
                            // Could run on a remote worker: shown in the bar's place, so columns stay put.
                            visible: root.remoteHint(nextRow.job)
                            text: "→ " + root.remoteTarget
                            color: view.runColor
                            opacity: 1
                            elide: Text.ElideRight
                            Layout.preferredWidth: view.gu * 2.6
                        }
                        Cell {
                            text: root.dur(nextRow.job.waited)
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: view.gu * 3.5
                        }
                    }
                }
            }

            // Sessions: by owning session (session, worktree, jobs), or every job in run order.
            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                title: i18n("Sessions")
                header: [
                    Repeater {
                        model: [["session", i18n("By session"), i18n("Jobs grouped by the session that owns them, then by worktree")], ["queue", i18n("Queue order"), i18n("Every job in the order heavy-build runs it")]]
                        delegate: HoverRow {
                            id: modeTab
                            required property var modelData
                            readonly property bool on: root.listMode === modelData[0]
                            clickable: !on
                            tip: modelData[2]
                            color: on ? root.tint(0.14) : hovered ? root.tint(0.08) : "transparent"
                            border.width: 1
                            border.color: on ? root.tint(0.24) : root.tint(0.12)
                            TapHandler {
                                onTapped: root.listMode = modelData[0]
                            }
                            PlasmaComponents.Label {
                                Layout.leftMargin: Kirigami.Units.smallSpacing
                                Layout.rightMargin: Kirigami.Units.smallSpacing
                                text: modelData[1]
                                font.pointSize: root.fsSmall
                                opacity: modeTab.on ? 1 : 0.65
                            }
                        }
                    },
                    Item {
                        Layout.fillWidth: true
                    },
                    Repeater {
                        model: root.listMode === "session" ? [[i18n("waiting"), view.waitColor], [i18n("running"), view.runColor], [i18n("ok"), view.okColor], [i18n("failed"), view.failColor]] : []
                        delegate: RowLayout {
                            required property var modelData
                            spacing: 3
                            Rectangle {
                                implicitWidth: 7
                                implicitHeight: 7
                                radius: 1
                                color: modelData[1]
                            }
                            Small {
                                text: modelData[0]
                            }
                        }
                    }
                ]

                // By session.
                RowLayout {
                    visible: root.listMode === "session"
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing * 1.5
                    Head {
                        text: i18n("Session")
                        Layout.leftMargin: view.gu * 0.8 + Kirigami.Units.smallSpacing * 1.5 + 3
                        Layout.fillWidth: true
                    }
                    Head {
                        text: i18n("Jobs")
                        Layout.preferredWidth: view.gu * 4.2
                    }
                    Head {
                        text: i18n("This hour")
                        Layout.preferredWidth: view.gu * 4.2
                    }
                    Head {
                        text: i18n("Queue")
                        Layout.preferredWidth: view.gu * 2.8
                    }
                    Head {
                        text: i18n("Priority")
                        Layout.preferredWidth: view.gu * 4.6
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
                ListView {
                    id: lanes
                    visible: root.listMode === "session"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: view.gu * 4
                    clip: true
                    model: root.projects.length
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: ColumnLayout {
                        id: lane
                        required property int index
                        readonly property var modelData: root.projects[index] || ({ name: "", waiting: 0, running: 0, finished: 0, failed: 0, jobs: [], spark: [], lanes: [] })
                        readonly property bool open: root.laneOpen(modelData.name, index)
                        readonly property var rows: open ? root.laneRows(modelData, 8) : []
                        width: ListView.view.width
                        spacing: 0

                        HoverRow {
                            Layout.fillWidth: true
                            minHeight: view.rowH * 1.1
                            spacing: Kirigami.Units.smallSpacing * 1.5
                            // Only the name, counts, bar and sparkline open the session, so a
                            // click on the stepper never does.
                            HoverRow {
                                Layout.fillWidth: true
                                clickable: true
                                spacing: Kirigami.Units.smallSpacing * 1.5
                                tip: i18n("%1: %2 waiting, %3 running, %4 finished and %5 failed in the last hour, in %6 worktrees. Click to %7.", root.ownerName(lane.modelData.name), lane.modelData.waiting, lane.modelData.running, lane.modelData.finished, lane.modelData.failed, (lane.modelData.lanes || []).length, lane.open ? i18n("close") : i18n("show its worktrees"))
                                TapHandler {
                                    onTapped: root.toggleLane(lane.modelData.name, lane.index)
                                }
                                Kirigami.Icon {
                                    source: lane.open ? "go-down-symbolic" : "go-next-symbolic"
                                    implicitWidth: view.gu * 0.8
                                    implicitHeight: implicitWidth
                                    opacity: 0.7
                                }
                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: root.ownerName(lane.modelData.name) + (lane.modelData.name && !lane.modelData.ownerLive ? " " + i18n("(ended)") : "")
                                    font.weight: Font.DemiBold
                                    font.italic: !lane.modelData.name
                                    opacity: lane.modelData.name ? 1 : 0.6
                                    elide: Text.ElideRight
                                }
                                PlasmaComponents.Label {
                                    Layout.preferredWidth: view.gu * 4.2
                                    textFormat: Text.StyledText
                                    text: view.counts(lane.modelData)
                                    font.pointSize: root.fsSmall
                                }
                                StackBar {
                                    Layout.preferredWidth: view.gu * 4.2
                                    max: view.laneMax
                                    parts: [[lane.modelData.waiting, view.waitColor], [lane.modelData.running, view.runColor], [lane.modelData.finished - lane.modelData.failed, view.okColor], [lane.modelData.failed, view.failColor]]
                                }
                                Spark {
                                    Layout.preferredWidth: view.gu * 2.8
                                    values: lane.modelData.spark || []
                                    line: view.waitColor
                                }
                            }
                            Stepper {
                                prio: lane.modelData.prio
                                match: lane.modelData.name
                            }
                        }

                        // The open session's worktrees and jobs. The model is a count, so
                        // the rows are kept between refreshes and only their bindings update.
                        Repeater {
                            model: lane.rows.length
                            delegate: HoverRow {
                                id: sub
                                required property int index
                                readonly property var modelData: lane.rows[index] || ({ kind: "more", depth: 0, text: "" })
                                readonly property bool isLane: modelData.kind === "lane"
                                readonly property bool isJob: modelData.kind === "job"
                                readonly property var kid: isLane ? modelData.lane : ({})
                                Layout.fillWidth: true
                                minHeight: view.rowH
                                clickable: isLane
                                spacing: Kirigami.Units.smallSpacing * 1.5
                                tip: isLane ? i18n("%1: %2 waiting, %3 running, %4 finished and %5 failed in the last hour.\nOwner: %6.\nClick to %7.", kid.name, kid.waiting, kid.running, kid.finished, kid.failed, root.ownerSource(kid), modelData.open ? i18n("close") : i18n("show its jobs"))
                                    : isJob ? i18n("%1, %2 priority", modelData.job.cls, modelData.job.prio || "normal") + (modelData.job.agent ? "\n" + i18n("subagent %1", modelData.job.agent) : "") : ""
                                TapHandler {
                                    enabled: sub.isLane
                                    onTapped: root.toggleLane(sub.kid.name, 1)
                                }
                                // Tree line in the chevron column.
                                Item {
                                    implicitWidth: view.gu * 0.8
                                    Layout.fillHeight: true
                                    Rectangle {
                                        x: parent.width / 2
                                        width: 1
                                        height: parent.height
                                        color: view.line
                                    }
                                }
                                Item {
                                    implicitWidth: view.gu * 0.8 * sub.modelData.depth
                                }
                                Kirigami.Icon {
                                    visible: sub.isLane
                                    source: sub.isLane && sub.modelData.open ? "go-down-symbolic" : "go-next-symbolic"
                                    implicitWidth: view.gu * 0.65
                                    implicitHeight: implicitWidth
                                    opacity: 0.6
                                }
                                Dot {
                                    visible: sub.isJob
                                    color: sub.isJob ? view.stateColor(sub.modelData.job.state) : "transparent"
                                }
                                Cell {
                                    Layout.fillWidth: !sub.isJob
                                    Layout.preferredWidth: sub.isJob ? view.gu * 5 : -1
                                    text: sub.isLane ? sub.kid.name + (root.inferred(sub.kid) ? " ≈" : "") : sub.isJob ? sub.modelData.job.cls : (sub.modelData.text || "")
                                    font.pointSize: sub.isLane ? root.fsRow : root.fsSmall
                                    opacity: sub.isLane ? 0.95 : sub.modelData.kind === "more" ? 0.5 : 0.85
                                }
                                // A worktree: counts, bar, sparkline and its effective priority.
                                PlasmaComponents.Label {
                                    visible: sub.isLane
                                    Layout.preferredWidth: view.gu * 4.2
                                    textFormat: Text.StyledText
                                    text: sub.isLane ? view.counts(sub.kid) : ""
                                    font.pointSize: root.fsSmall
                                }
                                StackBar {
                                    visible: sub.isLane
                                    Layout.preferredWidth: view.gu * 4.2
                                    implicitHeight: 6
                                    max: view.laneMax
                                    parts: sub.isLane ? [[sub.kid.waiting, view.waitColor], [sub.kid.running, view.runColor], [sub.kid.finished - sub.kid.failed, view.okColor], [sub.kid.failed, view.failColor]] : []
                                }
                                Spark {
                                    visible: sub.isLane
                                    Layout.preferredWidth: view.gu * 2.8
                                    values: sub.isLane ? (sub.kid.spark || []) : []
                                    line: view.waitColor
                                }
                                Stepper {
                                    visible: sub.isLane
                                    prio: sub.isLane ? sub.kid.prio : null
                                    match: sub.isLane ? sub.kid.name : ""
                                    editable: false
                                    border.width: 0
                                    color: "transparent"
                                }
                                // A job: what it is doing.
                                Small {
                                    visible: sub.isJob
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    opacity: 0.75
                                    text: {
                                        if (!sub.isJob)
                                            return "";
                                        const j = sub.modelData.job;
                                        if (j.state === "running")
                                            return i18n("running %1", root.dur(j.age));
                                        if (j.state === "waiting")
                                            return i18n("waiting #%1, %2, %3", j.pos, root.dur(j.age), root.causeLabel(j.cause));
                                        const at = Qt.formatTime(new Date(j.end * 1000), "HH:mm");
                                        return j.state === "ok" ? i18n("finished ok %1", at) : i18n("failed %1", at);
                                    }
                                }
                            }
                        }
                    }
                }

                // Queue order: running jobs, then every waiting job in heavy-build's order,
                // each with its owning session.
                RowLayout {
                    visible: root.listMode === "queue"
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing * 1.5
                    Head {
                        text: "#"
                        Layout.preferredWidth: view.gu * 1.1
                        horizontalAlignment: Text.AlignRight
                    }
                    Head {
                        text: i18n("Session")
                        Layout.preferredWidth: view.gu * 5.6
                    }
                    Head {
                        text: i18n("Worktree")
                        Layout.preferredWidth: view.gu * 5.6
                    }
                    Head {
                        text: i18n("Class")
                        Layout.fillWidth: true
                    }
                    Head {
                        text: i18n("Time")
                        Layout.preferredWidth: view.gu * 6.4
                        horizontalAlignment: Text.AlignRight
                    }
                }
                ListView {
                    visible: root.listMode === "queue"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: view.gu * 4
                    clip: true
                    model: root.queueRows.length
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: HoverRow {
                        id: qrow
                        required property int index
                        readonly property var job: root.queueRows[index] || ({ state: "", project: "", cls: "", owner: "", age: 0 })
                        readonly property bool run: job.state === "running"
                        width: ListView.view.width
                        minHeight: view.rowH
                        spacing: Kirigami.Units.smallSpacing * 1.5
                        tip: i18n("%1 in %2, %3 priority\nOwner %4: %5", job.cls, job.project, job.prio || "normal", root.ownerName(job.owner), root.ownerSource(job)) + (run ? "\n" + i18n("Running %1", root.dur(job.age)) : "\n" + i18n("Waited %1, %2", root.dur(job.age), root.causeLabel(job.cause))) + (root.remoteHint(job) ? "\n" + i18n("Could run on %1: job run --on %1 -- <command>", root.remoteTarget) : "")
                        Cell {
                            text: qrow.run ? "▶" : qrow.job.pos
                            color: qrow.run ? view.runColor : Kirigami.Theme.textColor
                            opacity: qrow.run ? 1 : 0.5
                            font.pointSize: root.fsSmall
                            Layout.preferredWidth: view.gu * 1.1
                            horizontalAlignment: Text.AlignRight
                        }
                        Cell {
                            text: root.ownerName(qrow.job.owner) + (qrow.job.owner && root.inferred(qrow.job) ? " ≈" : "")
                            font.italic: !qrow.job.owner
                            opacity: qrow.job.owner ? 1 : 0.55
                            Layout.preferredWidth: view.gu * 5.6
                        }
                        Cell {
                            text: qrow.job.project
                            opacity: 0.85
                            Layout.preferredWidth: view.gu * 5.6
                        }
                        Cell {
                            text: qrow.job.cls
                            opacity: 0.85
                            Layout.fillWidth: true
                        }
                        Cell {
                            visible: qrow.job.prio === "high" || qrow.job.prio === "critical" || qrow.job.prio === "low"
                            text: qrow.job.prio || ""
                            font.pointSize: root.fsSmall
                            color: view.prioColor(qrow.job.prio)
                        }
                        ValueBar {
                            visible: !root.remoteHint(qrow.job)
                            Layout.preferredWidth: view.gu * 2.6
                            value: qrow.job.age
                            max: view.queueMax
                            fill: qrow.run ? view.runColor : view.waitColor
                        }
                        Small {
                            // Could run on a remote worker: shown in the bar's place, so columns stay put.
                            visible: root.remoteHint(qrow.job)
                            text: "→ " + root.remoteTarget
                            color: view.runColor
                            opacity: 1
                            elide: Text.ElideRight
                            Layout.preferredWidth: view.gu * 2.6
                        }
                        Cell {
                            text: root.dur(qrow.job.age)
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: view.gu * 3.5
                        }
                    }
                }
            }

            Small {
                Layout.fillWidth: true
                text: i18n("Queue rules: %1", root.q.limits || "?")
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }
}
