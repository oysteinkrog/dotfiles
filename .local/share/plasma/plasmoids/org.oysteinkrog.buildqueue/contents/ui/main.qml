// Build Queue: the heavy-build queue at a glance. What runs, what waits and why, how fast
// the queue moves, which projects wait, and the memory signals that gate it.
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
            causes: [],
            prios: {}
        })
    readonly property var velocity: q.velocity || ({
            finished: {}
        })
    readonly property var projects: q.projects || []
    readonly property var machine: q.machine || ({})

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

    function gib(bytes) {
        return (bytes / 1073741824).toFixed(1);
    }

    function pct(v) {
        return v === null || v === undefined ? "–" : v.toFixed(1);
    }

    readonly property string trendText: {
        const t = velocity.trend;
        if (t === null || t === undefined)
            return i18n("trend after %1 min", velocity.trendMinutes || 15);
        if (t > 0)
            return i18n("growing: %1 more than %2 min ago", t, velocity.trendMinutes);
        if (t < 0)
            return i18n("shrinking: %1 fewer than %2 min ago", -t, velocity.trendMinutes);
        return i18n("steady over %1 min", velocity.trendMinutes);
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

    component Heading: PlasmaExtras.Heading {
        level: 4
        color: root.accentText
        Layout.topMargin: Kirigami.Units.smallSpacing
    }

    component Stat: ColumnLayout {
        property alias value: v.text
        property alias label: l.text
        property alias valueColor: v.color
        spacing: 0
        Layout.fillWidth: true
        PlasmaExtras.Heading {
            id: v
            level: 1
        }
        PlasmaComponents.Label {
            id: l
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }
    }

    component Dim: PlasmaComponents.Label {
        opacity: 0.7
    }

    fullRepresentation: Rectangle {
        id: view

        // Colours are worked out here, not on root, so they come from the Plasma style.
        readonly property color levelColor: root.machine.level === "pause" ? Kirigami.Theme.negativeTextColor
            : root.machine.level === "slow" ? Kirigami.Theme.neutralTextColor
            : Kirigami.Theme.positiveTextColor
        readonly property color trendColor: (root.velocity.trend || 0) > 0 ? Kirigami.Theme.negativeTextColor
            : (root.velocity.trend || 0) < 0 ? Kirigami.Theme.positiveTextColor
            : Kirigami.Theme.textColor

        function prioColor(p) {
            if (p === "critical")
                return Kirigami.Theme.negativeTextColor;
            if (p === "high")
                return Kirigami.Theme.neutralTextColor;
            return Kirigami.Theme.disabledTextColor;
        }

        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        Layout.minimumHeight: Kirigami.Units.gridUnit * 24
        Layout.preferredWidth: Kirigami.Units.gridUnit * 28
        Layout.preferredHeight: Kirigami.Units.gridUnit * 50

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

            // Header: the pressure level, and when the data was last read.
            RowLayout {
                Layout.fillWidth: true
                PlasmaExtras.Heading {
                    level: 1
                    text: i18n("Build queue")
                }
                Item {
                    Layout.fillWidth: true
                }
                Rectangle {
                    implicitWidth: levelLabel.implicitWidth + Kirigami.Units.largeSpacing * 2
                    implicitHeight: levelLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
                    radius: height / 2
                    color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, view.levelColor, 0.2)
                    border.width: 1
                    border.color: view.levelColor
                    PlasmaComponents.Label {
                        id: levelLabel
                        anchors.centerIn: parent
                        text: i18n("pressure %1", root.machine.level || "?")
                        color: view.levelColor
                        font.bold: true
                    }
                    HoverHandler {
                        id: levelHover
                    }
                    PlasmaComponents.ToolTip.visible: levelHover.hovered
                    PlasmaComponents.ToolTip.text: root.machine.levelReason || ""
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
            Dim {
                Layout.fillWidth: true
                visible: !!root.machine.level && root.machine.level !== "normal"
                text: i18n("%1 since %2", root.machine.levelReason || "", Qt.formatTime(new Date(root.machine.levelSince * 1000), "HH:mm"))
                wrapMode: Text.Wrap
                color: view.levelColor
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: root.problem !== ""
                text: root.problem
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.Wrap
            }

            // The three numbers that matter most.
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
                Stat {
                    value: root.running.length
                    label: i18n("running")
                }
                Stat {
                    value: root.waiting.count
                    label: i18n("waiting, %1 GiB est.", root.waiting.memGib || 0)
                    valueColor: root.waiting.count > 0 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                }
                Stat {
                    value: root.waiting.count > 0 ? root.dur(root.waiting.oldest) : "–"
                    label: i18n("oldest wait")
                }
            }

            // Velocity over the last hour.
            Heading {
                text: i18n("Last hour")
            }
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: 0

                Dim {
                    text: i18n("Finished")
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    textFormat: Text.StyledText
                    text: {
                        const f = root.velocity.finished || {};
                        const parts = [];
                        parts.push("<b>" + (f.ok || 0) + "</b> " + i18n("ok"));
                        parts.push("<font color='" + Kirigami.Theme.negativeTextColor + "'><b>" + (f.fail || 0) + "</b> " + i18n("failed") + "</font>");
                        const other = Object.keys(f).filter(k => k !== "ok" && k !== "fail");
                        for (const k of other)
                            parts.push("<b>" + f[k] + "</b> " + k);
                        return parts.join(",  ");
                    }
                }
                Dim {
                    text: i18n("Started")
                }
                PlasmaComponents.Label {
                    text: i18n("<b>%1</b>, while %2 arrived", root.velocity.started || 0, root.velocity.arrived || 0)
                    textFormat: Text.StyledText
                }
                Dim {
                    text: i18n("Queue wait")
                }
                PlasmaComponents.Label {
                    text: i18n("median <b>%1</b>, p90 <b>%2</b>", root.dur(root.velocity.waitMedian), root.dur(root.velocity.waitP90))
                    textFormat: Text.StyledText
                }
                Dim {
                    text: i18n("Queue")
                }
                PlasmaComponents.Label {
                    text: root.trendText
                    color: view.trendColor
                }
            }

            // Why jobs wait: the cause of each waiting job's last wait decision.
            Heading {
                visible: root.waiting.count > 0
                text: i18n("Why they wait")
            }
            Repeater {
                model: (root.waiting.causes || []).slice(0, 4)
                delegate: ColumnLayout {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 0
                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents.Label {
                            text: modelData.kind
                            font.bold: true
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            Layout.preferredWidth: Math.max(2, (parent.width - Kirigami.Units.gridUnit * 9) * modelData.count / Math.max(1, root.waiting.count))
                            implicitHeight: Kirigami.Units.smallSpacing * 2
                            radius: height / 2
                            color: root.accentText
                            opacity: 0.7
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        PlasmaComponents.Label {
                            text: modelData.count
                        }
                    }
                    Dim {
                        Layout.fillWidth: true
                        visible: index === 0 && modelData.example !== ""
                        text: modelData.example
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font: Kirigami.Theme.smallFont
                    }
                }
            }

            // Running builds, longest first.
            Heading {
                text: i18n("Running")
            }
            Repeater {
                model: root.running
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Rectangle {
                        implicitWidth: Kirigami.Units.smallSpacing
                        Layout.fillHeight: true
                        radius: width / 2
                        color: view.prioColor(modelData.prio)
                    }
                    PlasmaComponents.Label {
                        text: modelData.cls
                        font.bold: true
                    }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: modelData.project
                        elide: Text.ElideRight
                        opacity: 0.8
                        HoverHandler {
                            id: runHover
                        }
                        PlasmaComponents.ToolTip.visible: runHover.hovered && modelData.why !== ""
                        PlasmaComponents.ToolTip.text: modelData.why
                    }
                    Dim {
                        text: i18n("%1 GiB", root.gib(modelData.mem))
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

            // Per project: waiting now, started and finished in the last hour.
            Heading {
                text: i18n("Projects")
            }
            RowLayout {
                Layout.fillWidth: true
                Dim {
                    Layout.fillWidth: true
                    text: i18n("project")
                    font: Kirigami.Theme.smallFont
                }
                Repeater {
                    model: [i18n("waiting"), i18n("started"), i18n("done"), i18n("failed")]
                    delegate: Dim {
                        required property string modelData
                        text: modelData
                        font: Kirigami.Theme.smallFont
                        horizontalAlignment: Text.AlignRight
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5
                    }
                }
            }
            PlasmaComponents.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Kirigami.Units.gridUnit * 4

                ListView {
                    model: root.projects
                    clip: true
                    delegate: RowLayout {
                        required property var modelData
                        width: ListView.view.width
                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: modelData.name
                            elide: Text.ElideRight
                        }
                        Repeater {
                            model: [modelData.waiting, modelData.started, modelData.finished, modelData.failed]
                            delegate: PlasmaComponents.Label {
                                required property int modelData
                                required property int index
                                text: modelData || "·"
                                opacity: modelData ? 1 : 0.4
                                font.bold: index === 0 && modelData > 0
                                color: index === 3 && modelData > 0 ? Kirigami.Theme.negativeTextColor
                                    : index === 0 && modelData > 0 ? Kirigami.Theme.neutralTextColor
                                    : Kirigami.Theme.textColor
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5
                            }
                        }
                    }
                }
            }

            // Machine signals that gate the queue.
            Kirigami.Separator {
                Layout.fillWidth: true
            }
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: 0
                Dim {
                    text: i18n("Memory free")
                }
                PlasmaComponents.Label {
                    text: i18n("%1 of %2 GiB", root.gib(root.machine.memAvail || 0), root.gib(root.machine.memTotal || 0))
                    color: (root.machine.memAvail || 0) < 10 * 1073741824 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                }
                Dim {
                    text: i18n("Builds use")
                }
                PlasmaComponents.Label {
                    text: i18n("%1 GiB", root.gib(root.machine.slice || 0))
                }
                Dim {
                    text: i18n("Swap")
                }
                PlasmaComponents.Label {
                    text: i18n("%1 GiB used, %2 pages/s in", root.gib(root.machine.swapUsed || 0), root.machine.swapinPs === null || root.machine.swapinPs === undefined ? "–" : Math.round(root.machine.swapinPs))
                }
                Dim {
                    text: i18n("Memory stall")
                }
                PlasmaComponents.Label {
                    text: i18n("some %1%, full %2% (10 s)", root.pct(root.machine.psiSome10), root.pct(root.machine.psiFull10))
                }
            }
            Dim {
                Layout.fillWidth: true
                text: i18n("Limits: %1", root.q.limits || "?")
                font: Kirigami.Theme.smallFont
                wrapMode: Text.Wrap
            }
        }
    }
}
