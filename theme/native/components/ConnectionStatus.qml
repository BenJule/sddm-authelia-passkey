// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC2

RowLayout {
    id: root

    property string connectionState: "ready"

    spacing: 7

    Accessible.role: Accessible.StatusBar
    Accessible.name:
        qsTr("Verbindungsstatus: %1").arg(
            root.labelForState(root.connectionState)
        )

    function labelForState(value) {
        switch (value) {
        case "connecting":
            return qsTr("Verbinden")
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
            return "#6aa9ff"
        case "waiting":
            return "#75c8ff"
        case "rate_limited":
            return "#e7b85c"
        case "offline":
            return "#b0b6bd"
        case "error":
            return "#ff7777"
        default:
            return "#7dd79d"
        }
    }

    Rectangle {
        Layout.preferredWidth: 9
        Layout.preferredHeight: 9
        radius: 5
        color: root.colorForState(root.connectionState)
        Accessible.ignored: true
    }

    QQC2.Label {
        text: root.labelForState(root.connectionState)
        color: "white"
        opacity: 0.85
        font.pixelSize: 12
        Accessible.ignored: true
    }
}
