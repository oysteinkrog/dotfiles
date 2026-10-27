// The top card: the meeting going on now, or the next one. Title, time, how long until it
// starts, a button to join the Meet call, and the shorter meetings that overlap it. Click
// the card to open the event in Google Calendar.

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

Rectangle {
    id: card

    property var event: null
    property bool isNow
    property var overlaps: []
    property string whenText
    property color accent
    property color accentText
    property color textOnAccent
    property real textSize
    property color cardColor
    property color borderColor

    readonly property bool hasEvent: event !== null

    implicitHeight: content.implicitHeight + Kirigami.Units.largeSpacing * 2
    // The hero card of the shared panel style: a neutral card with a faint accent tint and a
    // 3 px accent bar on the left.
    radius: 6
    color: Kirigami.ColorUtils.tintWithAlpha(cardColor, accent, area.containsMouse ? 0.13 : 0.08)
    border.width: 1
    border.color: borderColor
    clip: true

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 1
        width: 3
        color: card.accent
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (card.hasEvent) Qt.openUrlExternally(card.event.link)
    }

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        anchors.leftMargin: Kirigami.Units.largeSpacing + 3
        spacing: Kirigami.Units.largeSpacing * 2

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                text: card.isNow ? i18n("NOW") : i18n("NEXT MEETING")
                color: card.accentText
                font.bold: true
                font.letterSpacing: 1
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: card.hasEvent ? card.event.title : ""
                font.pointSize: card.textSize * 1.6
                font.bold: true
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            RowLayout {
                spacing: Kirigami.Units.largeSpacing
                PlasmaComponents.Label {
                    text: card.hasEvent ? Qt.formatTime(new Date(card.event.start), "HH:mm") + "–" + Qt.formatTime(new Date(card.event.end), "HH:mm") : ""
                    font.pointSize: card.textSize * 1.2
                    font.features: { "tnum": 1 }
                }
                PlasmaComponents.Label {
                    text: card.whenText
                    color: card.accentText
                    font.bold: true
                    font.pointSize: card.textSize * 1.2
                }
            }
            PlasmaComponents.Button {
                id: join
                visible: card.hasEvent && card.event.meet !== ""
                text: i18n("Join")
                icon.name: "camera-video-symbolic"
                leftPadding: Kirigami.Units.largeSpacing * 2
                rightPadding: Kirigami.Units.largeSpacing * 2
                topPadding: Kirigami.Units.smallSpacing * 2
                bottomPadding: Kirigami.Units.smallSpacing * 2
                onClicked: Qt.openUrlExternally(card.event.meet)
                // Text and icon in the theme's colour for text on the accent.
                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Icon {
                        source: join.icon.name
                        color: card.textOnAccent
                        isMask: true
                        implicitWidth: Kirigami.Units.iconSizes.small
                        implicitHeight: implicitWidth
                    }
                    PlasmaComponents.Label {
                        text: join.text
                        color: card.textOnAccent
                        font.pointSize: card.textSize
                    }
                }
                background: Rectangle {
                    radius: Kirigami.Units.cornerRadius
                    color: join.down ? Qt.darker(card.accent, 1.2) : join.hovered ? Qt.lighter(card.accent, 1.15) : card.accent
                }
                PlasmaComponents.ToolTip {
                    text: i18n("Join the Google Meet call")
                }
            }
        }

        Kirigami.Separator {
            Layout.fillHeight: true
            visible: card.overlaps.length > 0
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignTop
            Layout.maximumWidth: card.width * 0.45
            visible: card.overlaps.length > 0
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                text: i18np("1 meeting overlaps", "%1 meetings overlap", card.overlaps.length)
                color: card.accentText
                font.bold: true
                font.pointSize: card.textSize
            }
            Repeater {
                model: card.overlaps
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing
                    PlasmaComponents.Label {
                        text: Qt.formatTime(new Date(modelData.start), "HH:mm") + "–" + Qt.formatTime(new Date(modelData.end), "HH:mm")
                        font.pointSize: card.textSize
                        font.features: { "tnum": 1 }
                        opacity: 0.8
                    }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: modelData.title
                        font.pointSize: card.textSize
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
