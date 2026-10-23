// One calendar event: a stripe in the calendar's colour, the time, the title and where.
// The event happening now is highlighted, the next one shows how long until it starts,
// and finished events are dimmed. Click opens it in Google Calendar; the camera button
// joins the Meet call.

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

PlasmaComponents.ItemDelegate {
    id: item

    required property var model
    property double now
    property bool isNext
    property string untilText
    property string timeText
    property color accentText

    readonly property bool past: model.end <= now
    readonly property bool current: !model.allDay && model.start <= now && now < model.end

    opacity: past ? 0.45 : 1
    highlighted: current
    onClicked: Qt.openUrlExternally(model.link)

    leftPadding: Kirigami.Units.largeSpacing
    rightPadding: Kirigami.Units.largeSpacing

    contentItem: RowLayout {
        spacing: Kirigami.Units.largeSpacing

        Rectangle {
            Layout.fillHeight: true
            implicitWidth: Kirigami.Units.smallSpacing
            radius: width / 2
            color: item.model.color || Kirigami.Theme.highlightColor
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents.Label {
                    text: item.timeText
                    font.features: { "tnum": 1 }
                    opacity: 0.8
                }
                PlasmaComponents.Label {
                    visible: item.isNext || item.current
                    text: item.current ? i18n("now") : item.untilText
                    color: item.accentText
                    font.bold: true
                }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: item.model.title
                font.bold: item.isNext || item.current
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: item.model.location
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                elide: Text.ElideRight
            }
        }

        PlasmaComponents.ToolButton {
            visible: item.model.meet !== "" && !item.past
            icon.name: "camera-web"
            onClicked: Qt.openUrlExternally(item.model.meet)
            PlasmaComponents.ToolTip { text: i18n("Join the Google Meet call") }
        }
    }
}
