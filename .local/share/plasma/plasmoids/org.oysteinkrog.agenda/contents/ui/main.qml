// Agenda: today and the coming days from Google Calendar, plus open Google Tasks.
// Data comes from ~/bin/agenda-fetch (gog), run every two minutes. Colours and fonts come
// from the Plasma style, so the window matches the panels.
// Run as a window with: plasmawindowed org.oysteinkrog.agenda

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

    readonly property string fetchCommand: "$HOME/bin/agenda-fetch"
    property var agenda: ({
            updated: 0,
            error: "",
            events: [],
            tasks: []
        })
    property double now: Date.now()
    property bool fetching: false

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground

    function fetch() {
        if (fetching)
            return;
        fetching = true;
        exec.connectSource(fetchCommand);
    }

    function dayStart(ms) {
        const d = new Date(ms);
        d.setHours(0, 0, 0, 0);
        return d.getTime();
    }

    function dayLabel(start) {
        const days = Math.round((dayStart(start) - dayStart(now)) / 86400000);
        if (days === 0)
            return i18n("Today");
        if (days === 1)
            return i18n("Tomorrow");
        return Qt.formatDate(new Date(start), "dddd d MMMM");
    }

    function timeText(e) {
        if (e.allDay)
            return i18n("All day");
        return Qt.formatTime(new Date(e.start), "HH:mm") + "–" + Qt.formatTime(new Date(e.end), "HH:mm");
    }

    // "out until Tue 3 Nov", "home", "out 08:00–12:00", "works 08:00–14:00".
    function awayText(p) {
        if (p.source === "slack") {
            const text = p.title.toLowerCase();
            if (!p.end)
                return i18n("%1 (Slack, no end set)", text);
            if (p.end - now < 86400000 && dayStart(p.end) === dayStart(now))
                return i18n("%1 (Slack)", text);
            return i18n("%1 until %2 (Slack)", text, Qt.formatDate(new Date(p.end), "ddd d MMM"));
        }
        const what = p.kind === "hours" ? i18n("works") : p.kind === "home" ? i18n("home") : i18n("out");
        if (!p.allDay)
            return what + " " + Qt.formatTime(new Date(p.start), "HH:mm") + "–" + Qt.formatTime(new Date(p.end), "HH:mm");
        const lastDay = dayStart(p.end - 1);
        if (lastDay <= dayStart(now))
            return what;
        return i18n("%1 until %2", what, Qt.formatDate(new Date(lastDay), "ddd d MMM"));
    }

    function untilText(ms) {
        const min = Math.round((ms - now) / 60000);
        if (min < 60)
            return i18n("in %1 min", min);
        const h = Math.floor(min / 60), m = min % 60;
        return m ? i18n("in %1 h %2 min", h, m) : i18n("in %1 h", h);
    }

    // The next timed event that has not started yet, today or later.
    readonly property double nextStart: {
        const e = agenda.events.find(e => !e.allDay && e.start > now);
        return e ? e.start : 0;
    }

    function rebuild() {
        eventModel.clear();
        const todayStart = dayStart(now);
        for (const e of agenda.events) {
            if (e.end <= todayStart)
                continue;
            const start = Math.max(e.start, todayStart);
            eventModel.append(Object.assign({}, e, {
                day: dayLabel(start),
                dayKey: dayStart(start)
            }));
        }
    }

    onAgendaChanged: rebuild()

    ListModel {
        id: eventModel
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source);
            root.fetching = false;
            try {
                root.agenda = JSON.parse(data.stdout);
            } catch (err) {
                root.agenda = Object.assign({}, root.agenda, {
                    error: data.stderr || String(err)
                });
            }
        }
    }

    Timer {
        interval: 120000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.fetch()
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            const before = root.dayStart(root.now);
            root.now = Date.now();
            if (root.dayStart(root.now) !== before)
                root.rebuild();
        }
    }

    // Plasma style (panel) colours from agenda-fetch. Empty until the first fetch, and then
    // the app colour scheme is used.
    readonly property var style: agenda.theme || ({})
    readonly property bool styled: style.background !== undefined
    // The style's accent is often too dark for text on its own background, so text uses a
    // lighter tint of it.
    readonly property color accentText: Kirigami.ColorUtils.tintWithAlpha(styled ? style.accent : Kirigami.Theme.highlightColor, "white", 0.35)

    fullRepresentation: Rectangle {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 20
        Layout.preferredWidth: Kirigami.Units.gridUnit * 26
        Layout.preferredHeight: Kirigami.Units.gridUnit * 40

        Kirigami.Theme.inherit: !root.styled
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.backgroundColor: root.styled ? root.style.background : undefined
        Kirigami.Theme.alternateBackgroundColor: root.styled ? root.style.alternate : undefined
        Kirigami.Theme.textColor: root.styled ? root.style.text : undefined
        Kirigami.Theme.disabledTextColor: root.styled ? root.style.inactive : undefined
        Kirigami.Theme.negativeTextColor: root.styled ? root.style.negative : undefined
        Kirigami.Theme.highlightColor: root.styled ? root.style.accent : undefined
        Kirigami.Theme.highlightedTextColor: root.styled ? root.style.accentText : undefined
        Kirigami.Theme.hoverColor: root.styled ? root.style.accent : undefined
        Kirigami.Theme.focusColor: root.styled ? root.style.accent : undefined
        color: Kirigami.Theme.backgroundColor

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            // Header: today's date, and when the data was last read.
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.largeSpacing

                ColumnLayout {
                    spacing: 0
                    PlasmaExtras.Heading {
                        level: 1
                        text: Qt.formatDate(new Date(root.now), "dddd")
                    }
                    PlasmaComponents.Label {
                        text: Qt.formatDate(new Date(root.now), "d MMMM yyyy") + "  ·  " + i18n("week %1", weekNumber(new Date(root.now)))
                        opacity: 0.7

                        function weekNumber(d) {
                            const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
                            t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
                            return Math.ceil(((t - new Date(Date.UTC(t.getUTCFullYear(), 0, 1))) / 86400000 + 1) / 7);
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                Kirigami.Icon {
                    visible: root.agenda.error !== ""
                    source: "data-warning"
                    implicitWidth: Kirigami.Units.iconSizes.small
                    implicitHeight: implicitWidth
                    PlasmaComponents.ToolTip {
                        text: root.agenda.error
                    }
                    HoverHandler {}
                }
                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    enabled: !root.fetching
                    onClicked: root.fetch()
                    PlasmaComponents.ToolTip {
                        text: root.agenda.updated ? i18n("Updated %1", Qt.formatTime(new Date(root.agenda.updated), "HH:mm")) : i18n("Not updated yet")
                    }
                }
            }

            // Who is out, working from home or on part-time hours today, as chips that
            // wrap across the width. Entries that have ended are left out; Slack statuses
            // without an end time (end 0) stay.
            ColumnLayout {
                id: awayList
                readonly property var people: (root.agenda.away || []).filter(p => p.end === 0 || p.end > root.now)
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.largeSpacing
                visible: people.length > 0
                spacing: Kirigami.Units.smallSpacing

                PlasmaExtras.Heading {
                    level: 4
                    text: i18n("Away today")
                    color: root.accentText
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: awayList.people
                        delegate: PlasmaComponents.ItemDelegate {
                            id: person
                            required property var modelData
                            readonly property color dot: modelData.kind === "out" ? Kirigami.Theme.negativeTextColor
                                : modelData.kind === "home" ? root.accentText
                                : Kirigami.Theme.disabledTextColor
                            topPadding: Kirigami.Units.smallSpacing
                            bottomPadding: Kirigami.Units.smallSpacing
                            leftPadding: Kirigami.Units.largeSpacing
                            rightPadding: Kirigami.Units.largeSpacing
                            enabled: true
                            onClicked: if (modelData.link) Qt.openUrlExternally(modelData.link)
                            background: Rectangle {
                                radius: height / 2
                                color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, person.dot, person.hovered ? 0.3 : 0.15)
                                border.width: 1
                                border.color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, person.dot, 0.5)
                            }
                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                PlasmaComponents.Label {
                                    text: person.modelData.name
                                    font.bold: true
                                }
                                PlasmaComponents.Label {
                                    text: root.awayText(person.modelData)
                                    opacity: 0.8
                                }
                            }
                            PlasmaComponents.ToolTip {
                                text: person.modelData.source === "slack"
                                    ? i18n("Slack status: %1", person.modelData.title) + (person.modelData.end ? "" : "\n" + i18n("No end time set in Slack"))
                                    : person.modelData.title
                            }
                        }
                    }
                }
            }

            PlasmaComponents.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: list
                    model: eventModel
                    clip: true
                    spacing: Kirigami.Units.smallSpacing
                    reuseItems: true

                    section.property: "dayKey"
                    section.delegate: PlasmaExtras.Heading {
                        required property string section
                        width: ListView.view.width
                        level: 4
                        topPadding: Kirigami.Units.largeSpacing
                        bottomPadding: Kirigami.Units.smallSpacing
                        leftPadding: Kirigami.Units.largeSpacing
                        text: root.dayLabel(Number(section))
                        color: root.accentText
                    }

                    delegate: EventDelegate {
                        width: ListView.view.width
                        now: root.now
                        isNext: !model.allDay && model.start === root.nextStart
                        untilText: isNext ? root.untilText(model.start) : ""
                        timeText: root.timeText(model)
                    accentText: root.accentText
                    }

                    PlasmaExtras.PlaceholderMessage {
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.gridUnit * 4
                        visible: list.count === 0
                        iconName: "view-calendar-agenda"
                        text: root.fetching || !root.agenda.updated ? i18n("Loading…") : i18n("Nothing planned")
                    }
                }
            }

            // Open Google Tasks, overdue first.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.largeSpacing
                Layout.bottomMargin: Kirigami.Units.largeSpacing
                visible: root.agenda.tasks.length > 0
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Separator {
                    Layout.fillWidth: true
                }

                PlasmaExtras.Heading {
                    level: 4
                    text: i18n("Tasks")
                    color: root.accentText
                }

                Repeater {
                    model: root.agenda.tasks
                    delegate: PlasmaComponents.ItemDelegate {
                        id: task
                        required property var modelData
                        readonly property bool overdue: modelData.due !== "" && new Date(modelData.due + "T23:59:59").getTime() < root.now
                        Layout.fillWidth: true
                        onClicked: Qt.openUrlExternally(modelData.link)
                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon {
                                source: "checkbox"
                                implicitWidth: Kirigami.Units.iconSizes.small
                                implicitHeight: implicitWidth
                            }
                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                text: task.modelData.title
                                elide: Text.ElideRight
                            }
                            PlasmaComponents.Label {
                                visible: task.modelData.due !== ""
                                text: {
                                    const d = new Date(task.modelData.due + "T12:00:00");
                                    return Qt.formatDate(d, d.getFullYear() === new Date(root.now).getFullYear() ? "d MMM" : "d MMM yyyy");
                                }
                                color: task.overdue ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                                opacity: task.overdue ? 1 : 0.7
                            }
                        }
                    }
                }
            }
        }
    }
}
