// One calendar event: the time, a dot in the calendar's colour, the title and where. The
// next event shows how long until it starts, events that overlap the top card's meeting are
// indented under it, and finished events are dimmed. A thin line with the time can sit above
// the row to mark now. Click opens it in Google Calendar; the camera button joins the call.

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

PlasmaComponents.ItemDelegate {
    id: item

    required property var model
    required property int index
    property double now
    property bool isNext
    property bool isFocus
    property bool overlapsFocus
    property bool nowLineAbove
    property string untilText
    property string timeText
    property color accent
    property color accentText
    property real textSize
    property real smallSize

    readonly property bool past: model.end <= now
    readonly property bool current: !model.allDay && model.start <= now && now < model.end
    readonly property int indent: overlapsFocus ? Kirigami.Units.gridUnit * 1.5 : 0
    readonly property int nowLineHeight: nowLineAbove ? nowLabel.implicitHeight : 0

    onClicked: Qt.openUrlExternally(model.link)

    topPadding: Kirigami.Units.smallSpacing + nowLineHeight
    bottomPadding: Kirigami.Units.smallSpacing
    leftPadding: Kirigami.Units.largeSpacing + indent
    rightPadding: Kirigami.Units.largeSpacing

    background: Item {
        // A faint row tint and a bar on the left for the top card's meeting.
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: item.nowLineHeight
            visible: item.isFocus || item.hovered
            color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, item.accent, item.hovered ? 0.13 : 0.08)
        }
        Rectangle {
            visible: item.isFocus
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: item.nowLineHeight
            width: 3
            color: item.accent
        }
        // The bracket that joins an overlapping event to the meeting above it.
        Rectangle {
            visible: item.overlapsFocus
            x: Kirigami.Units.largeSpacing + Kirigami.Units.gridUnit * 0.6
            y: 0
            width: 1
            height: parent.height / 2
            color: Kirigami.Theme.disabledTextColor
        }
        Rectangle {
            visible: item.overlapsFocus
            x: Kirigami.Units.largeSpacing + Kirigami.Units.gridUnit * 0.6
            y: parent.height / 2
            width: Kirigami.Units.gridUnit * 0.6
            height: 1
            color: Kirigami.Theme.disabledTextColor
        }
        // The now line: a hairline with the time, kept quiet so it does not compete with
        // the next meeting.
        RowLayout {
            visible: item.nowLineAbove
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: item.nowLineHeight
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents.Label {
                id: nowLabel
                Layout.leftMargin: Kirigami.Units.largeSpacing
                text: Qt.formatTime(new Date(item.now), "HH:mm")
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: item.accentText
                opacity: 0.6
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.rightMargin: Kirigami.Units.largeSpacing
                implicitHeight: 1
                color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, item.accentText, 0.35)
            }
        }
    }

    contentItem: RowLayout {
        spacing: Kirigami.Units.largeSpacing
        opacity: item.past ? 0.45 : 1

        // Time on the left in a fixed-width column, so titles line up beside it.
        PlasmaComponents.Label {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: timeWidth.width + Kirigami.Units.smallSpacing
            text: item.timeText
            font.pointSize: item.textSize
            font.features: { "tnum": 1 }
            opacity: 0.8

            TextMetrics {
                id: timeWidth
                font.family: Kirigami.Theme.defaultFont.family
                font.pointSize: item.textSize
                text: "00:00–00:00"
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: (titleLabel.implicitHeight - height) / 2
            implicitWidth: Kirigami.Units.smallSpacing * 2
            implicitHeight: implicitWidth
            radius: width / 2
            color: item.model.color || Kirigami.Theme.highlightColor
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 0

            PlasmaComponents.Label {
                id: titleLabel
                Layout.fillWidth: true
                text: item.model.title
                font.pointSize: item.textSize
                font.bold: item.isFocus
                elide: Text.ElideRight
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: item.model.location
                font.pointSize: item.smallSize
                opacity: 0.6
                elide: Text.ElideRight
            }
        }

        Kirigami.Icon {
            Layout.alignment: Qt.AlignTop
            visible: item.model.meet !== ""
            source: "camera-video-symbolic"
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: implicitWidth
            opacity: 0.7
            TapHandler {
                enabled: !item.past
                onTapped: Qt.openUrlExternally(item.model.meet)
            }
            PlasmaComponents.ToolTip {
                text: i18n("Join the Google Meet call")
            }
            HoverHandler {
                cursorShape: Qt.PointingHandCursor
            }
        }

        PlasmaComponents.Label {
            Layout.alignment: Qt.AlignTop
            Layout.minimumWidth: Kirigami.Units.gridUnit * 4
            horizontalAlignment: Text.AlignRight
            visible: text !== ""
            text: item.current ? i18n("now") : item.isNext ? item.untilText : item.overlapsFocus ? i18n("Overlaps") : ""
            color: item.current || item.isNext ? item.accentText : Kirigami.Theme.textColor
            font.bold: item.current || item.isNext
            font.pointSize: item.current || item.isNext ? item.textSize : item.smallSize
            opacity: item.current || item.isNext ? 1 : 0.6
        }
    }
}
