// Agenda: the next meeting, today and the coming days from Google Calendar, who is away
// today, and open Google Tasks. Data comes from ~/bin/agenda-fetch (gog), run every
// minute so the away list stays current. Colours come from the theme picked with os-theme (shared with the Build Queue
// panel), or from the Plasma style when that theme is "plasma".
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
    // The picked theme name, a separator line, then the theme file (docs/desktop-panels-style.md).
    readonly property string themeCommand: "sh -c 'cat \"$HOME/.local/state/os-theme/current\" 2>/dev/null; echo; echo ---; cat \"$HOME/.config/os-theme/themes.json\" 2>/dev/null'"
    property string themeRaw: ""
    // {name, label, names: [[name, label], ...], and the colour tokens unless it is "plasma"}.
    property var panel: ({
            name: "plasma",
            names: []
        })
    property var agenda: ({
            updated: 0,
            error: "",
            events: [],
            tasks: []
        })
    property double now: Date.now()
    property bool fetching: false
    // Per day (keyed by the day's start): event count, booked minutes and busy segments.
    property var days: ({})

    // Type scale, shared with the Build Queue panel (docs/desktop-panels-style.md): a little
    // larger than the Plasma font, so the panel reads from a metre away.
    readonly property real textSize: Kirigami.Theme.defaultFont.pointSize * 1.08
    readonly property real smallSize: Kirigami.Theme.smallFont.pointSize
    // The busy strip covers the working day.
    readonly property int stripFrom: 8
    readonly property int stripTo: 18
    // Absences that end more than this many days from now are shown as long leave.
    readonly property int longLeaveDays: 30

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground

    function fetch() {
        if (fetching)
            return;
        fetching = true;
        exec.connectSource(fetchCommand);
    }

    function readTheme(raw) {
        if (raw === themeRaw)
            return;
        themeRaw = raw;
        const cut = raw.indexOf("\n---\n");
        const name = raw.slice(0, Math.max(cut, 0)).trim();
        let themes = {};
        try {
            themes = JSON.parse(raw.slice(cut + 5));
        } catch (err) {
            themes = {};
        }
        const t = themes[name] || {};
        panel = Object.assign({}, t, {
            name: themes[name] ? name : "plasma",
            names: Object.keys(themes).map(n => [n, themes[n].label || n])
        });
    }

    function setTheme(name) {
        if (/^[A-Za-z0-9_-]+$/.test(name))
            themeExec.connectSource("$HOME/bin/os-theme " + name);
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
        return Qt.formatDate(new Date(start), "dddd");
    }

    function timeText(e) {
        if (e.allDay)
            return i18n("All day");
        return Qt.formatTime(new Date(e.start), "HH:mm") + "–" + Qt.formatTime(new Date(e.end), "HH:mm");
    }

    function durationText(min) {
        const h = Math.floor(min / 60), m = min % 60;
        if (!h)
            return i18n("%1 min", m);
        return m ? i18n("%1 h %2 min", h, m) : i18n("%1 h", h);
    }

    // "until Tue 3 Nov", "home until 13:30", "out 08:00–12:00", "works 08:00–14:00". The
    // avatar colour says out or home. Slack statuses use their own text; the tooltip says it
    // came from Slack.
    function awayText(p) {
        if (p.source === "slack") {
            const text = p.title.toLowerCase();
            if (!p.end || dayStart(p.end) === dayStart(now))
                return text;
            return i18n("%1 until %2", text, Qt.formatDate(new Date(p.end), "ddd d MMM"));
        }
        const what = p.kind === "hours" ? i18n("works") : p.kind === "home" ? i18n("home") : i18n("out");
        if (!p.allDay)
            return what + " " + Qt.formatTime(new Date(p.start), "HH:mm") + "–" + Qt.formatTime(new Date(p.end), "HH:mm");
        const lastDay = dayStart(p.end - 1);
        if (lastDay <= dayStart(now))
            return what;
        const sameYear = new Date(lastDay).getFullYear() === new Date(now).getFullYear();
        const date = Qt.formatDate(new Date(lastDay), sameYear ? "ddd d MMM" : "d MMM yyyy");
        return p.kind === "out" ? i18n("until %1", date) : i18n("%1 until %2", what, date);
    }

    // For the top card: "in 25 min" today, otherwise the day ("Tomorrow", "Wednesday").
    function whenText(ms) {
        return dayStart(ms) === dayStart(now) ? untilText(ms) : dayLabel(ms);
    }

    // "Updated 1 min ago", in the same form as the Build Queue panel.
    readonly property string updatedText: {
        const min = Math.max(0, Math.round((now - agenda.updated) / 60000));
        return min < 1 ? i18n("Updated just now") : i18n("Updated %1 ago", durationText(min));
    }

    function untilText(ms) {
        const min = Math.round((ms - now) / 60000);
        return i18n("in %1", durationText(Math.max(min, 0)));
    }

    // The meeting for the top card: the one going on now, or else the next one to start.
    readonly property var focusEvent: {
        const timed = agenda.events.filter(e => !e.allDay && e.end > now);
        return timed.find(e => e.start <= now) || timed.find(e => e.start > now) || null;
    }
    readonly property bool focusIsNow: focusEvent !== null && focusEvent.start <= now
    readonly property double nextStart: {
        const e = agenda.events.find(e => !e.allDay && e.start > now);
        return e ? e.start : 0;
    }

    function sameEvent(a, b) {
        return a && b && a.start === b.start && a.end === b.end && a.title === b.title;
    }

    // Shorter meetings that start or end inside the top card's meeting.
    function overlapsFocus(e) {
        const f = focusEvent;
        return f !== null && !e.allDay && !sameEvent(e, f) && e.start < f.end && e.end > f.start;
    }
    readonly property var focusOverlaps: agenda.events.filter(e => overlapsFocus(e))

    function rebuild() {
        eventModel.clear();
        const todayStart = dayStart(now);
        const info = {};
        for (const e of agenda.events) {
            if (e.end <= todayStart)
                continue;
            const start = Math.max(e.start, todayStart);
            // A string key: Qt writes some numbers as "1.793142e+12" when it turns the
            // section value into text, and the lookup in days then misses that day.
            const key = String(dayStart(start));
            eventModel.append(Object.assign({}, e, {
                dayKey: key
            }));
            const d = info[key] || (info[key] = {
                    count: 0,
                    spans: []
                });
            d.count++;
            if (!e.allDay)
                d.spans.push([e.start, Math.min(e.end, key + 86400000)]);
        }
        // Booked time is the union of the day's timed events, so overlaps count once.
        for (const key in info) {
            const d = info[key];
            d.spans.sort((a, b) => a[0] - b[0]);
            const merged = [];
            for (const s of d.spans) {
                const last = merged[merged.length - 1];
                if (last && s[0] <= last[1])
                    last[1] = Math.max(last[1], s[1]);
                else
                    merged.push([s[0], s[1]]);
            }
            d.busy = merged;
            d.minutes = Math.round(merged.reduce((sum, s) => sum + s[1] - s[0], 0) / 60000);
        }
        days = info;
    }

    // The row the now line sits above: the first event today that has not started, when an
    // earlier event today has.
    readonly property int nowIndex: {
        now; eventModel.count;
        const todayStart = String(dayStart(now));
        let started = false;
        for (let i = 0; i < eventModel.count; i++) {
            const e = eventModel.get(i);
            if (e.dayKey !== todayStart)
                break;
            if (e.allDay)
                continue;
            if (e.start <= now)
                started = true;
            else
                return started ? i : -1;
        }
        return -1;
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

    P5Support.DataSource {
        id: themeExec
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source);
            if (source === root.themeCommand)
                root.readTheme(data.stdout);
            else
                connectSource(root.themeCommand);
        }
    }

    // A theme switch from either panel or the command line shows within a few seconds.
    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: themeExec.connectSource(root.themeCommand)
    }

    Timer {
        interval: 60000
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
    // A theme with its own colours. "plasma" has none and keeps the colours derived below.
    readonly property bool themed: panel.window !== undefined && !panel.mute
    // Surfaces are tinted from these, not from Kirigami.Theme: the root item does not see the
    // colours set on the window below.
    readonly property color baseBg: themed ? panel.card : styled ? style.background : Kirigami.Theme.backgroundColor
    readonly property color baseText: themed ? panel.text : styled ? style.text : Kirigami.Theme.textColor
    // The style's accent is often too dark for text on its own background, so text uses a
    // lighter tint of it. Themes pick their own.
    readonly property color accent: themed ? panel.accent : styled ? style.accent : Kirigami.Theme.highlightColor
    readonly property color accentText: themed ? panel.accent : Kirigami.ColorUtils.tintWithAlpha(accent, "white", 0.35)
    readonly property color textOnAccent: themed ? panel.onAccent : styled ? style.accentText : Kirigami.Theme.highlightedTextColor
    readonly property color titleColor: themed ? panel.title : accentText
    readonly property color windowColor: themed ? panel.window : Kirigami.ColorUtils.tintWithAlpha(baseBg, "black", 0.18)
    readonly property color cardColor: themed ? panel.card : tint(0.045)
    readonly property color borderColor: themed ? panel.border : tint(0.11)
    readonly property color bandColor: themed ? panel.band : tint(0.07)
    readonly property color lineColor: themed ? panel.line : tint(0.11)
    // Data colours are the Plasma ones, a little less saturated so they sit calmly on the
    // dark cards (the same rule as the Build Queue panel).
    function muted(c) {
        return Qt.hsla(c.hslHue, c.hslSaturation * 0.78, Math.min(c.hslLightness, 0.6), 1);
    }
    function tint(amount) {
        return Kirigami.ColorUtils.tintWithAlpha(baseBg, baseText, amount);
    }
    readonly property color busyColor: themed ? panel.positive : muted(Kirigami.Theme.positiveTextColor)
    readonly property color homeColor: themed ? panel.info : muted(Kirigami.Theme.linkColor)

    fullRepresentation: Rectangle {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 20
        Layout.preferredWidth: Kirigami.Units.gridUnit * 26
        Layout.preferredHeight: Kirigami.Units.gridUnit * 40

        Kirigami.Theme.inherit: !root.styled && !root.themed
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.backgroundColor: root.themed ? root.panel.card : root.styled ? root.style.background : undefined
        Kirigami.Theme.alternateBackgroundColor: root.themed ? root.panel.band : root.styled ? root.style.alternate : undefined
        Kirigami.Theme.textColor: root.themed ? root.panel.text : root.styled ? root.style.text : undefined
        Kirigami.Theme.disabledTextColor: root.themed ? root.panel.muted : root.styled ? root.style.inactive : undefined
        Kirigami.Theme.negativeTextColor: root.themed ? root.panel.negative : root.styled ? root.style.negative : undefined
        Kirigami.Theme.positiveTextColor: root.themed ? root.panel.positive : undefined
        Kirigami.Theme.neutralTextColor: root.themed ? root.panel.warning : undefined
        Kirigami.Theme.linkColor: root.themed ? root.panel.info : undefined
        Kirigami.Theme.highlightColor: root.themed ? root.panel.accent : root.styled ? root.style.accent : undefined
        Kirigami.Theme.highlightedTextColor: root.themed ? root.panel.onAccent : root.styled ? root.style.accentText : undefined
        Kirigami.Theme.hoverColor: root.themed ? root.panel.accent : root.styled ? root.style.accent : undefined
        Kirigami.Theme.focusColor: root.themed ? root.panel.accent : root.styled ? root.style.accent : undefined
        // The window sits a step darker than the cards, so the cards lift off it.
        color: root.windowColor

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing * 1.25
            spacing: Kirigami.Units.largeSpacing

            // Header: title, today's date and week, and when the data was last read.
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing * 1.5

                PlasmaComponents.Label {
                    text: i18n("Agenda")
                    font.pointSize: root.textSize * 1.4
                    font.weight: Font.Bold
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBaseline
                    text: Qt.formatDate(new Date(root.now), "ddd d MMM") + "  ·  " + i18n("week %1", weekNumber(new Date(root.now)))
                    font.pointSize: root.smallSize
                    opacity: 0.62

                    function weekNumber(d) {
                        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
                        t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
                        return Math.ceil(((t - new Date(Date.UTC(t.getUTCFullYear(), 0, 1))) / 86400000 + 1) / 7);
                    }
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
                PlasmaComponents.Label {
                    visible: root.agenda.updated > 0
                    text: root.updatedText
                    font.pointSize: root.smallSize
                    opacity: 0.62
                }
                Rectangle {
                    visible: root.agenda.updated > 0
                    implicitWidth: Kirigami.Units.smallSpacing * 2
                    implicitHeight: implicitWidth
                    radius: width / 2
                    color: root.agenda.error !== "" || root.now - root.agenda.updated > 600000 ? Kirigami.Theme.neutralTextColor : root.busyColor
                }
                PlasmaComponents.ToolButton {
                    id: themeButton
                    visible: root.panel.names.length > 0
                    icon.name: "color-management"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    text: i18n("Theme")
                    onClicked: themeMenu.open()
                    PlasmaComponents.ToolTip.visible: hovered && !themeMenu.visible
                    PlasmaComponents.ToolTip.text: i18n("Panel theme: %1", root.panel.label || root.panel.name)
                    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                    PlasmaComponents.Menu {
                        id: themeMenu
                        y: themeButton.height
                        Repeater {
                            model: root.panel.names
                            PlasmaComponents.MenuItem {
                                required property var modelData
                                text: modelData[1]
                                checkable: true
                                checked: modelData[0] === root.panel.name
                                onTriggered: root.setTheme(modelData[0])
                            }
                        }
                    }
                }
                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    enabled: !root.fetching
                    onClicked: root.fetch()
                    PlasmaComponents.ToolTip {
                        text: i18n("Read the calendar again")
                    }
                }
            }

            NextCard {
                Layout.fillWidth: true
                visible: root.focusEvent !== null
                event: root.focusEvent
                isNow: root.focusIsNow
                overlaps: root.focusOverlaps
                whenText: root.focusEvent === null ? "" : root.focusIsNow
                    ? i18n("ends %1", Qt.formatTime(new Date(root.focusEvent.end), "HH:mm"))
                    : root.whenText(root.focusEvent.start)
                accent: root.accent
                accentText: root.accentText
                textOnAccent: root.textOnAccent
                textSize: root.textSize
                cardColor: root.cardColor
                borderColor: root.borderColor
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 6
                color: root.cardColor
                border.width: 1
                border.color: root.borderColor
                clip: true

            PlasmaComponents.ScrollView {
                anchors.fill: parent
                anchors.margins: 1

                ListView {
                    id: list
                    model: eventModel
                    clip: true
                    reuseItems: true

                    section.property: "dayKey"
                    section.delegate: DayHeader {
                        required property string section
                        width: ListView.view.width
                        dayKey: Number(section)
                        label: root.dayLabel(dayKey)
                        info: root.days[section] || null
                        durationText: info ? root.durationText(info.minutes) : ""
                        stripFrom: root.stripFrom
                        stripTo: root.stripTo
                        busyColor: root.busyColor
                        accentText: root.accentText
                        textSize: root.textSize
                        smallSize: root.smallSize
                        background: root.bandColor
                        line: root.lineColor
                    }

                    delegate: EventDelegate {
                        width: ListView.view.width
                        now: root.now
                        isNext: !model.allDay && model.start === root.nextStart
                        isFocus: root.sameEvent(model, root.focusEvent)
                        overlapsFocus: root.overlapsFocus(model)
                        nowLineAbove: index === root.nowIndex
                        untilText: isNext ? root.untilText(model.start) : ""
                        timeText: root.timeText(model)
                        accent: root.accent
                        accentText: root.accentText
                        textSize: root.textSize
                        smallSize: root.smallSize
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
            }

            // Bottom: who is away today, and open Google Tasks beside it, on one card. Shown
            // from the data, not from the children's visible: children of a hidden card
            // always read as hidden, so the card would never show again.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: bottom.implicitHeight + Kirigami.Units.smallSpacing * 5
                visible: awayList.people.length > 0 || root.agenda.tasks.length > 0
                radius: 6
                color: root.cardColor
                border.width: 1
                border.color: root.borderColor

            RowLayout {
                id: bottom
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing * 2.5
                spacing: Kirigami.Units.largeSpacing * 2

                // Entries that have ended are left out; Slack statuses without an end time
                // (end 0) stay.
                ColumnLayout {
                    id: awayList
                    readonly property var people: (root.agenda.away || []).filter(p => p.end === 0 || p.end > root.now)
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    visible: people.length > 0
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        PlasmaComponents.Label {
                            text: i18n("Away today")
                            color: root.titleColor
                            font.pointSize: root.textSize
                            font.weight: Font.DemiBold
                        }
                        PlasmaComponents.Label {
                            text: i18np("1 person", "%1 people", awayList.people.length)
                            font.pointSize: root.smallSize
                            opacity: 0.5
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: Math.max(2, Math.floor(awayList.width / (Kirigami.Units.gridUnit * 8.5)))
                        columnSpacing: Kirigami.Units.largeSpacing
                        rowSpacing: Kirigami.Units.smallSpacing

                        Repeater {
                            model: awayList.people
                            delegate: AwayPerson {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                person: modelData
                                detail: root.awayText(modelData)
                                dot: modelData.kind === "out"
                                    ? (modelData.end - root.now > root.longLeaveDays * 86400000 ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.negativeTextColor)
                                    : modelData.kind === "home" ? root.homeColor
                                    : Kirigami.Theme.disabledTextColor
                                smallSize: root.smallSize
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillHeight: true
                    implicitWidth: 1
                    visible: awayList.people.length > 0 && root.agenda.tasks.length > 0
                    color: root.lineColor
                }

                // Open Google Tasks, overdue first.
                ColumnLayout {
                    id: tasks
                    Layout.preferredWidth: awayList.people.length > 0 ? Kirigami.Units.gridUnit * 9 : -1
                    Layout.fillWidth: awayList.people.length === 0
                    Layout.alignment: Qt.AlignTop
                    visible: root.agenda.tasks.length > 0
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.Label {
                        text: i18np("1 open task", "%1 open tasks", root.agenda.tasks.length)
                        color: root.titleColor
                        font.pointSize: root.textSize
                        font.weight: Font.DemiBold
                    }

                    Repeater {
                        model: root.agenda.tasks
                        delegate: PlasmaComponents.ItemDelegate {
                            id: task
                            required property var modelData
                            readonly property bool overdue: modelData.due !== "" && new Date(modelData.due + "T23:59:59").getTime() < root.now
                            Layout.fillWidth: true
                            leftPadding: 0
                            onClicked: Qt.openUrlExternally(modelData.link)
                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                Kirigami.Icon {
                                    Layout.alignment: Qt.AlignTop
                                    source: "checkbox"
                                    implicitWidth: Kirigami.Units.iconSizes.small
                                    implicitHeight: implicitWidth
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    PlasmaComponents.Label {
                                        Layout.fillWidth: true
                                        text: task.modelData.title
                                        elide: Text.ElideRight
                                    }
                                    PlasmaComponents.Label {
                                        visible: task.modelData.due !== ""
                                        text: {
                                            const d = new Date(task.modelData.due + "T12:00:00");
                                            const date = Qt.formatDate(d, d.getFullYear() === new Date(root.now).getFullYear() ? "d MMM" : "d MMM yyyy");
                                            return task.overdue ? i18n("Overdue %1", date) : i18n("Due %1", date);
                                        }
                                        font.pointSize: root.smallSize
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
        }
    }
}
