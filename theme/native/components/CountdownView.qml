// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC2

ColumnLayout {
    id: root

    property int remainingSeconds: 0
    property int totalSeconds: 0

    readonly property real fraction:
        totalSeconds > 0
            ? Math.max(
                0,
                Math.min(1, remainingSeconds / totalSeconds)
            )
            : 0

    spacing: 4

    function formatted(seconds) {
        var safe = Math.max(0, seconds)
        var minutes = Math.floor(safe / 60)
        var secs = safe % 60

        return minutes
            + ":"
            + (secs < 10 ? "0" : "")
            + secs
    }

    RowLayout {
        Layout.fillWidth: true

        QQC2.Label {
            Layout.fillWidth: true
            text: qsTr("Verbleibende Zeit")
            color: "white"
            opacity: 0.72
            font.pixelSize: 11
            Accessible.ignored: true
        }

        QQC2.Label {
            text: root.formatted(root.remainingSeconds)
            color: "white"
            font.pixelSize: 12
            font.bold: true
            Accessible.ignored: true
        }
    }

    QQC2.ProgressBar {
        id: countdownProgress

        Layout.fillWidth: true
        from: 0
        to: 1
        value: root.fraction

        Accessible.role: Accessible.ProgressBar
        Accessible.name: qsTr("Verbleibende Zeit")
        Accessible.description:
            qsTr("%1 verbleibend").arg(
                root.formatted(root.remainingSeconds)
            )
    }
}
