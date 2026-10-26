// One person who is away today: a round initial in the status colour (red out, blue home,
// grey for long leave or part-time hours), the first name, and until when. Click opens the
// absence entry.

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

PlasmaComponents.ItemDelegate {
    id: cell

    property var person
    property string detail
    property color dot
    property real smallSize

    padding: Kirigami.Units.smallSpacing
    onClicked: if (person.link) Qt.openUrlExternally(person.link)

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        Rectangle {
            implicitWidth: Kirigami.Units.iconSizes.medium
            implicitHeight: implicitWidth
            radius: width / 2
            color: cell.dot
            PlasmaComponents.Label {
                anchors.centerIn: parent
                text: cell.person.name.charAt(0).toUpperCase()
                color: "white"
                font.bold: true
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: cell.person.name
                font.bold: true
                elide: Text.ElideRight
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: cell.detail
                font.pointSize: cell.smallSize
                opacity: 0.7
                elide: Text.ElideRight
            }
        }
    }

    PlasmaComponents.ToolTip {
        text: cell.person.source === "slack"
            ? i18n("Slack status: %1", cell.person.title) + (cell.person.end ? "" : "\n" + i18n("No end time set in Slack"))
            : cell.person.title
    }
}
