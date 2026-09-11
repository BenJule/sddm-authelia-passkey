// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC2

Rectangle {
    id: root

    property string connectionState: "ready"

    implicitWidth:
        statusRow.implicitWidth + 18

    implicitHeight: 27

    radius: 14

    color: Qt.rgba(0.045, 0.07, 0.10, 0.84)

    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)

    function labelForState(value) {
        switch (value) {
        case "connecting":
            return qsTr("Verbindung")
        case "waiting":
            return qsTr("Wartet")
        case "rate_limited":
            return qsTr("Kurz warten")
        case "offline":
            return qsTr("Offline")
        case "error":
            return qsTr("Fehler")
        default:
            return qsTr("Bereit")
        }
    }

    function colorForState(value) {
        switch (value) {
        case "connecting":
            return "#67a8ff"
        case "waiting":
            return "#65c9ff"
        case "rate_limited":
            return "#e8b85b"
        case "offline":
            return "#a2aebb"
        case "error":
            return "#ff7777"
        default:
            return "#72da98"
        }
    }

    RowLayout {
        id: statusRow

        anchors.centerIn: parent

        spacing: 6

        Rectangle {
            Layout.preferredWidth: 7
            Layout.preferredHeight: 7

            radius: 4

            color:
                root.colorForState(
                    root.connectionState
                )
        }

        QQC2.Label {
            text:
                root.labelForState(
                    root.connectionState
                )

            color: "#d7e2ed"

            font.pixelSize: 10
            font.weight: Font.Medium
        }
    }
}
