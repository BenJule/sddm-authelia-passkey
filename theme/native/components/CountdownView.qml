// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC2

ColumnLayout {
    id: root

    property int remainingSeconds: 0
    property int totalSeconds: 0

    spacing: 5

    readonly property real fraction:
        totalSeconds > 0
            ? Math.max(
                0,
                Math.min(
                    1,
                    remainingSeconds
                        / totalSeconds
                )
            )
            : 0

    function formatted(value) {
        var safe =
            Math.max(
                0,
                value
            )

        var minutes =
            Math.floor(
                safe / 60
            )

        var seconds =
            safe % 60

        return minutes
            + ":"
            + (
                seconds < 10
                    ? "0"
                    : ""
            )
            + seconds
    }

    RowLayout {
        Layout.fillWidth: true

        QQC2.Label {
            Layout.fillWidth: true

            text:
                qsTr(
                    "Verbleibende Zeit"
                )

            color: "#7d8fa2"

            font.pixelSize: 9
        }

        QQC2.Label {
            text:
                root.formatted(
                    root.remainingSeconds
                )

            color: "#edf4fb"

            font.pixelSize: 10
            font.bold: true
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 5

        radius: 3

        color: Qt.rgba(1, 1, 1, 0.075)

        Rectangle {
            width:
                parent.width
                * root.fraction

            height: parent.height

            radius: parent.radius

            color: "#4f91f7"

            Behavior on width {
                NumberAnimation {
                    duration: 200
                }
            }
        }
    }
}
