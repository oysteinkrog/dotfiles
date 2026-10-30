// Aiolos Timeline: the Timeline view from the aiolos Accounts page on its own. It shows how
// much of the Claude pool is free now and how that is projected to move over the next 7 days,
// stepping up at each account's window reset. The maths is in timeline.js, a port of the
// dashboard's renderTimeline.
// Data comes from $XDG_RUNTIME_DIR/aiolostimeline/timeline.json, which
// ~/bin/aiolostimeline-fetch rewrites every minute. Colours follow the os-theme choice, as in
// the Agenda and the Build Queue (docs/desktop-panels-style.md). Nothing here writes.
// Run as a window with ~/bin/aiolostimeline-window, which starts the fetch and sets
// QML_XHR_ALLOW_FILE_READ=1 so the widget may read the file.

import QtCore
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "timeline.js" as TL

PlasmoidItem {
    id: root

    readonly property url dataFile: StandardPaths.writableLocation(StandardPaths.RuntimeLocation) + "/aiolostimeline/timeline.json"
    property var d: ({
            updated: 0,
            error: ""
        })
    property string lastText: ""
    property double now: Date.now()
    readonly property double startedAt: Date.now()
    // When the fetch last wrote, with data or only an error.
    property double fetched: 0
    // The fetch writes every minute, so 3 min without a new file means it has stopped.
    readonly property bool stale: fetched > 0 && now - fetched > 180000
    readonly property bool hasData: !!d.pool
    readonly property string problem: stale ? i18n("No new data for %1: is aiolostimeline-fetch running?", dur((now - fetched) / 1000))
        : !hasData && now - startedAt > 15000 && !d.error ? i18n("No data in %1. Start the window with aiolostimeline-window.", dataFile)
        : (d.error || "")

    // The lines shown, the windows counted and the accounts counted. The defaults are the
    // dashboard's: Optimistic and Last 7d, all windows, all accounts that are not paused.
    property var shownProjs: ["optimistic", "7d"]
    property string mode: "all"
    property string accts: "all"
    Settings {
        category: "AiolosTimeline"
        property alias shownProjs: root.shownProjs
        property alias mode: root.mode
        property alias accts: root.accts
    }

    // The projection model and one stepped line per projection, built again on new data or
    // a new setting.
    readonly property var m: hasData ? TL.model(d.pool, mode, accts) : null
    readonly property var lines: {
        const out = {};
        if (m && m.maxNx > 0)
            for (const p of TL.PROJS)
                out[p] = TL.series(m, p);
        return out;
    }
    readonly property real freeNow: m && m.maxNx > 0 ? TL.valueAt(m, "optimistic", m.now) : NaN
    // When the slowest and the fastest shown projection first drop below the 20% alert line.
    readonly property var alerts: {
        const out = [];
        if (!m || m.maxNx <= 0)
            return out;
        for (const p of TL.PROJS)
            if (shownProjs.indexOf(p) >= 0)
                out.push({
                    proj: p,
                    t: TL.crossing(m, p, 20)
                });
        return out;
    }

    readonly property var projMeta: ({
            optimistic: {
                label: i18n("Optimistic"),
                short: i18n("Optimistic"),
                desc: i18n("No more use until each window resets.")
            },
            current: {
                label: i18n("Current pace"),
                short: i18n("Current"),
                desc: i18n("Each window keeps being used at the pace it has had since it last reset.")
            },
            "24h": {
                label: i18n("Last 24h"),
                short: i18n("24h"),
                desc: i18n("Use at the request rate of the last 24 hours.")
            },
            "7d": {
                label: i18n("Last 7d"),
                short: i18n("7d"),
                desc: i18n("Use at the average request rate of the last 7 days.")
            }
        })

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground

    function load() {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            root.now = Date.now();
            const text = xhr.responseText;
            if (!text || text === root.lastText)
                return;
            root.lastText = text;
            try {
                const next = JSON.parse(text);
                root.fetched = next.updated || 0;
                // On an error the fetch writes only the error, so the last data stays.
                root.d = next.pool ? next : Object.assign({}, root.d, {
                    error: next.error,
                    panelTheme: next.panelTheme
                });
            } catch (err) {
                root.d = Object.assign({}, root.d, {
                    error: String(err)
                });
            }
        };
        xhr.open("GET", dataFile);
        xhr.send();
    }

    function toggleProj(p) {
        const on = shownProjs.indexOf(p) >= 0;
        if (on && shownProjs.length === 1)
            return;
        shownProjs = TL.PROJS.filter(x => x === p ? !on : shownProjs.indexOf(x) >= 0);
    }

    // 45 s, 12 min, 3 h 5 min.
    function dur(s) {
        if (s === null || s === undefined)
            return "–";
        s = Math.round(s);
        if (s < 60)
            return i18n("%1 s", s);
        const mins = Math.round(s / 60);
        if (mins < 60)
            return i18n("%1 min", mins);
        const h = Math.floor(mins / 60), rest = mins % 60;
        return rest ? i18n("%1 h %2 min", h, rest) : i18n("%1 h", h);
    }

    // "in 5 h" or "in 2 d 3 h" from now.
    function until(t) {
        const h = Math.max(0, (t - now) / 3600000);
        if (h < 1)
            return i18n("in %1 min", Math.round(h * 60));
        if (h < 24)
            return i18n("in %1 h", Math.round(h));
        const days = Math.floor(h / 24), rest = Math.round(h % 24);
        return rest ? i18n("in %1 d %2 h", days, rest) : i18n("in %1 d", days);
    }

    // "Sat 18:10" in local time.
    function when(t) {
        return Qt.formatDateTime(new Date(t), "ddd HH:mm");
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.load()
    }

    // The theme picked with os-theme. "plasma" (no colours) keeps the Plasma colours.
    readonly property var pt: d.panelTheme || ({})
    readonly property bool themed: pt.window !== undefined
    readonly property color cardColor: themed ? pt.card : Kirigami.Theme.backgroundColor
    readonly property color inkColor: themed ? pt.text : Kirigami.Theme.textColor

    // Type scale, shared with the Agenda and the Build Queue.
    readonly property real fs: Kirigami.Theme.defaultFont.pointSize * 1.08
    readonly property real fsSmall: Kirigami.Theme.smallFont.pointSize

    function muted(c) {
        if (themed && !pt.mute)
            return c;
        return Qt.hsla(c.hslHue, c.hslSaturation * 0.78, Math.min(c.hslLightness, 0.6), 1);
    }

    function tint(amount) {
        return Kirigami.ColorUtils.tintWithAlpha(cardColor, inkColor, amount);
    }

    component Small: PlasmaComponents.Label {
        font.pointSize: root.fsSmall
        opacity: 0.62
    }

    component Dot: Rectangle {
        implicitWidth: Kirigami.Units.smallSpacing * 2
        implicitHeight: implicitWidth
        radius: width / 2
    }

    fullRepresentation: Rectangle {
        id: view

        readonly property var projColor: ({
                optimistic: root.muted(Kirigami.Theme.positiveTextColor),
                current: root.muted(Kirigami.Theme.negativeTextColor),
                "24h": root.muted(Kirigami.Theme.neutralTextColor),
                "7d": root.muted(Kirigami.Theme.linkColor)
            })
        readonly property color alertColor: root.muted(Kirigami.Theme.negativeTextColor)
        readonly property color nowColor: Kirigami.Theme.highlightColor
        readonly property color okColor: root.muted(Kirigami.Theme.positiveTextColor)

        Layout.minimumWidth: Kirigami.Units.gridUnit * 24
        Layout.minimumHeight: Kirigami.Units.gridUnit * 10
        Layout.preferredWidth: Kirigami.Units.gridUnit * 44
        Layout.preferredHeight: Kirigami.Units.gridUnit * 16

        Kirigami.Theme.inherit: !root.themed
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.backgroundColor: root.themed ? root.pt.card : undefined
        Kirigami.Theme.alternateBackgroundColor: root.themed ? root.pt.band : undefined
        Kirigami.Theme.textColor: root.themed ? root.pt.text : undefined
        Kirigami.Theme.disabledTextColor: root.themed ? root.pt.muted : undefined
        Kirigami.Theme.negativeTextColor: root.themed ? root.pt.negative : undefined
        Kirigami.Theme.neutralTextColor: root.themed ? root.pt.warning : undefined
        Kirigami.Theme.positiveTextColor: root.themed ? root.pt.positive : undefined
        Kirigami.Theme.highlightColor: root.themed ? root.pt.accent : undefined
        Kirigami.Theme.linkColor: root.themed ? root.pt.info : undefined
        Kirigami.Theme.highlightedTextColor: root.themed ? root.pt.onAccent : undefined
        // The window sits a step darker than the card, so the card lifts off it.
        color: root.themed ? root.pt.window : Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, "black", 0.18)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing * 1.25
            spacing: Kirigami.Units.largeSpacing

            // Header: title, free capacity now, when it drops below 20%, and how fresh the data is.
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing * 1.5
                PlasmaComponents.Label {
                    text: i18n("Aiolos Timeline")
                    font.pointSize: root.fs * 1.4
                    font.weight: Font.Bold
                }
                Small {
                    text: i18n("Claude pool, next 7 days")
                    Layout.alignment: Qt.AlignBaseline
                }
                Item {
                    Layout.preferredWidth: Kirigami.Units.largeSpacing
                }
                PlasmaComponents.Label {
                    visible: !isNaN(root.freeNow)
                    text: i18n("%1% free now", Math.round(root.freeNow))
                    font.pointSize: root.fs
                    font.weight: Font.DemiBold
                    color: root.freeNow < 20 ? view.alertColor : Kirigami.Theme.textColor
                    HoverHandler {
                        id: freeHover
                    }
                    PlasmaComponents.ToolTip.visible: freeHover.hovered
                    PlasmaComponents.ToolTip.text: i18n("Share of the pool's capacity (each account weighted by its plan size) that is not used up in its fullest window.")
                    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
                Item {
                    Layout.fillWidth: true
                }
                Small {
                    visible: root.d.updated > 0
                    text: root.stale ? i18n("No update for %1", root.dur((root.now - root.fetched) / 1000)) : i18n("Updated %1 ago", root.dur(Math.max(0, root.now - root.d.updated) / 1000))
                }
                Dot {
                    visible: root.d.updated > 0
                    color: root.stale || root.problem !== "" ? Kirigami.Theme.neutralTextColor : view.okColor
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
                    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }

            // The chart card.
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: root.tint(0.045)
                border.color: root.tint(0.11)
                radius: 6

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing * 2.5
                    spacing: Kirigami.Units.smallSpacing

                    // Line toggles and what is counted.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        Repeater {
                            model: TL.PROJS
                            PlasmaComponents.ToolButton {
                                required property string modelData
                                readonly property bool on: root.shownProjs.indexOf(modelData) >= 0
                                text: root.projMeta[modelData].label
                                font.pointSize: root.fsSmall
                                checkable: true
                                checked: on
                                opacity: on ? 1 : 0.55
                                leftPadding: Kirigami.Units.smallSpacing * 2 + Kirigami.Units.gridUnit
                                onClicked: root.toggleProj(modelData)
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: Kirigami.Units.smallSpacing * 1.5
                                    width: Kirigami.Units.gridUnit * 0.8
                                    height: 2
                                    color: view.projColor[parent.modelData]
                                }
                                PlasmaComponents.ToolTip.visible: hovered
                                PlasmaComponents.ToolTip.text: root.projMeta[modelData].desc + (on && root.shownProjs.length === 1 ? "\n" + i18n("Show another line to hide this one.") : "")
                                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        // One phrase per shown line: when it drops below 20%, or that it stays above.
                        Repeater {
                            model: root.alerts
                            RowLayout {
                                required property var modelData
                                spacing: Kirigami.Units.smallSpacing
                                Dot {
                                    color: view.projColor[modelData.proj]
                                }
                                PlasmaComponents.Label {
                                    font.pointSize: root.fsSmall
                                    text: modelData.t === null ? i18n("%1: stays above 20%", root.projMeta[modelData.proj].short)
                                        : modelData.t <= root.m.now ? i18n("%1: below 20% now", root.projMeta[modelData.proj].short)
                                        : i18n("%1: below 20% %2, %3", root.projMeta[modelData.proj].short, root.until(modelData.t), root.when(modelData.t))
                                    color: modelData.t !== null && modelData.t - root.now < 12 * 3600000 ? view.alertColor : Kirigami.Theme.textColor
                                }
                            }
                        }
                        PlasmaComponents.ToolButton {
                            id: countButton
                            icon.name: "configure"
                            display: PlasmaComponents.AbstractButton.IconOnly
                            text: i18n("What is counted")
                            implicitWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                            implicitHeight: implicitWidth
                            onClicked: countMenu.open()
                            PlasmaComponents.ToolTip.visible: hovered && !countMenu.visible
                            PlasmaComponents.ToolTip.text: i18n("Counting %1 of %2", root.mode === "all" ? i18n("all windows") : i18n("5-hour and Weekly windows"), root.accts === "all" ? i18n("all accounts that are not paused") : i18n("routable accounts"))
                            PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                            PlasmaComponents.Menu {
                                id: countMenu
                                y: countButton.height
                                PlasmaComponents.MenuItem {
                                    text: i18n("All windows, with the model weekly caps")
                                    checkable: true
                                    checked: root.mode === "all"
                                    onTriggered: root.mode = "all"
                                }
                                PlasmaComponents.MenuItem {
                                    text: i18n("Only 5-hour and Weekly, the windows that gate routing")
                                    checkable: true
                                    checked: root.mode === "routable"
                                    onTriggered: root.mode = "routable"
                                }
                                PlasmaComponents.MenuSeparator {}
                                PlasmaComponents.MenuItem {
                                    text: i18n("All accounts that are not paused")
                                    checkable: true
                                    checked: root.accts === "all"
                                    onTriggered: root.accts = "all"
                                }
                                PlasmaComponents.MenuItem {
                                    text: i18n("Only accounts that are routable now")
                                    checkable: true
                                    checked: root.accts === "routable"
                                    onTriggered: root.accts = "routable"
                                }
                            }
                        }
                    }

                    Item {
                        id: plotArea
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        // Plot box inside the canvas, in pixels.
                        readonly property real pL: Kirigami.Units.gridUnit * 2
                        readonly property real pR: Kirigami.Units.smallSpacing * 2
                        readonly property real pT: Kirigami.Units.smallSpacing * 2
                        readonly property real pB: Kirigami.Units.gridUnit * 1.2
                        readonly property real pW: Math.max(1, width - pL - pR)
                        readonly property real pH: Math.max(1, height - pT - pB)

                        function tx(t) {
                            return pL + (t - root.m.now) / (root.m.end - root.m.now) * pW;
                        }
                        function ty(pct) {
                            return pT + pH - pct / 100 * pH;
                        }
                        function tAt(x) {
                            return root.m.now + Math.max(0, Math.min(1, (x - pL) / pW)) * (root.m.end - root.m.now);
                        }

                        Canvas {
                            id: canvas
                            anchors.fill: parent
                            renderStrategy: Canvas.Cooperative

                            // Repaint on new data, a new setting, a theme change or a resize.
                            property var deps: [root.lines, root.shownProjs, view.projColor, root.inkColor, width, height]
                            onDepsChanged: requestPaint()

                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                const m = root.m;
                                if (!m || m.maxNx <= 0)
                                    return;
                                const a = plotArea, ink = root.inkColor.toString();
                                const fontPx = Math.round(Kirigami.Theme.smallFont.pixelSize || 11);
                                ctx.font = fontPx + "px sans-serif";
                                ctx.lineWidth = 1;

                                // Grid and y labels.
                                ctx.textAlign = "right";
                                ctx.textBaseline = "middle";
                                for (const p of [0, 25, 50, 75, 100]) {
                                    const y = Math.round(a.ty(p)) + 0.5;
                                    ctx.globalAlpha = 0.13;
                                    ctx.strokeStyle = ink;
                                    ctx.beginPath();
                                    ctx.moveTo(a.pL, y);
                                    ctx.lineTo(a.pL + a.pW, y);
                                    ctx.stroke();
                                    ctx.globalAlpha = 0.55;
                                    ctx.fillStyle = ink;
                                    ctx.fillText(p + "%", a.pL - 4, y);
                                }

                                // Local midnights, with the weekday in the middle of each day.
                                ctx.textAlign = "center";
                                ctx.textBaseline = "top";
                                const day = new Date(m.now);
                                day.setHours(24, 0, 0, 0);
                                let prev = m.now;
                                for (let t = day.getTime(); t <= m.end + TL.DAY; t += TL.DAY) {
                                    const edge = Math.min(t, m.end);
                                    const mid = (prev + edge) / 2;
                                    if (edge - prev > 4 * TL.HOUR) {
                                        ctx.globalAlpha = 0.55;
                                        ctx.fillStyle = ink;
                                        ctx.fillText(Qt.formatDateTime(new Date(mid), "ddd d"), a.tx(mid), a.pT + a.pH + 4);
                                    }
                                    if (t < m.end) {
                                        const x = Math.round(a.tx(t)) + 0.5;
                                        ctx.globalAlpha = 0.13;
                                        ctx.strokeStyle = ink;
                                        ctx.setLineDash([2, 3]);
                                        ctx.beginPath();
                                        ctx.moveTo(x, a.pT);
                                        ctx.lineTo(x, a.pT + a.pH);
                                        ctx.stroke();
                                        ctx.setLineDash([]);
                                    }
                                    prev = t;
                                    if (t >= m.end)
                                        break;
                                }

                                // The 20% alert line.
                                const y20 = Math.round(a.ty(20)) + 0.5;
                                ctx.globalAlpha = 0.6;
                                ctx.strokeStyle = view.alertColor.toString();
                                ctx.setLineDash([4, 4]);
                                ctx.beginPath();
                                ctx.moveTo(a.pL, y20);
                                ctx.lineTo(a.pL + a.pW, y20);
                                ctx.stroke();
                                ctx.setLineDash([]);
                                ctx.textAlign = "right";
                                ctx.textBaseline = "bottom";
                                ctx.fillStyle = view.alertColor.toString();
                                ctx.fillText(i18n("20% alert"), a.pL + a.pW - 2, y20 - 2);

                                const shown = TL.PROJS.filter(p => root.shownProjs.indexOf(p) >= 0);
                                function trace(pts) {
                                    ctx.moveTo(a.tx(pts[0].t), a.ty(pts[0].pct));
                                    for (let i = 1; i < pts.length; i++) {
                                        ctx.lineTo(a.tx(pts[i].t), a.ty(pts[i - 1].pct));
                                        ctx.lineTo(a.tx(pts[i].t), a.ty(pts[i].pct));
                                    }
                                }
                                // A filled area when only one line shows, as on the dashboard.
                                if (shown.length === 1) {
                                    const pts = root.lines[shown[0]];
                                    ctx.globalAlpha = 0.14;
                                    ctx.fillStyle = view.projColor[shown[0]].toString();
                                    ctx.beginPath();
                                    trace(pts);
                                    ctx.lineTo(a.tx(m.end), a.ty(0));
                                    ctx.lineTo(a.tx(m.now), a.ty(0));
                                    ctx.closePath();
                                    ctx.fill();
                                }
                                ctx.globalAlpha = 1;
                                ctx.lineWidth = 2;
                                ctx.lineJoin = "round";
                                for (const p of shown) {
                                    ctx.strokeStyle = view.projColor[p].toString();
                                    ctx.beginPath();
                                    trace(root.lines[p]);
                                    ctx.stroke();
                                }

                                // Now.
                                ctx.lineWidth = 1.5;
                                ctx.strokeStyle = view.nowColor.toString();
                                const xn = Math.round(a.tx(m.now)) + 0.5;
                                ctx.beginPath();
                                ctx.moveTo(xn, a.pT);
                                ctx.lineTo(xn, a.pT + a.pH);
                                ctx.stroke();
                            }
                        }

                        // Hover: a hairline, each shown line's value and the resets near it.
                        HoverHandler {
                            id: plotHover
                        }
                        readonly property bool hovering: plotHover.hovered && root.m !== null && root.m.maxNx > 0 && plotHover.point.position.x >= pL
                        readonly property real hoverT: hovering ? tAt(plotHover.point.position.x) : 0

                        Rectangle {
                            visible: plotArea.hovering
                            x: plotArea.hovering ? Math.round(plotArea.tx(plotArea.hoverT)) : 0
                            y: plotArea.pT
                            width: 1
                            height: plotArea.pH
                            color: root.inkColor
                            opacity: 0.45
                        }

                        Rectangle {
                            id: tip
                            visible: plotArea.hovering
                            readonly property real hx: plotArea.hovering ? plotArea.tx(plotArea.hoverT) : 0
                            x: hx + width + Kirigami.Units.largeSpacing * 2 < plotArea.width ? hx + Kirigami.Units.largeSpacing : hx - width - Kirigami.Units.largeSpacing
                            y: plotArea.pT + Kirigami.Units.smallSpacing
                            width: tipCol.implicitWidth + Kirigami.Units.smallSpacing * 4
                            height: tipCol.implicitHeight + Kirigami.Units.smallSpacing * 3
                            radius: 4
                            color: root.cardColor
                            border.color: root.tint(0.2)

                            readonly property var resets: plotArea.hovering ? TL.resetsNear(root.m, plotArea.hoverT, (root.m.end - root.m.now) / plotArea.pW * Kirigami.Units.gridUnit * 0.4) : []

                            ColumnLayout {
                                id: tipCol
                                anchors.centerIn: parent
                                spacing: Kirigami.Units.smallSpacing / 2
                                PlasmaComponents.Label {
                                    text: plotArea.hovering ? Qt.formatDateTime(new Date(plotArea.hoverT), "ddd d MMM HH:mm") + "  ·  " + root.until(plotArea.hoverT) : ""
                                    font.pointSize: root.fsSmall
                                    font.weight: Font.DemiBold
                                }
                                Repeater {
                                    model: plotArea.hovering ? TL.PROJS.filter(p => root.shownProjs.indexOf(p) >= 0) : []
                                    RowLayout {
                                        required property string modelData
                                        spacing: Kirigami.Units.smallSpacing
                                        Dot {
                                            color: view.projColor[modelData]
                                        }
                                        PlasmaComponents.Label {
                                            text: i18n("%1: %2% free", root.projMeta[modelData].label, Math.round(TL.valueAt(root.m, modelData, plotArea.hoverT)))
                                            font.pointSize: root.fsSmall
                                        }
                                    }
                                }
                                Repeater {
                                    model: tip.resets.slice(0, 4)
                                    Small {
                                        required property var modelData
                                        text: i18n("%1 resets: %2 %3", root.when(modelData.ms), modelData.name.replace(/@.*/, ""), modelData.label)
                                    }
                                }
                                Small {
                                    visible: tip.resets.length > 4
                                    text: i18n("and %1 more resets", tip.resets.length - 4)
                                }
                            }
                        }

                        PlasmaComponents.Label {
                            anchors.centerIn: parent
                            visible: root.m === null || root.m.maxNx <= 0
                            text: root.m === null ? (root.problem || i18n("Waiting for data from aiolos")) : i18n("No accounts to count")
                            opacity: 0.62
                            wrapMode: Text.WordWrap
                            width: Math.min(implicitWidth, parent.width - Kirigami.Units.gridUnit * 2)
                        }
                    }
                }
            }
        }
    }
}
