// A day's header in the agenda list: the day and date, a strip showing booked time over the
// working day, the booked hours, and how many events the day has.

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

Rectangle {
    id: header

    property double dayKey
    property string label
    property var info: null
    property string durationText
    property int stripFrom
    property int stripTo
    property color busyColor
    property color accentText
    property real textSize
    property real smallSize

    implicitHeight: row.implicitHeight + Kirigami.Units.smallSpacing * 2
    color: Kirigami.Theme.alternateBackgroundColor

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.largeSpacing
        anchors.rightMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        PlasmaComponents.Label {
            text: header.label
            color: header.accentText
            font.bold: true
            font.pointSize: header.textSize
        }
        PlasmaComponents.Label {
            text: Qt.formatDate(new Date(header.dayKey), "d MMMM")
            font.pointSize: header.textSize
            opacity: 0.7
        }

        Item {
            Layout.fillWidth: true
        }

        // Booked time between stripFrom and stripTo o'clock as segments on a track.
        Rectangle {
            id: track
            readonly property double from: header.dayKey + header.stripFrom * 3600000
            readonly property double span: (header.stripTo - header.stripFrom) * 3600000
            Layout.preferredWidth: Kirigami.Units.gridUnit * 9
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: Math.round(Kirigami.Units.smallSpacing * 1.5)
            radius: height / 2
            color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.1)

            Repeater {
                model: header.info ? header.info.busy : []
                delegate: Rectangle {
                    required property var modelData
                    readonly property double s: Math.max(modelData[0], track.from)
                    readonly property double e: Math.min(modelData[1], track.from + track.span)
                    visible: e > s
                    x: (s - track.from) / track.span * track.width
                    width: Math.max(2, (e - s) / track.span * track.width)
                    height: track.height
                    radius: track.radius
                    color: header.busyColor
                }
            }
            PlasmaComponents.ToolTip {
                text: i18n("Booked time %1:00 to %2:00", header.stripFrom, header.stripTo)
            }
            HoverHandler {}
        }

        PlasmaComponents.Label {
            Layout.minimumWidth: Kirigami.Units.gridUnit * 4.5
            horizontalAlignment: Text.AlignRight
            text: header.info && header.info.minutes > 0 ? header.durationText : ""
            color: header.busyColor
            font.pointSize: header.smallSize
            font.features: { "tnum": 1 }
        }
        PlasmaComponents.Label {
            Layout.minimumWidth: Kirigami.Units.gridUnit * 4
            horizontalAlignment: Text.AlignRight
            text: header.info ? i18np("1 event", "%1 events", header.info.count) : ""
            font.pointSize: header.smallSize
            opacity: 0.6
        }
    }
}
