// SPDX-License-Identifier: GPL-3.0-or-later
// Original work for sddm-authelia-passkey. Not derived from any
// Debian Breeze or KDE theme source - see theme/native/PROVENANCE.md.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC2

// v1.9.0 Native Theme Foundation: an intentional placeholder
// affordance only. It never talks to the broker, never renders a QR
// code, and never claims a login occurred - the full QR/device-code/
// approval flow is deferred to v1.10.0 (Native Theme Feature Parity).
// Wording here must stay unambiguous: this is a preview of where that
// flow will live, not the flow itself, and the password field remains
// the real, working login path in this release.
Rectangle {
    id: root

    property bool open: false

    signal closeRequested()

    visible: opacity > 0.01
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 150 } }

    radius: 14
    color: Qt.rgba(0.10, 0.12, 0.16, 0.96)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.12)

    Keys.onEscapePressed: root.closeRequested()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: qsTr("Smartphone-Login (Vorschau)")
                color: "white"
                font.bold: true
                font.pixelSize: 16
            }
            QQC2.ToolButton {
                text: qsTr("Schliessen")
                onClicked: root.closeRequested()
            }
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: "white"
            opacity: 0.85
            text: qsTr("Diese native Ansicht ist experimentell (v1.9.0 Foundation). Der vollständige QR-/Gerätecode-Ablauf folgt in einer späteren Version. Es wurde noch keine Anmeldung durchgeführt.")
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: "white"
            font.bold: true
            text: qsTr("Bitte weiterhin mit Passwort anmelden.")
        }

        Item { Layout.fillHeight: true }
    }
}
