// Build Queue: the heavy-build queue at a glance. Whether the gate lets jobs start, what
// runs and what starts next, why jobs wait, how the queue grew over the last hour, and each
// lane (project) with its jobs and its priority. Machine resources are left out: Tasklens
// shows them beside this window.
// Data comes from $XDG_RUNTIME_DIR/buildqueue/queue.json, which ~/bin/buildqueue-fetch
// rewrites every five seconds. It only reads. Colours and fonts come from the Plasma style,
// so the window matches the panels.
// Run as a window with ~/bin/buildqueue-window, which starts the fetch and sets
// QML_XHR_ALLOW_FILE_READ=1 so the widget may read the file.

import QtCore
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
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
    readonly property var nextJobs: q.next || []
    readonly property var history: q.history || []

    // Lane name -> true or false, for lanes the owner opened or closed. The top lane starts open.
    property var expanded: ({})

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

    // The rows of an open lane: sessions and subagents when heavy-build names them, then
    // their jobs. Jobs without a session come first, as a flat list.
    function laneRows(lane, max) {
        const rows = [];
        const groups = {};
        const order = [];
        for (const j of lane.jobs || []) {
            const key = (j.session || "") + "\u0000" + (j.agent || "");
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
            let depth = 0;
            if (session) {
                if (session !== lastSession)
                    rows.push({
                        kind: "group",
                        depth: 0,
                        text: i18n("session %1", session)
                    });
                lastSession = session;
                depth = 1;
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
                depth: 0,
                text: i18n("+ %1 more jobs", total - shown)
            });
        return rows;
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
    readonly property color accentText: Kirigami.ColorUtils.tintWithAlpha(styled ? style.accent : Kirigami.Theme.highlightColor, "white", 0.35)

    component Heading: PlasmaComponents.Label {
        color: root.accentText
        font.bold: true
        Layout.topMargin: Kirigami.Units.smallSpacing
    }

    component Dim: PlasmaComponents.Label {
        opacity: 0.7
    }

    component Small: PlasmaComponents.Label {
        font: Kirigami.Theme.smallFont
        opacity: 0.75
    }

    // A row that lights up under the mouse and shows `tip` as a tooltip. `clickable` rows
    // light up more and show a hand cursor.
    component HoverRow: Rectangle {
        id: hoverRow
        default property alias content: row.data
        property alias spacing: row.spacing
        property string tip: ""
        property bool clickable: false
        readonly property bool hovered: hover.hovered
        implicitHeight: row.implicitHeight + 2
        implicitWidth: row.implicitWidth + 4
        radius: 3
        color: hover.hovered ? Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, Kirigami.Theme.highlightColor, clickable ? 0.3 : 0.16) : "transparent"
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
            anchors.leftMargin: 2
            anchors.rightMargin: 2
            spacing: Kirigami.Units.smallSpacing
        }
        PlasmaComponents.ToolTip.visible: hover.hovered && tip !== ""
        PlasmaComponents.ToolTip.text: tip
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
    }

    // A small square button for a lane's priority. It lights up under the mouse even when
    // it cannot act yet, and its tooltip says why.
    component PrioButton: Rectangle {
        id: prioButton
        property string iconName: ""
        property string tip: ""
        property bool active: false
        signal clicked
        implicitWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
        implicitHeight: implicitWidth
        radius: 3
        color: tap.pressed && active ? Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, Kirigami.Theme.highlightColor, 0.6)
            : hover.hovered ? Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, Kirigami.Theme.highlightColor, active ? 0.45 : 0.22)
            : "transparent"
        border.width: hover.hovered ? 1 : 0
        border.color: Kirigami.Theme.highlightColor
        Kirigami.Icon {
            anchors.centerIn: parent
            source: prioButton.iconName
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: implicitWidth
            opacity: prioButton.active ? 1 : 0.45
        }
        HoverHandler {
            id: hover
            cursorShape: prioButton.active ? Qt.PointingHandCursor : Qt.ForbiddenCursor
        }
        TapHandler {
            id: tap
            onTapped: if (prioButton.active) prioButton.clicked()
        }
        PlasmaComponents.ToolTip.visible: hover.hovered
        PlasmaComponents.ToolTip.text: tip
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
    }

    // A row of cells, `used` of `total` filled: job slots and app-run slots.
    component CellMeter: Row {
        property int total: 0
        property int used: 0
        property color fill: Kirigami.Theme.positiveTextColor
        spacing: 2
        Repeater {
            model: Math.max(0, parent.total)
            delegate: Rectangle {
                required property int index
                width: Kirigami.Units.gridUnit * 0.75
                height: Kirigami.Units.gridUnit * 0.6
                radius: 2
                color: index < parent.used ? parent.fill : Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.12)
            }
        }
    }

    // A bar `value` long on a scale of `max`, with a faint track behind it.
    component ValueBar: Rectangle {
        property real value: 0
        property real max: 1
        property color fill: root.accentText
        implicitHeight: Kirigami.Units.smallSpacing * 2
        radius: height / 2
        color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.08)
        Rectangle {
            height: parent.height
            radius: parent.radius
            width: parent.max > 0 ? Math.max(value > 0 ? 2 : 0, parent.width * Math.min(1, parent.value / parent.max)) : 0
            color: parent.fill
        }
    }

    // Segments side by side, each `[count, colour]`, scaled to `max` (default: their sum).
    component StackBar: Item {
        property var parts: []
        property real max: 0
        implicitHeight: Kirigami.Units.smallSpacing * 2.5
        readonly property real sum: parts.reduce((a, p) => a + p[0], 0)
        Rectangle {
            anchors.fill: parent
            radius: 2
            color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.08)
        }
        Row {
            height: parent.height
            Repeater {
                model: parent.parent.parts
                delegate: Rectangle {
                    required property var modelData
                    readonly property real scale: parent.parent.max > 0 ? parent.parent.max : parent.parent.sum
                    height: parent.height
                    width: scale > 0 ? parent.parent.width * modelData[0] / scale : 0
                    color: modelData[1]
                }
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
        readonly property color runColor: Kirigami.Theme.linkColor
        readonly property color waitColor: Kirigami.Theme.neutralTextColor
        readonly property color okColor: Kirigami.Theme.positiveTextColor
        readonly property color failColor: Kirigami.Theme.negativeTextColor
        readonly property var causePalette: [Kirigami.Theme.negativeTextColor, Kirigami.Theme.neutralTextColor, Kirigami.Theme.linkColor, root.accentText, Kirigami.Theme.positiveTextColor, Kirigami.Theme.disabledTextColor]
        readonly property color faint: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.08)

        function prioColor(p) {
            if (p === "critical")
                return Kirigami.Theme.negativeTextColor;
            if (p === "high")
                return Kirigami.Theme.neutralTextColor;
            return Kirigami.Theme.disabledTextColor;
        }

        function stateColor(s) {
            return s === "running" ? runColor : s === "waiting" ? waitColor : s === "ok" ? okColor : failColor;
        }

        // Where a wait of `s` seconds sits on the 1 min to 10 h log axis, from 0 to 1.
        function logPos(s) {
            const v = Math.log(Math.max(60, s) / 60) / Math.log(600);
            return Math.max(0, Math.min(1, v));
        }

        readonly property var causeList: (root.waiting.causes || []).slice(0, 4)
        readonly property var causeParts: (root.waiting.causes || []).map((c, i) => [c.count, causePalette[Math.min(i, causePalette.length - 1)]])
        readonly property real runMax: root.running.reduce((a, b) => Math.max(a, b.runtime), 60)
        readonly property real nextMax: root.nextJobs.reduce((a, j) => Math.max(a, j.waited), 60)
        readonly property real laneMax: root.projects.reduce((a, p) => Math.max(a, p.waiting + p.running + p.finished), 1)
        readonly property int finishedTotal: Object.values(root.velocity.finished || {}).reduce((a, n) => a + n, 0)
        readonly property real flowMax: Math.max(1, root.velocity.arrived || 0, root.velocity.started || 0, finishedTotal)

        Layout.minimumWidth: Kirigami.Units.gridUnit * 22
        Layout.minimumHeight: Kirigami.Units.gridUnit * 30
        Layout.preferredWidth: Kirigami.Units.gridUnit * 29
        Layout.preferredHeight: Kirigami.Units.gridUnit * 60

        Kirigami.Theme.inherit: !root.styled
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.backgroundColor: root.styled ? root.style.background : undefined
        Kirigami.Theme.alternateBackgroundColor: root.styled ? root.style.alternate : undefined
        Kirigami.Theme.textColor: root.styled ? root.style.text : undefined
        Kirigami.Theme.disabledTextColor: root.styled ? root.style.inactive : undefined
        Kirigami.Theme.negativeTextColor: root.styled ? root.style.negative : undefined
        Kirigami.Theme.neutralTextColor: root.styled ? root.style.neutral : undefined
        Kirigami.Theme.positiveTextColor: root.styled ? root.style.positive : undefined
        Kirigami.Theme.highlightColor: root.styled ? root.style.accent : undefined
        Kirigami.Theme.highlightedTextColor: root.styled ? root.style.accentText : undefined
        color: Kirigami.Theme.backgroundColor

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            // Header: the gate state, and why.
            RowLayout {
                Layout.fillWidth: true
                PlasmaExtras.Heading {
                    level: 2
                    text: i18n("Build Queue")
                }
                Item {
                    Layout.fillWidth: true
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
                Rectangle {
                    implicitWidth: gateLabel.implicitWidth + Kirigami.Units.largeSpacing * 2
                    implicitHeight: gateLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
                    radius: Kirigami.Units.smallSpacing
                    color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, view.gateColor, 0.25)
                    border.width: 1
                    border.color: view.gateColor
                    PlasmaComponents.Label {
                        id: gateLabel
                        anchors.centerIn: parent
                        text: root.gate.state === "paused" ? i18n("PAUSED") : root.gate.state === "slowed" ? i18n("SLOWED") : root.gate.state === "open" ? i18n("OPEN") : i18n("UNKNOWN")
                        color: view.gateColor
                        font.bold: true
                    }
                }
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: root.gate.state === "open" ? Kirigami.Theme.textColor : view.gateColor
                text: {
                    const since = root.gate.since ? Qt.formatTime(new Date(root.gate.since * 1000), "HH:mm") : "";
                    const what = root.gate.state === "paused" ? i18n("Only high and critical jobs start.")
                        : root.gate.state === "slowed" ? i18n("One new job at a time.")
                        : root.gate.state === "open" ? i18n("Jobs start when they fit.") : "";
                    return since && root.gate.state !== "open" ? i18n("Since %1: %2. %3", since, root.gate.reason || "", what) : what;
                }
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: root.problem !== ""
                text: root.problem
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.Wrap
            }

            // The key numbers, each with a visual.
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing * 1.5

                ColumnLayout {
                    spacing: 2
                    Layout.alignment: Qt.AlignTop
                    Small {
                        text: i18n("Running")
                    }
                    PlasmaExtras.Heading {
                        level: 1
                        text: i18n("%1 of %2", root.running.length, root.slots.jobs || "?")
                    }
                    CellMeter {
                        total: root.slots.jobs || 0
                        used: root.running.length
                        fill: view.runColor
                    }
                    Small {
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        text: i18n("app runs %1 of %2", root.slots.appRunsUsed || 0, root.slots.appRuns || "?")
                    }
                    CellMeter {
                        total: root.slots.appRuns || 0
                        used: root.slots.appRunsUsed || 0
                        fill: root.accentText
                    }
                }

                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    Small {
                        text: i18n("Waiting")
                    }
                    PlasmaExtras.Heading {
                        level: 1
                        text: root.waiting.count
                        color: root.waiting.count > 0 ? view.waitColor : Kirigami.Theme.textColor
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
                            tip: modelData.example || ""
                            Rectangle {
                                implicitWidth: Kirigami.Units.smallSpacing * 2
                                implicitHeight: implicitWidth
                                radius: width / 2
                                color: view.causePalette[Math.min(index, view.causePalette.length - 1)]
                            }
                            PlasmaComponents.Label {
                                text: modelData.count
                                font: Kirigami.Theme.smallFont
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 1.4
                                horizontalAlignment: Text.AlignRight
                            }
                            Small {
                                Layout.fillWidth: true
                                text: root.causeLabel(modelData.kind)
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                ColumnLayout {
                    spacing: 2
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                    Layout.alignment: Qt.AlignTop
                    Small {
                        text: i18n("Oldest wait")
                    }
                    PlasmaExtras.Heading {
                        level: 1
                        text: root.waiting.count > 0 ? root.dur(root.waiting.oldest) : "–"
                    }
                    // A log axis from 1 min to 10 h: median and slowest 10% of the jobs that
                    // started in the last hour, and the oldest job still waiting.
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: Kirigami.Units.gridUnit * 1.6
                        Rectangle {
                            y: Kirigami.Units.smallSpacing
                            width: parent.width
                            height: 2
                            color: view.faint
                        }
                        Repeater {
                            model: [[root.velocity.waitMedian, view.okColor], [root.velocity.waitP90, view.waitColor], [root.waiting.count > 0 ? root.waiting.oldest : null, view.failColor]]
                            delegate: Rectangle {
                                required property var modelData
                                visible: modelData[0] !== null && modelData[0] !== undefined
                                x: parent.width * view.logPos(modelData[0] || 0) - width / 2
                                width: Kirigami.Units.smallSpacing * 2
                                height: width
                                radius: width / 2
                                color: modelData[1]
                            }
                        }
                        Repeater {
                            model: [[60, i18n("1 min")], [3600, i18n("1 h")], [36000, i18n("10 h")]]
                            delegate: PlasmaComponents.Label {
                                required property var modelData
                                required property int index
                                y: Kirigami.Units.smallSpacing * 2.5
                                x: Math.max(0, Math.min(parent.width - width, parent.width * view.logPos(modelData[0]) - width / 2))
                                text: modelData[1]
                                font: Kirigami.Theme.smallFont
                                opacity: 0.5
                            }
                        }
                    }
                    Small {
                        textFormat: Text.StyledText
                        text: i18n("<font color='%1'>●</font> median %2", view.okColor, root.dur(root.velocity.waitMedian))
                    }
                    Small {
                        textFormat: Text.StyledText
                        text: i18n("<font color='%1'>●</font> slowest 10% %2", view.waitColor, root.dur(root.velocity.waitP90))
                    }
                }
            }

            // Queue length over the last hour, with the slowed and paused stretches shaded,
            // and the flow of jobs beside it.
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.largeSpacing * 1.5

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    RowLayout {
                        Layout.fillWidth: true
                        Heading {
                            Layout.topMargin: 0
                            text: i18n("Queue, last hour")
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        PlasmaComponents.Label {
                            readonly property int t: root.velocity.trend || 0
                            visible: root.velocity.trend !== null && root.velocity.trend !== undefined
                            text: t > 0 ? i18n("+%1 in %2 min", t, root.velocity.trendMinutes) : t < 0 ? i18n("%1 in %2 min", t, root.velocity.trendMinutes) : i18n("steady")
                            color: t > 0 ? Kirigami.Theme.negativeTextColor : t < 0 ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.textColor
                            font: Kirigami.Theme.smallFont
                        }
                    }
                    Canvas {
                        id: chart
                        Layout.fillWidth: true
                        implicitHeight: Kirigami.Units.gridUnit * 4
                        readonly property var points: root.history
                        readonly property color line: view.waitColor
                        readonly property color slowBand: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, Kirigami.Theme.neutralTextColor, 0.18)
                        readonly property color pauseBand: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, Kirigami.Theme.negativeTextColor, 0.22)
                        readonly property color text: Kirigami.Theme.disabledTextColor
                        readonly property string key: points.length ? points.length + ":" + points[points.length - 1][0] : ""
                        onKeyChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            const pts = points;
                            if (pts.length < 2)
                                return;
                            const t1 = pts[pts.length - 1][0], t0 = t1 - 3600;
                            const top = Math.max(10, ...pts.map(p => p[1]));
                            const fontPx = 11;
                            const h = height - fontPx - 4, w = width;
                            const X = t => w * (t - t0) / 3600;
                            const Y = n => h - h * n / top;
                            for (let i = 0; i < pts.length - 1; i++) {
                                const lvl = pts[i][2];
                                if (lvl === "slow" || lvl === "pause") {
                                    ctx.fillStyle = lvl === "pause" ? pauseBand : slowBand;
                                    ctx.fillRect(X(pts[i][0]), 0, X(pts[i + 1][0]) - X(pts[i][0]) + 0.5, h);
                                }
                            }
                            ctx.beginPath();
                            ctx.moveTo(X(pts[0][0]), h);
                            for (const p of pts)
                                ctx.lineTo(X(p[0]), Y(p[1]));
                            ctx.lineTo(X(t1), h);
                            ctx.closePath();
                            ctx.fillStyle = Qt.rgba(line.r, line.g, line.b, 0.18);
                            ctx.fill();
                            ctx.beginPath();
                            for (let i = 0; i < pts.length; i++) {
                                if (i === 0)
                                    ctx.moveTo(X(pts[i][0]), Y(pts[i][1]));
                                else
                                    ctx.lineTo(X(pts[i][0]), Y(pts[i][1]));
                            }
                            ctx.strokeStyle = line;
                            ctx.lineWidth = 1.5;
                            ctx.stroke();
                            ctx.fillStyle = text;
                            ctx.font = fontPx + "px sans-serif";
                            ctx.textBaseline = "bottom";
                            ctx.fillText(i18n("1 h ago"), 2, height);
                            const peak = i18n("top %1", top);
                            ctx.fillText(peak, (w - ctx.measureText(peak).width) / 2, height);
                            const nowText = i18n("now %1", pts[pts.length - 1][1]);
                            ctx.fillText(nowText, w - ctx.measureText(nowText).width - 2, height);
                        }
                    }
                }

                ColumnLayout {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 9
                    Layout.alignment: Qt.AlignTop
                    spacing: 2
                    Heading {
                        Layout.topMargin: 0
                        text: i18n("Jobs, last hour")
                    }
                    Repeater {
                        model: [[i18n("arrived"), root.velocity.arrived || 0], [i18n("started"), root.velocity.started || 0], [i18n("finished"), view.finishedTotal]]
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            Small {
                                text: modelData[0]
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 3.2
                            }
                            ValueBar {
                                Layout.fillWidth: true
                                value: modelData[1]
                                max: view.flowMax
                            }
                            PlasmaComponents.Label {
                                text: modelData[1]
                                font: Kirigami.Theme.smallFont
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 1.4
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                    StackBar {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        readonly property var f: root.velocity.finished || {}
                        parts: [[f.ok || 0, view.okColor], [f.fail || 0, view.failColor], [view.finishedTotal - (f.ok || 0) - (f.fail || 0), Kirigami.Theme.neutralTextColor]]
                    }
                    Small {
                        textFormat: Text.StyledText
                        readonly property var f: root.velocity.finished || {}
                        text: i18n("<font color='%1'>%2 ok</font>, <font color='%3'>%4 failed</font>", view.okColor, f.ok || 0, view.failColor, f.fail || 0)
                    }
                }
            }

            // Running builds, longest first, each with a bar for how long it has run.
            Heading {
                text: i18n("Running now")
            }
            Repeater {
                model: root.running.length
                delegate: HoverRow {
                    required property int index
                    readonly property var modelData: root.running[index] || ({})
                    Layout.fillWidth: true
                    tip: i18n("%1 in %2, %3 priority, running %4", modelData.cls, modelData.project, modelData.prio || "normal", root.dur(modelData.runtime)) + (modelData.why ? "\n" + modelData.why : "")
                    Rectangle {
                        implicitWidth: Kirigami.Units.smallSpacing * 2
                        implicitHeight: implicitWidth
                        radius: width / 2
                        color: view.runColor
                    }
                    PlasmaComponents.Label {
                        text: modelData.cls
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                        elide: Text.ElideRight
                    }
                    PlasmaComponents.Label {
                        text: modelData.project
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                        elide: Text.ElideRight
                        opacity: 0.8
                    }
                    PlasmaComponents.Label {
                        visible: modelData.prio === "high" || modelData.prio === "critical"
                        text: modelData.prio
                        color: view.prioColor(modelData.prio)
                        font: Kirigami.Theme.smallFont
                    }
                    ValueBar {
                        Layout.fillWidth: true
                        value: modelData.runtime
                        max: view.runMax
                        fill: view.runColor
                    }
                    PlasmaComponents.Label {
                        text: root.dur(modelData.runtime)
                        horizontalAlignment: Text.AlignRight
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                    }
                }
            }
            Dim {
                visible: root.running.length === 0
                text: i18n("Nothing running")
            }

            // The next jobs in queue order, each with a bar for how long it has waited.
            RowLayout {
                Layout.fillWidth: true
                visible: root.nextJobs.length > 0
                Heading {
                    text: i18n("Next in line")
                }
                Item {
                    Layout.fillWidth: true
                }
                Small {
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    text: root.waiting.count > root.nextJobs.length ? i18n("%1 more waiting", root.waiting.count - root.nextJobs.length) : ""
                }
            }
            Repeater {
                model: root.nextJobs.length
                delegate: HoverRow {
                    required property int index
                    readonly property var modelData: root.nextJobs[index] || ({})
                    Layout.fillWidth: true
                    tip: i18n("%1 in %2, %3 priority\nWaited %4, %5\nRuns about %6", modelData.cls, modelData.project, modelData.prio, root.dur(modelData.waited), root.causeLabel(modelData.cause), root.dur(modelData.est))
                    Small {
                        text: index + 1
                        Layout.preferredWidth: Kirigami.Units.smallSpacing * 2
                    }
                    PlasmaComponents.Label {
                        text: modelData.project
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 6.5
                        elide: Text.ElideRight
                    }
                    PlasmaComponents.Label {
                        text: modelData.cls
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 5.5
                        elide: Text.ElideRight
                        opacity: 0.8
                    }
                    ValueBar {
                        Layout.fillWidth: true
                        value: modelData.waited
                        max: view.nextMax
                        fill: modelData.prio === "critical" || modelData.prio === "high" ? view.prioColor(modelData.prio) : view.waitColor
                    }
                    PlasmaComponents.Label {
                        text: root.dur(modelData.waited)
                        horizontalAlignment: Text.AlignRight
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                    }
                }
            }

            // Lanes: one row per project, as a tree. Each row has a bar split into waiting,
            // running and finished jobs, a sparkline of its queue over the hour, and its
            // priority setting.
            RowLayout {
                Layout.fillWidth: true
                Heading {
                    text: i18n("Lanes")
                }
                Item {
                    Layout.fillWidth: true
                }
                Repeater {
                    model: [[i18n("waiting"), view.waitColor], [i18n("running"), view.runColor], [i18n("ok"), view.okColor], [i18n("failed"), view.failColor]]
                    delegate: Small {
                        required property var modelData
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        textFormat: Text.StyledText
                        text: "<font color='" + modelData[1] + "'>■</font> " + modelData[0]
                    }
                }
            }
            ListView {
                id: lanes
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Kirigami.Units.gridUnit * 4
                clip: true
                model: root.projects.length
                boundsBehavior: Flickable.StopAtBounds
                delegate: ColumnLayout {
                    id: lane
                    required property int index
                    readonly property var modelData: root.projects[index] || ({ name: "", waiting: 0, running: 0, finished: 0, failed: 0, jobs: [], spark: [] })
                    readonly property bool open: root.laneOpen(modelData.name, index)
                    readonly property int step: root.prioStep(modelData.prio)
                    width: ListView.view.width
                    spacing: 0

                    HoverRow {
                        Layout.fillWidth: true
                        // Only the name, bar and sparkline open the lane, so a click on a
                        // priority button never does.
                        HoverRow {
                            Layout.fillWidth: true
                            clickable: true
                            tip: i18n("%1: %2 waiting, %3 running, %4 finished and %5 failed in the last hour. Click to %6.", lane.modelData.name, lane.modelData.waiting, lane.modelData.running, lane.modelData.finished, lane.modelData.failed, lane.open ? i18n("close") : i18n("show its jobs"))
                            TapHandler {
                                onTapped: root.toggleLane(lane.modelData.name, lane.index)
                            }
                        Kirigami.Icon {
                            source: lane.open ? "go-down-symbolic" : "go-next-symbolic"
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: implicitWidth
                        }
                        PlasmaComponents.Label {
                            text: lane.modelData.name
                            font.bold: lane.open
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 6.5
                            elide: Text.ElideRight
                        }
                        StackBar {
                            Layout.fillWidth: true
                            max: view.laneMax
                            parts: [[lane.modelData.waiting, view.waitColor], [lane.modelData.running, view.runColor], [lane.modelData.finished - lane.modelData.failed, view.okColor], [lane.modelData.failed, view.failColor]]
                        }
                        PlasmaComponents.Label {
                            text: lane.modelData.waiting
                            font: Kirigami.Theme.smallFont
                            color: lane.modelData.waiting > 0 ? view.waitColor : Kirigami.Theme.disabledTextColor
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.4
                            horizontalAlignment: Text.AlignRight
                        }
                        Canvas {
                            implicitWidth: Kirigami.Units.gridUnit * 3
                            implicitHeight: Kirigami.Units.gridUnit * 0.9
                            readonly property var spark: lane.modelData.spark || []
                            readonly property color line: view.waitColor
                            readonly property string key: spark.join(",")
                            onKeyChanged: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                const s = spark;
                                if (s.length < 2)
                                    return;
                                const top = Math.max(1, ...s);
                                ctx.beginPath();
                                for (let i = 0; i < s.length; i++) {
                                    const x = width * i / (s.length - 1), y = height - 1 - (height - 2) * s[i] / top;
                                    if (i === 0)
                                        ctx.moveTo(x, y);
                                    else
                                        ctx.lineTo(x, y);
                                }
                                ctx.strokeStyle = line;
                                ctx.lineWidth = 1;
                                ctx.stroke();
                            }
                        }
                        }
                        // Priority: a track with a marker at -1, 0 or +1. The buttons are
                        // off until heavy-build-prio is installed.
                        PrioButton {
                            iconName: "go-down-symbolic"
                            tip: root.q.prioTool ? i18n("Lower this lane's priority") : i18n("Lower this lane's priority. Not available yet: heavy-build-prio is not installed.")
                        }
                        Item {
                            implicitWidth: Kirigami.Units.gridUnit * 2
                            implicitHeight: Kirigami.Units.gridUnit * 0.8
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 2
                                color: view.faint
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                x: parent.width * (Math.max(-1, Math.min(1, lane.step)) + 1) / 2 - width / 2
                                width: Kirigami.Units.smallSpacing * 2.5
                                height: width
                                radius: width / 2
                                color: lane.step > 0 ? Kirigami.Theme.positiveTextColor : lane.step < 0 ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.disabledTextColor
                            }
                            HoverHandler {
                                id: prioHover
                            }
                            PlasmaComponents.ToolTip.visible: prioHover.hovered
                            PlasmaComponents.ToolTip.text: lane.modelData.prio ? i18n("Priority %1 (set by %2, rule %3)", lane.modelData.prio.prio, lane.modelData.prio.by || "?", lane.modelData.prio.rule) : i18n("Normal priority")
                        }
                        PrioButton {
                            iconName: "go-up-symbolic"
                            tip: root.q.prioTool ? i18n("Raise this lane's priority") : i18n("Raise this lane's priority. Not available yet: heavy-build-prio is not installed.")
                        }
                    }

                    // The open lane's sessions, subagents and jobs.
                    Repeater {
                        model: lane.open ? root.laneRows(lane.modelData, 8) : []
                        delegate: HoverRow {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.leftMargin: Kirigami.Units.gridUnit * (1 + modelData.depth * 0.8)
                            tip: modelData.kind === "job" ? i18n("%1, %2 priority", modelData.job.cls, modelData.job.prio || "normal") + (modelData.job.session ? "\n" + i18n("session %1", modelData.job.session) : "") + (modelData.job.agent ? "\n" + i18n("subagent %1", modelData.job.agent) : "") : ""
                            Rectangle {
                                visible: modelData.kind === "job"
                                implicitWidth: Kirigami.Units.smallSpacing * 1.6
                                implicitHeight: implicitWidth
                                radius: width / 2
                                color: modelData.kind === "job" ? view.stateColor(modelData.job.state) : "transparent"
                            }
                            PlasmaComponents.Label {
                                visible: modelData.kind !== "job"
                                text: modelData.text || ""
                                font: Kirigami.Theme.smallFont
                                opacity: modelData.kind === "more" ? 0.6 : 0.85
                            }
                            PlasmaComponents.Label {
                                visible: modelData.kind === "job"
                                text: modelData.kind === "job" ? modelData.job.cls : ""
                                font: Kirigami.Theme.smallFont
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                                elide: Text.ElideRight
                            }
                            Small {
                                visible: modelData.kind === "job"
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: {
                                    if (modelData.kind !== "job")
                                        return "";
                                    const j = modelData.job;
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
